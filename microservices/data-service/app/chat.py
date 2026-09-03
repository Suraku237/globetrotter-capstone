"""
Community room chat — a single public thread every logged-in user can
post to. This module used to also handle 1:1 direct messages, but the
product decided a single "everyone is in the same room" model (like a
WhatsApp community/group chat) is a better fit, so all conversation-based
endpoints were removed. The old chat_conversations.json file is left in
place on disk in case an operator wants to inspect it, but nothing in the
API reads from it anymore.

WhatsApp-style features implemented on top of the plain text/sticker/audio
messages we already had:
  * Image messages (photos) — reuses the same JPEG re-compression path
    the feed uses so a phone-camera upload doesn't ship as a 5 MB file.
  * Reply-to-a-message — carries a small "preview" of the parent so the
    UI can render "▎ Kamga: …" without a second fetch.
  * Emoji reactions — a plain dict of emoji → list of user ids, so the
    client can toggle a user's own reaction with a single POST.
  * Soft delete — the sender (or an admin) can wipe a message's contents;
    the message stays in place with `deleted: true` so replies that
    pointed at it still make sense in the transcript.
  * Presence — a lightweight heartbeat endpoint clients call every few
    seconds while the room is open; GET /chat/room/presence returns the
    users seen in the last ~15 s so the header can show "Kamga, Alice
    and 3 others active now".
"""

import io
import uuid
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image
from pydantic import BaseModel

from .models import DATA_DIR, _load, _save, load_users
from .security import get_current_user

router = APIRouter(prefix="/chat", tags=["chat"])

# One file per persistent surface — the room's message list, an audio
# subdirectory for voice messages, and an image subdirectory for photos.
ROOM_FILE = DATA_DIR / "chat_room.json"
ROOM_AUDIO_DIR = DATA_DIR / "audio" / "chat_room"
ROOM_IMAGE_DIR = DATA_DIR / "images" / "chat_room"
# Presence is intentionally kept out of the room file (which is a list)
# and given its own tiny dict store — otherwise every heartbeat would
# rewrite the whole message log.
PRESENCE_FILE = DATA_DIR / "chat_room_presence.json"

# A viewer counts as "active in the room" if they've pinged within this
# window. Matches roughly two poll cycles at the client's 4 s cadence.
PRESENCE_WINDOW = timedelta(seconds=15)
# Maximum uploaded photo dimension — the same 1600 px cap the feed uses,
# recompressed to JPEG so a full-res phone shot doesn't ship as-is.
_MAX_IMAGE_WIDTH = 1600


# ---- Persistence helpers ----------------------------------------------------


def _load_room() -> list:
    return _load(ROOM_FILE)


def _save_room(messages: list) -> None:
    _save(ROOM_FILE, messages)


def _load_presence() -> dict:
    data = _load(PRESENCE_FILE)
    # _load is shared with the room's message list and defaults to `[]`
    # when the file doesn't exist yet; presence needs a dict instead.
    if isinstance(data, list):
        return {}
    return data


def _save_presence(presence: dict) -> None:
    _save(PRESENCE_FILE, presence)


# ---- Message shape ---------------------------------------------------------


def _reply_preview(parent: dict) -> dict:
    """Small denormalized snapshot of a message being replied to — kept on
    the reply itself so rendering the transcript doesn't need a second
    lookup and so a soft-delete on the parent doesn't blank the preview
    the reply was written against."""
    if parent.get("deleted"):
        excerpt = "(deleted message)"
    elif parent.get("type") == "audio":
        excerpt = "🎤 Voice message"
    elif parent.get("type") == "image":
        excerpt = "📷 Photo"
    elif parent.get("type") == "sticker":
        excerpt = parent.get("sticker") or ""
    else:
        text = parent.get("text") or ""
        excerpt = text if len(text) <= 80 else f"{text[:77]}…"
    return {
        "id": parent["id"],
        "sender_id": parent.get("sender_id"),
        "sender_name": parent.get("sender_name"),
        "excerpt": excerpt,
    }


