from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

from .models import ALGORITHM, SECRET_KEY, load_users

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
        # by /register) carry a "purpose" claim. A normal access token
        # never does, so any purpose value here means the caller is
        # trying to reuse a scoped token as a real session — refuse it.
        if payload.get("purpose") is not None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    users = load_users()
    user = next((u for u in users if u["id"] == user_id), None)
    if user is None:
        raise credentials_exception
    return user
