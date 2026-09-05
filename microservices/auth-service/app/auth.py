from datetime import datetime, timedelta, timezone
from typing import Optional
import logging
import threading
import requests

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from jose import JWTError, jwt
from pydantic import BaseModel

from .email_utils import (
    generate_approval_token,
    generate_verification_code,
    send_admin_admission_email,
    send_admin_approval_request_email,
    send_admin_rejection_email,
    send_verification_code_email,
)
from .firebase_auth import verify_firebase_token
from .models import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    ALGORITHM,
    PENDING_SESSION_EXPIRE_MINUTES,
    SECRET_KEY,
    LoginRequest,
    PendingSessionRequest,
    RegisterRequest,
    TokenResponse,
    VerifyEmailRequest,
    is_valid_username,
    load_pending_registrations,
    load_users,
    normalize_username,
    pwd_context,
    save_pending_registrations,
    save_users,
    unique_generated_username,
)

logger = logging.getLogger(__name__)

VERIFICATION_CODE_EXPIRE_MINUTES = 15

router = APIRouter()

# FastAPI runs sync endpoints across a thread pool, so two Google sign-in
# requests for the same (new) email arriving close together could both read
# "user not found" before either one saves, creating two accounts with the
# same email but different ids. This serializes the find-or-create so the
# second request always sees the first one's write.
_users_lock = threading.Lock()


def normalize_role(role: Optional[str]) -> str:
    if role in {"admin", "worker", "user"}:
        return role
    return "user"


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# The admin/worker "waiting for approval" screen holds this instead of the
# user's password, so it can ask the server "am I approved yet?" without
# ever needing to store credentials in the client. The `purpose` claim is
# checked everywhere else (see security.py get_current_user), so this token
# only works against the one status endpoint below — it can't be used to
# access /me, social, or anything else even before the request is approved.
_PENDING_SESSION_PURPOSE = "admin_approval_status"