def _new_message(sender: dict, type_: str, **fields) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "sender_id": sender["id"],
        "sender_name": sender["full_name"],
        "sender_avatar": sender.get("avatar_url"),
        "type": type_,
        "text": fields.get("text"),
        "sticker": fields.get("sticker"),
        "audio_url": fields.get("audio_url"),
        "image_url": fields.get("image_url"),
        "reply_to": fields.get("reply_to"),
        "reactions": {},
        "deleted": False,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def _find_by_id(messages: list, message_id: str) -> dict:
    msg = next((m for m in messages if m["id"] == message_id), None)
    if msg is None:
        raise HTTPException(status_code=404, detail="Message not found")
    return msg


def _resolve_reply(messages: list, reply_to_id: Optional[str]) -> Optional[dict]:
    if not reply_to_id:
        return None
    parent = next((m for m in messages if m["id"] == reply_to_id), None)
    if parent is None:
        # Silently drop an unknown reply_to id rather than 400ing — the
        # message the client was replying to may have been deleted in the
        # window between opening the reply UI and sending.
        return None
    return _reply_preview(parent)


# ---- Image handling --------------------------------------------------------


def _compress_image(contents: bytes) -> bytes:
    img = Image.open(io.BytesIO(contents)).convert("RGB")
    if img.width > _MAX_IMAGE_WIDTH:
        ratio = _MAX_IMAGE_WIDTH / img.width
        img = img.resize(
            (_MAX_IMAGE_WIDTH, round(img.height * ratio)), Image.LANCZOS
        )
    buffer = io.BytesIO()
    img.save(buffer, "JPEG", quality=80, optimize=True)
    return buffer.getvalue()


# ---- Payload models --------------------------------------------------------


class MessageCreate(BaseModel):
    type: Literal["text", "sticker"]
    content: str
    reply_to_id: Optional[str] = None


class ReactionPayload(BaseModel):
    # A single unicode emoji — the client validates non-emptiness before
    # posting, but we defensively strip below too.
    emoji: str


# ---- Endpoints -------------------------------------------------------------


@router.get("/room/messages")
def get_room_messages(current_user: dict = Depends(get_current_user)):
    return _load_room()


@router.post("/room/messages", status_code=201)
def send_room_message(
    payload: MessageCreate, current_user: dict = Depends(get_current_user)
):
    text = payload.content.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message can't be empty")

    messages = _load_room()
    reply = _resolve_reply(messages, payload.reply_to_id)
    message = _new_message(
        current_user,
        payload.type,
        text=text if payload.type == "text" else None,
        sticker=text if payload.type == "sticker" else None,
        reply_to=reply,
    )
    messages.append(message)
    _save_room(messages)
    return message


@router.post("/room/messages/audio", status_code=201)
async def send_room_audio_message(
    audio: UploadFile = File(...),
    reply_to_id: Optional[str] = Form(None),
    current_user: dict = Depends(get_current_user),
):
    ROOM_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    extension = (
        audio.filename.rsplit(".", 1)[-1].lower()
        if audio.filename and "." in audio.filename
        else "m4a"
    )
    filename = f"{uuid.uuid4().hex}.{extension}"
    contents = await audio.read()
    with open(ROOM_AUDIO_DIR / filename, "wb") as f:
        f.write(contents)

    messages = _load_room()
    reply = _resolve_reply(messages, reply_to_id)
    message = _new_message(
        current_user,
        "audio",
        audio_url=f"/audio/chat_room/{filename}",
        reply_to=reply,
    )
    messages.append(message)
    _save_room(messages)
    return message


@router.post("/room/messages/image", status_code=201)
async def send_room_image_message(
    image: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    reply_to_id: Optional[str] = Form(None),
    current_user: dict = Depends(get_current_user),
):
    ROOM_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    contents = await image.read()
    extension = "jpg"
    # Fall back to storing the file as-is if PIL can't decode it (some
    # weird HEIC variants, animated GIFs…) rather than 500ing.
    try:
        contents = _compress_image(contents)
    except Exception:
        extension = (
            image.filename.rsplit(".", 1)[-1].lower()
            if image.filename and "." in image.filename
            else "bin"
        )
    filename = f"{uuid.uuid4().hex}.{extension}"
    with open(ROOM_IMAGE_DIR / filename, "wb") as f:
        f.write(contents)

    messages = _load_room()
    reply = _resolve_reply(messages, reply_to_id)
    trimmed_caption = (caption or "").strip() or None
    message = _new_message(
        current_user,
        "image",
        image_url=f"/images/chat_room/{filename}",
        text=trimmed_caption,
        reply_to=reply,
    )
    messages.append(message)
    _save_room(messages)
    return message


