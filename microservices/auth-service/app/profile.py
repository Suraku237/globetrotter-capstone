import uuid

from fastapi import APIRouter, Depends, File, UploadFile

from .models import DATA_DIR, UpdateProfileRequest, load_users, save_users
from .security import get_current_user

router = APIRouter(prefix="/me", tags=["profile"])

AVATARS_DIR = DATA_DIR / "images" / "avatars"


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "email": user["email"],
        "full_name": user["full_name"],
        "username": user.get("username", ""),
        "role": user.get("role", "user"),
        "avatar_url": user.get("avatar_url"),
    }


@router.get("")
def get_me(current_user: dict = Depends(get_current_user)):
    return _public_user(current_user)


@router.patch("")
def update_me(
    payload: UpdateProfileRequest,
    current_user: dict = Depends(get_current_user),
):
    users = load_users()
    user = next(u for u in users if u["id"] == current_user["id"])
    user["full_name"] = payload.full_name
    save_users(users)
    return _public_user(user)


@router.post("/avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    AVATARS_DIR.mkdir(parents=True, exist_ok=True)
    extension = (file.filename or "").rsplit(".", 1)[-1].lower() or "jpg"
    filename = f"{current_user['id']}_{uuid.uuid4().hex[:8]}.{extension}"
    contents = await file.read()
    with open(AVATARS_DIR / filename, "wb") as f:
        f.write(contents)

    users = load_users()
    user = next(u for u in users if u["id"] == current_user["id"])
    user["avatar_url"] = f"/images/avatars/{filename}"
    save_users(users)
    return _public_user(user)
