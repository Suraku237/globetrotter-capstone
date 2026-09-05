from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

from .models import ALGORITHM, SECRET_KEY, load_users

# tokenUrl is informational only here (points at the gateway route that
# actually issues tokens) — this service only ever verifies them.
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


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
        # Scoped tokens (e.g. the pending-admin-approval poll token issued
        # by auth-service /register) carry a "purpose" claim. A normal
        # access token never does, so any purpose value here means the
        # caller is trying to reuse a scoped token as a real session.
        if payload.get("purpose") is not None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    users = load_users()
    user = next((u for u in users if u["id"] == user_id), None)
    if user is None:
        raise credentials_exception
    return user


def require_worker_or_admin(current_user: dict = Depends(get_current_user)) -> dict:
    if current_user.get("role") not in {"worker", "admin"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only workers and admins can do this",
        )
    return current_user


def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    if current_user.get("role") != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins can do this",
        )
    return current_user
