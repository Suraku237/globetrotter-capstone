import io
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image

from .models import CommentCreate, DATA_DIR, load_posts, save_posts
from .security import get_current_user

router = APIRouter()

IMAGES_DIR = DATA_DIR / "images" / "posts"

_MAX_IMAGE_WIDTH = 1600


def _compress_image(contents: bytes) -> bytes:
    img = Image.open(io.BytesIO(contents)).convert("RGB")
    if img.width > _MAX_IMAGE_WIDTH:
        ratio = _MAX_IMAGE_WIDTH / img.width
        img = img.resize((_MAX_IMAGE_WIDTH, round(img.height * ratio)), Image.LANCZOS)
    buffer = io.BytesIO()
    img.save(buffer, "JPEG", quality=80, optimize=True)
    return buffer.getvalue()


@router.get("/posts")
def get_posts(current_user: dict = Depends(get_current_user)):
    posts = load_posts()
    return sorted(posts, key=lambda p: p["created_at"], reverse=True)


async def _save_upload(upload: UploadFile) -> str:
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    contents = await upload.read()
    extension = (
        upload.filename.rsplit(".", 1)[-1].lower()
        if upload.filename and "." in upload.filename
        else ""
    )

    # Photos come straight off a phone camera at full resolution — recompress
    # so the feed isn't waiting on multi-MB downloads for something shown at
    # a few hundred pixels wide. Also normalizes formats (HEIC, PNG) that
    # browsers don't universally support into JPEG. Videos are left as-is;
    # re-encoding video needs ffmpeg, out of scope here.
    if (upload.content_type or "").startswith("image/"):
        try:
            contents = _compress_image(contents)
            extension = "jpg"
        except Exception:
            pass  # not a decodable image — fall back to storing it as-is

    filename = f"{uuid.uuid4().hex}.{extension}" if extension else uuid.uuid4().hex
    with open(IMAGES_DIR / filename, "wb") as f:
        f.write(contents)
    return f"/images/posts/{filename}"


@router.post("/posts", status_code=201)
async def create_post(
    text: str = Form(...),
    image: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
    current_user: dict = Depends(get_current_user),
):
    # A post carries at most one piece of media — if both somehow arrive,
    # the video wins since it's the richer content.
    image_path = await _save_upload(image) if image is not None and image.filename else None
    video_path = await _save_upload(video) if video is not None and video.filename else None
    if video_path:
        image_path = None

    post = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "author_name": current_user["full_name"],
        "author_avatar": current_user.get("avatar_url"),
        "text": text,
        "image": image_path,
        "video": video_path,
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