def create_pending_session_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "purpose": _PENDING_SESSION_PURPOSE,
        "exp": datetime.now(timezone.utc)
        + timedelta(minutes=PENDING_SESSION_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def _decode_pending_session_token(token: str) -> str:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(
            status_code=401, detail="This registration session has expired"
        ) from exc
    if payload.get("purpose") != _PENDING_SESSION_PURPOSE:
        raise HTTPException(status_code=401, detail="Invalid session token")
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid session token")
    return user_id


def _validated_available_username(
    username: str, users: list, pending: list | None = None
) -> str:
    normalized = normalize_username(username)
    if not is_valid_username(normalized):
        raise HTTPException(
            status_code=400,
            detail=(
                "Username must be 3-24 characters and use only lowercase "
                "letters, numbers, periods, or underscores."
            ),
        )
    existing = {
        normalize_username(str(entry.get("username") or ""))
        for entry in [*users, *(pending or [])]
    }
    if normalized in existing:
        raise HTTPException(status_code=400, detail="Username is already taken")
    return normalized


@router.post("/register", status_code=201)
def register(payload: RegisterRequest):
    # Usernames are a global social identifier, so validate uniqueness while
    # holding the same process-wide lock used for all account creation paths.
    with _users_lock:
        users = load_users()
        existing = next((u for u in users if u["email"] == payload.email), None)
        if existing is not None:
            if existing.get("status") != "rejected":
                raise HTTPException(status_code=400, detail="Email already registered")
            # A rejected admin request doesn't permanently lock out this email —
            # drop the stale record so a fresh registration (as admin or as a
            # regular user/worker) goes through cleanly instead of leaving two
            # entries around for the same email, which would make login() find
            # the old rejected one first forever.
            users = [u for u in users if u["email"] != payload.email]
            save_users(users)

        pending = load_pending_registrations()
        username = _validated_available_username(payload.username, users, pending)
        role = normalize_role(payload.role)

        if role in ("admin", "worker"):
            # Admin and worker signups still create the account right away —
            # the gate here is on *login*, not on storage, since a human
            # (SUPER_ADMIN_EMAIL) needs to review a real request, not a
            # one-time code the requester types straight back in themselves.
            user_id = str(__import__("uuid").uuid4())
            user = {
                "id": user_id,
                "email": payload.email,
                "full_name": payload.full_name,
                "username": username,
                "role": role,
                "hashed_password": pwd_context.hash(payload.password),
                "preferences": [],
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            token = generate_approval_token()
            user["status"] = "pending_admin_approval"
            user["admin_approval_token"] = token
            user["email_verified"] = True
            users.append(user)
            save_users(users)
            send_admin_approval_request_email(
                user_id, payload.email, payload.full_name, token, role=role
            )
            return {
                "id": user_id,
                "email": payload.email,
                "full_name": payload.full_name,
                "role": role,
                "status": "pending_admin_approval",
                # The client holds onto this to poll for approval — so the
                # registration screen can flip straight into the signed-in
                # app the moment the super admin clicks approve, instead of
                # sending the user back to the login screen to retype
                # credentials they just typed.
                "pending_session_token": create_pending_session_token(user_id),
            }

        # Regular user signups: nothing is written to users.json yet.
        # The email + hashed password sit in a separate pending store until the
        # code is confirmed, so a mistyped or fake email never leaves a real,
        # usable credential in the database.
        pending = [p for p in pending if p["email"] != payload.email]
        code = generate_verification_code()
        pending.append(
            {
                "email": payload.email,
                "full_name": payload.full_name,
                "username": username,
                "role": role,
                "hashed_password": pwd_context.hash(payload.password),
                "code": code,
                "expires": (
                    datetime.now(timezone.utc)
                    + timedelta(minutes=VERIFICATION_CODE_EXPIRE_MINUTES)
                ).isoformat(),
            }
        )
        save_pending_registrations(pending)
        send_verification_code_email(payload.email, payload.full_name, code)
        return {
            "id": "",
            "email": payload.email,
            "full_name": payload.full_name,
            "role": role,
            "status": "pending_verification",
        }


@router.post("/verify-email", response_model=TokenResponse)
def verify_email(payload: VerifyEmailRequest):
    with _users_lock:
        pending = load_pending_registrations()
        entry = next((p for p in pending if p["email"] == payload.email), None)
        if entry is None:
            raise HTTPException(
                status_code=404,
                detail="No pending registration for that email. Register again to get a new code.",
            )

        expires_raw = entry.get("expires")
        expired = not expires_raw or datetime.now(timezone.utc) > datetime.fromisoformat(expires_raw)
        if expired:
            save_pending_registrations(
                [p for p in pending if p["email"] != payload.email]
            )
            raise HTTPException(
                status_code=400,
                detail="This code has expired. Request a new one by registering again.",
            )
        if payload.code != entry.get("code"):
            raise HTTPException(status_code=400, detail="Incorrect code")

        users = load_users()
        if any(u["email"] == payload.email for u in users):
            save_pending_registrations(
                [p for p in pending if p["email"] != payload.email]
            )
            raise HTTPException(status_code=400, detail="Email already registered")

        # Code matches — this is the one point where a verified email actually
        # becomes a stored account.
        user_id = str(__import__("uuid").uuid4())
        entry_username = entry.get("username")
        if not entry_username:
            used_usernames = {
                normalize_username(str(existing.get("username") or ""))
                for existing in users
            }
            entry_username = unique_generated_username(
                entry["email"].split("@", 1)[0], used_usernames
            )
        user = {
            "id": user_id,
            "email": entry["email"],
            "full_name": entry["full_name"],
            "username": entry_username,
            "role": entry["role"],
            "hashed_password": entry["hashed_password"],
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
            "email_verified": True,
        }
        users.append(user)
        save_users(users)
        save_pending_registrations([p for p in pending if p["email"] != payload.email])

        token = create_access_token({"sub": user_id, "role": user["role"]})
        return TokenResponse(
            access_token=token,
            role=user["role"],
            user_id=user_id,
            full_name=user["full_name"],
            username=user["username"],
            email=user["email"],
            avatar_url=None,
        )


def _find_pending_admin(user_id: str, token: str) -> dict:
    users = load_users()
    user = next((u for u in users if u["id"] == user_id), None)
    if (
        user is None
        or user.get("status") != "pending_admin_approval"
        or user.get("admin_approval_token") != token
    ):
        raise HTTPException(status_code=404, detail="Request not found or already handled")
    return users


_APPROVAL_PAGE = """
<html><body style="font-family: sans-serif; text-align:center; padding: 60px;">
<h2>{heading}</h2><p>{message}</p>
</body></html>
"""


@router.get("/admin-requests/{user_id}/approve", response_class=HTMLResponse)
def approve_admin_request(user_id: str, token: str):
    users = _find_pending_admin(user_id, token)
    user = next(u for u in users if u["id"] == user_id)
    role = user.get("role", "admin")
    user["status"] = "active"
    user.pop("admin_approval_token", None)
    save_users(users)
    send_admin_admission_email(user["email"], user["full_name"], role=role)
    role_label = "worker" if role == "worker" else "admin"
    return _APPROVAL_PAGE.format(
        heading=f"{role_label.capitalize()} request approved",
        message=f"{user['full_name']} ({user['email']}) can now sign in as a {role_label}.",
    )


@router.get("/admin-requests/{user_id}/reject", response_class=HTMLResponse)
def reject_admin_request(user_id: str, token: str):
    users = _find_pending_admin(user_id, token)
    user = next(u for u in users if u["id"] == user_id)
    role = user.get("role", "admin")
    # Rejecting removes the account outright rather than just marking it
    # rejected — the email is freed up immediately (no stale record left
    # to clean up later), and since the record's gone, any future login
    # attempt with these credentials fails exactly like it would for an
    # email that was never registered, landing back on the login screen.
    users = [u for u in users if u["id"] != user_id]
    save_users(users)
    send_admin_rejection_email(user["email"], user["full_name"], role=role)
    role_label = "worker" if role == "worker" else "admin"
    return _APPROVAL_PAGE.format(
        heading=f"{role_label.capitalize()} request rejected",
        message=f"{user['full_name']} ({user['email']}) has been notified.",
    )


@router.post("/admin-requests/status")
def check_admin_request_status(payload: PendingSessionRequest):
    """
    Called by the register screen while the user is on the "pending admin
    approval" screen. As soon as the super admin clicks the approve link,
    the next poll here returns the same TokenResponse shape login()
    returns — so the client can flip straight into the signed-in app
    without ever prompting the user to type their password again.

    While still pending, returns {"status": "pending"}.
    If the request was rejected, the user record is gone (reject_admin_request
    deletes it), so this returns {"status": "rejected"} and the client
    surfaces the rejection message locally.
    """
    user_id = _decode_pending_session_token(payload.pending_session_token)
    users = load_users()
    user = next((u for u in users if u["id"] == user_id), None)

    if user is None:
        # reject_admin_request deletes the record outright, so a missing
        # user for a still-valid session token means the request was
        # rejected while the client was polling.
        return {"status": "rejected"}

    status_value = user.get("status", "active")
    if status_value == "pending_admin_approval":
        return {"status": "pending"}

    # Any non-pending state (currently only "active") means approved —
    # mint a real access token exactly like login() does so the client
    # uses the same authenticated path from this point on.
    access_token = create_access_token(
        {"sub": user["id"], "role": user.get("role", "user")}
    )
    return {
        "status": "approved",
        "access_token": access_token,
        "token_type": "bearer",
        "role": user.get("role", "user"),
        "user_id": user["id"],
        "email": user["email"],
        "full_name": user["full_name"],
        "username": user.get("username", ""),
        "avatar_url": user.get("avatar_url"),
    }


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest):
    users = load_users()
    user = next((u for u in users if u["email"] == payload.email), None)
    if not user or not pwd_context.verify(payload.password, user["hashed_password"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    # .get(..., True) / .get(..., "active"): accounts created before this
    # feature existed have neither field set at all, and should keep
    # working exactly as before — only new signups actually go through
    # verification/approval.
    if not user.get("email_verified", True):
        raise HTTPException(status_code=403, detail="Please verify your email first")
    if user.get("role") in ("admin", "worker") and user.get("status", "active") != "active":
        role_label = "worker" if user.get("role") == "worker" else "admin"
        raise HTTPException(
            status_code=403,
            detail=f"Your {role_label} request is still pending approval",
        )

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
        username=user["username"],
        avatar_url=user.get("avatar_url"),
    )


class FirebaseTokenRequest(BaseModel):
    id_token: str


@router.post("/auth/google", response_model=TokenResponse)
def login_with_google(payload: FirebaseTokenRequest):
    """
    Accepts either a Firebase ID token OR a Google access token.
    Verifies it and finds-or-creates a matching user.
    """
    token = payload.id_token
    logger.info(f"Received token, length: {len(token)}")

    claims = None

    # Try 1: Verify as Firebase ID token
    try:
        claims = verify_firebase_token(token)
        logger.info(f"✅ Verified as Firebase ID token for: {claims.get('email')}")
    except Exception as e:
        logger.info(f"Not a Firebase ID token, trying as Google access token: {e}")

        # Try 2: Verify as Google access token
        try:
            response = requests.get(
                f"https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={token}"
            )
            if response.status_code != 200:
                logger.error(f"Google token verification failed: {response.text}")
                raise HTTPException(status_code=401, detail="Invalid Google token")

            token_info = response.json()
            logger.info(f"✅ Verified as Google access token for: {token_info.get('email')}")

            claims = {
                'uid': token_info.get('sub'),
                'email': token_info.get('email'),
                'name': token_info.get('name'),
                'picture': token_info.get('picture'),
            }
        except Exception as e2:
            logger.error(f"❌ Token verification failed: {e2}")
            raise HTTPException(status_code=401, detail="Invalid token")

    if not claims:
        raise HTTPException(status_code=401, detail="Token verification failed")

    email = claims.get("email")
    if not email:
        raise HTTPException(
            status_code=400,
            detail="This sign-in provider did not share an email address",
        )

    full_name = claims.get("name") or email.split("@")[0]
    firebase_uid = claims.get("uid")

    with _users_lock:
        users = load_users()
        user = next((u for u in users if u["email"] == email), None)

        if user is None:
            used_usernames = {
                normalize_username(str(existing.get("username") or ""))
                for existing in users
            }
            user = {
                "id": str(__import__("uuid").uuid4()),
                "email": email,
                "full_name": full_name,
                "username": unique_generated_username(
                    email.split("@", 1)[0], used_usernames
                ),
                "role": "user",
                "hashed_password": None,
                "firebase_uid": firebase_uid,
                # Google already proved this address belongs to them —
                # the code-verification flow is specifically for
                # email/password signups, where that isn't established.
                "email_verified": True,
                "preferences": [],
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            users.append(user)
            save_users(users)
            logger.info(f"✅ Created new user: {email}")
        elif not user.get("firebase_uid"):
            user["firebase_uid"] = firebase_uid
            save_users(users)
            logger.info(f"✅ Updated existing user with firebase_uid: {email}")
        elif not user.get("username"):
            used_usernames = {
                normalize_username(str(existing.get("username") or ""))
                for existing in users
                if existing["id"] != user["id"]
            }
            user["username"] = unique_generated_username(
                email.split("@", 1)[0], used_usernames
            )
            save_users(users)
        else:
            logger.info(f"✅ Existing user signed in: {email}")

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
        username=user["username"],
        avatar_url=user.get("avatar_url"),
    )
