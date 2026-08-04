from datetime import datetime, timedelta, timezone
from typing import Optional
import logging
import requests

from fastapi import APIRouter, HTTPException
from jose import jwt
from pydantic import BaseModel

from .firebase_auth import verify_firebase_token
from .models import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    ALGORITHM,
    SECRET_KEY,
    LoginRequest,
    RegisterRequest,
    TokenResponse,
    load_users,
    pwd_context,
    save_users,
)

logger = logging.getLogger(__name__)

router = APIRouter()


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

    user = {
        "id": str(__import__("uuid").uuid4()),
        "email": payload.email,
        "full_name": payload.full_name,
        "role": normalize_role(payload.role),
        "hashed_password": pwd_context.hash(payload.password),
        "preferences": [],
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    users.append(user)
    save_users(users)
    return {
        "id": user["id"],
        "email": user["email"],
        "full_name": user["full_name"],
        "role": user.get("role", "user"),
    }


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest):
    users = load_users()
    user = next((u for u in users if u["email"] == payload.email), None)
    if not user or not pwd_context.verify(payload.password, user["hashed_password"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
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
    )
