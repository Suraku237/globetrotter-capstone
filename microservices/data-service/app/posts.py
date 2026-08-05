import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from .models import CommentCreate, DATA_DIR, load_posts, save_posts
from .security import get_current_user

router = APIRouter()

IMAGES_DIR = DATA_DIR / "images" / "posts"


@router.get("/posts")
def get_posts(current_user: dict = Depends(get_current_user)):
    posts = load_posts()
    return sorted(posts, key=lambda p: p["created_at"], reverse=True)


@router.post("/posts", status_code=201)
async def create_post(
    text: str = Form(...),
    image: Optional[UploadFile] = File(None),
    current_user: dict = Depends(get_current_user),
):
    image_path = None
    if image is not None and image.filename:
        IMAGES_DIR.mkdir(parents=True, exist_ok=True)
        extension = image.filename.rsplit(".", 1)[-1].lower() or "jpg"
        filename = f"{uuid.uuid4().hex}.{extension}"
        contents = await image.read()
        with open(IMAGES_DIR / filename, "wb") as f:
            f.write(contents)
        image_path = f"/images/posts/{filename}"

    post = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "author_name": current_user["full_name"],
        "author_avatar": current_user.get("avatar_url"),
        "text": text,
        "image": image_path,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "likes": [],
        "comments": [],
    }
    posts = load_posts()
    posts.append(post)
    save_posts(posts)
    return post


@router.post("/posts/{post_id}/like")
def like_post(post_id: str, current_user: dict = Depends(get_current_user)):
    posts = load_posts()
    post = next((p for p in posts if p["id"] == post_id), None)
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    user_id = current_user["id"]
    if user_id in post["likes"]:
        post["likes"].remove(user_id)
    else:
        post["likes"].append(user_id)
    save_posts(posts)
    return post


@router.post("/posts/{post_id}/comments", status_code=201)
def add_comment(
    post_id: str,
    payload: CommentCreate,
    current_user: dict = Depends(get_current_user),
):
    posts = load_posts()
    post = next((p for p in posts if p["id"] == post_id), None)
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    comment = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "author_name": current_user["full_name"],
        "text": payload.text,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    post["comments"].append(comment)
    save_posts(posts)
    return post