@router.post("/room/messages/{message_id}/react")
def toggle_reaction(
    message_id: str,
    payload: ReactionPayload,
    current_user: dict = Depends(get_current_user),
):
    emoji = payload.emoji.strip()
    if not emoji:
        raise HTTPException(status_code=400, detail="Emoji can't be empty")

    messages = _load_room()
    msg = _find_by_id(messages, message_id)
    if msg.get("deleted"):
        raise HTTPException(
            status_code=400, detail="Can't react to a deleted message"
        )
    reactions = msg.setdefault("reactions", {})
    users_for_emoji = reactions.setdefault(emoji, [])
    my_id = current_user["id"]
    if my_id in users_for_emoji:
        # Toggle off — a second tap on your own reaction removes it, like
        # WhatsApp/Telegram/Slack.
        users_for_emoji.remove(my_id)
        if not users_for_emoji:
            del reactions[emoji]
    else:
        users_for_emoji.append(my_id)
    _save_room(messages)
    return msg


@router.delete("/room/messages/{message_id}")
def delete_room_message(
    message_id: str, current_user: dict = Depends(get_current_user)
):
    messages = _load_room()
    msg = _find_by_id(messages, message_id)
    is_admin = current_user.get("role") == "admin"
    if msg["sender_id"] != current_user["id"] and not is_admin:
        raise HTTPException(
            status_code=403,
            detail="You can only delete your own messages",
        )
    # Soft delete: the message stays in the log so ordering and replies
    # that referenced it still render correctly, but the content is wiped
    # and the client renders a "this message was deleted" tombstone.
    msg["deleted"] = True
    msg["text"] = None
    msg["sticker"] = None
    msg["audio_url"] = None
    msg["image_url"] = None
    msg["reactions"] = {}
    _save_room(messages)
    return msg


# ---- Presence --------------------------------------------------------------


@router.post("/room/heartbeat")
def heartbeat(current_user: dict = Depends(get_current_user)):
    """The room screen calls this every few seconds while open, so other
    viewers can see who's currently active. Cheap: just stamps the
    current time against the caller's id in a small dict on disk."""
    presence = _load_presence()
    presence[current_user["id"]] = datetime.now(timezone.utc).isoformat()
    _save_presence(presence)
    return {"status": "ok"}


@router.get("/room/presence")
def presence(current_user: dict = Depends(get_current_user)):
    """Users seen in the last PRESENCE_WINDOW, with just enough info for
    the header ("N active now" + a short avatar strip)."""
    presence_data = _load_presence()
    cutoff = datetime.now(timezone.utc) - PRESENCE_WINDOW
    active_ids: set[str] = set()
    stale_ids: list[str] = []
    for user_id, stamp in presence_data.items():
        try:
            seen_at = datetime.fromisoformat(stamp)
        except ValueError:
            stale_ids.append(user_id)
            continue
        if seen_at >= cutoff:
            active_ids.add(user_id)
        else:
            stale_ids.append(user_id)
    # Opportunistically prune old entries so the presence file doesn't
    # grow without bound as users come and go.
    if stale_ids:
        for user_id in stale_ids:
            presence_data.pop(user_id, None)
        _save_presence(presence_data)

    users_by_id = {u["id"]: u for u in load_users()}
    active_users = [
        {
            "id": u["id"],
            "full_name": u["full_name"],
            "avatar_url": u.get("avatar_url"),
        }
        for user_id in active_ids
        if (u := users_by_id.get(user_id)) is not None
    ]
    return {"count": len(active_users), "users": active_users}
