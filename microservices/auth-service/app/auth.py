from datetime import datetime, timedelta, timezone
from typing import Optional
import logging
import threading
import requests

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from jose import jwt
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
    SECRET_KEY,
    LoginRequest,
    RegisterRequest,
    TokenResponse,
    VerifyEmailRequest,
    load_users,
    pwd_context,
    save_users,
)

logger = logging.getLogger(__name__)

VERIFICATION_CODE_EXPIRE_MINUTES = 15

router = APIRouter()

# FastAPI runs sync endpoints across a thread pool, so two Google sign-in
# requests for the same (new) email arriving close together could both read
# "user not found" before either one saves, creating two accounts with the
# same email but different ids. This serializes the find-or-create so the
# second request always sees the first one's write.
_google_signin_lock = threading.Lock()


def normalize_role(role: Optional[str]) -> str:
    if role in {"admin", "worker", "user"}:
        return role
    return "user"


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


@router.post("/register", status_code=201)
def register(payload: RegisterRequest):
    users = load_users()
    if any(u["email"] == payload.email for u in users):
        raise HTTPException(status_code=400, detail="Email already registered")

    role = normalize_role(payload.role)
    user_id = str(__import__("uuid").uuid4())
    user = {
        "id": user_id,
        "email": payload.email,
        "full_name": payload.full_name,
        "role": role,
        "hashed_password": pwd_context.hash(payload.password),
        "preferences": [],
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    if role == "admin":
        # Doesn't self-activate — needs a human (SUPER_ADMIN_EMAIL) to click
        # approve/reject in the notification email. Skips the regular
        # email-verification code entirely since approval already proves
        # someone reviewed this request.
        token = generate_approval_token()
        user["status"] = "pending_admin_approval"
        user["admin_approval_token"] = token
        user["email_verified"] = True
        users.append(user)
        save_users(users)
        send_admin_approval_request_email(user_id, payload.email, payload.full_name, token)
        return {
            "id": user_id,
            "email": payload.email,
            "full_name": payload.full_name,
            "role": role,
            "status": "pending_admin_approval",
        }

    code = generate_verification_code()
    user["email_verified"] = False
    user["verification_code"] = code
    user["verification_code_expires"] = (
        datetime.now(timezone.utc) + timedelta(minutes=VERIFICATION_CODE_EXPIRE_MINUTES)
    ).isoformat()
    users.append(user)
    save_users(users)
    send_verification_code_email(payload.email, payload.full_name, code)
    return {
        "id": user_id,
        "email": payload.email,
        "full_name": payload.full_name,
        "role": role,
        "status": "pending_verification",
    }


@router.post("/verify-email", response_model=TokenResponse)
def verify_email(payload: VerifyEmailRequest):
    users = load_users()
    user = next((u for u in users if u["email"] == payload.email), None)
    if user is None:
        raise HTTPException(status_code=404, detail="No account with that email")
    if user.get("email_verified"):
        raise HTTPException(status_code=400, detail="This email is already verified")

    expires_raw = user.get("verification_code_expires")
    expired = not expires_raw or datetime.now(timezone.utc) > datetime.fromisoformat(expires_raw)
    if expired:
        raise HTTPException(
            status_code=400,
            detail="This code has expired. Request a new one by registering again.",
        )
    if payload.code != user.get("verification_code"):
        raise HTTPException(status_code=400, detail="Incorrect code")

    user["email_verified"] = True
    user.pop("verification_code", None)
    user.pop("verification_code_expires", None)
    save_users(users)

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
        avatar_url=user.get("avatar_url"),
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
    user["status"] = "active"
    user.pop("admin_approval_token", None)
    save_users(users)
    send_admin_admission_email(user["email"], user["full_name"])
    return _APPROVAL_PAGE.format(
        heading="Admin request approved",
        message=f"{user['full_name']} ({user['email']}) can now sign in as an admin.",
    )


@router.get("/admin-requests/{user_id}/reject", response_class=HTMLResponse)
def reject_admin_request(user_id: str, token: str):
    users = _find_pending_admin(user_id, token)
    user = next(u for u in users if u["id"] == user_id)
    user["status"] = "rejected"
    user.pop("admin_approval_token", None)
    save_users(users)
    send_admin_rejection_email(user["email"], user["full_name"])
    return _APPROVAL_PAGE.format(
        heading="Admin request rejected",
        message=f"{user['full_name']} ({user['email']}) has been notified.",
    )


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
    if user.get("role") == "admin" and user.get("status", "active") != "active":
        raise HTTPException(
            status_code=403, detail="Your admin request is still pending approval"
        )

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
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

    with _google_signin_lock:
        users = load_users()
        user = next((u for u in users if u["email"] == email), None)

        if user is None:
            user = {
                "id": str(__import__("uuid").uuid4()),
                "email": email,
                "full_name": full_name,
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
        else:
            logger.info(f"✅ Existing user signed in: {email}")

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
        avatar_url=user.get("avatar_url"),
    )
