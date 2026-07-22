from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

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

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


def normalize_role(role: Optional[str]) -> str:
    if role in {"admin", "worker", "user"}:
        return role
    return "user"


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    users = load_users()
    user = next((u for u in users if u["id"] == user_id), None)
    if user is None:
        raise credentials_exception
    return user


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
