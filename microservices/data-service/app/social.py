"""Friend connections, direct messages, and small private group chats."""

import threading
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from .models import DATA_DIR, _load, _save, load_users
from .security import get_current_user

router = APIRouter(prefix="/social", tags=["social"])

FRIENDSHIPS_FILE = DATA_DIR / "friendships.json"
DIRECT_THREADS_FILE = DATA_DIR / "direct_threads.json"
GROUPS_FILE = DATA_DIR / "chat_groups.json"
# Voice-message uploads land under DATA_DIR/audio/voice, which is served
# publicly at /audio/voice/<uuid>.<ext> by the /audio StaticFiles mount in
# main.py — matches how avatars and post photos are already served.
VOICE_DIR = DATA_DIR / "audio" / "voice"
VOICE_DIR.mkdir(parents=True, exist_ok=True)

# Kept tight so the JSON message store doesn't grow unbounded from a
# single accidentally-uploaded long recording, and so users can't push
# multi-megabyte files through a chat channel.
MAX_VOICE_BYTES = 5 * 1024 * 1024  # 5 MB
MAX_VOICE_DURATION_MS = 5 * 60 * 1000  # 5 minutes

# A curated catalogue of "stickers" — the client renders each as a large
# emoji tile. Keeping the catalogue on the server means new stickers only
# need one place changed and older clients still see something sensible
# (unknown ids fall back to a generic label on the client).
STICKERS: list[dict] = [
    {"id": "wave", "emoji": "\U0001F44B", "label": "Hi!"},
    {"id": "thumbs_up", "emoji": "\U0001F44D", "label": "Nice!"},
    {"id": "clap", "emoji": "\U0001F44F", "label": "Bravo"},
    {"id": "heart", "emoji": "\u2764\ufe0f", "label": "Love"},
    {"id": "fire", "emoji": "\U0001F525", "label": "Fire"},
    {"id": "laugh", "emoji": "\U0001F602", "label": "Haha"},
    {"id": "party", "emoji": "\U0001F389", "label": "Party!"},
    {"id": "star", "emoji": "\U0001F929", "label": "Star!"},
    {"id": "sad", "emoji": "\U0001F622", "label": "Sad"},
    {"id": "surprise", "emoji": "\U0001F62E", "label": "Wow"},
    {"id": "plane", "emoji": "\u2708\ufe0f", "label": "Bon voyage"},
    {"id": "beach", "emoji": "\U0001F3D6\ufe0f", "label": "Vacation"},
]
_STICKER_IDS = {sticker["id"] for sticker in STICKERS}

# Serializes writes to the JSON stores below — matches the single-process
# assumption the friends feature already runs under.
_social_lock = threading.Lock()


class FriendRequestCreate(BaseModel):
    username: str


class GroupCreate(BaseModel):
    name: str
    member_ids: list[str]


class TextMessageCreate(BaseModel):
    # Kept as the whole payload rather than adding new fields to a single
    # model so an old (text-only) client hitting the endpoint with
    # {"text": ...} still validates cleanly. Extra fields cover stickers
    # and voice notes; type defaults to "text" for backwards compatibility.
    text: str = ""
    type: str = "text"
    sticker_id: Optional[str] = None
    voice_url: Optional[str] = None
    voice_duration_ms: Optional[int] = None


def _load_list(path) -> list:
    data = _load(path)
    return data if isinstance(data, list) else []


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "full_name": user.get("full_name", ""),
        "username": user.get("username", ""),
        "avatar_url": user.get("avatar_url"),
    }


def _user_by_id(users: list, user_id: str) -> dict:
    user = next((item for item in users if item["id"] == user_id), None)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def _friendship_between(friendships: list, first_id: str, second_id: str) -> dict | None:
    pair = {first_id, second_id}
    return next(
        (
            friendship
            for friendship in friendships
            if {friendship["requester_id"], friendship["recipient_id"]} == pair
        ),
        None,
    )


def _require_friendship(friendships: list, first_id: str, second_id: str) -> None:
    friendship = _friendship_between(friendships, first_id, second_id)
    if friendship is None or friendship["status"] != "accepted":
        raise HTTPException(
            status_code=403,
            detail="You can only message users after they accept your friend request",
        )


def _validate_voice_url(voice_url: str) -> str:
    # Reject anything not pointing at our own voice-upload directory so a
    # crafted message can't smuggle an arbitrary URL through as a "voice
    # message" — the bubble would then happily play a link the sender
    # never uploaded, e.g. audio from a phishing site.
    if not voice_url.startswith("/audio/voice/"):
        raise HTTPException(status_code=400, detail="Invalid voice message URL")
    return voice_url


def _message(sender: dict, payload: TextMessageCreate) -> dict:
    message_type = payload.type or "text"
    base = {
        "id": str(uuid.uuid4()),
        "sender_id": sender["id"],
        "sender_name": sender.get("full_name", ""),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "type": message_type,
        # Kept for backwards compatibility with older clients that read
        # only .text. Non-text messages set this to a short human-readable
        # description so a fallback UI still shows something meaningful.
        "text": "",
    }

    if message_type == "text":
        cleaned = payload.text.strip()
        if not cleaned:
            raise HTTPException(status_code=400, detail="Message cannot be empty")
        if len(cleaned) > 4000:
            raise HTTPException(
                status_code=400, detail="Message must be at most 4000 characters"
            )
        base["text"] = cleaned
        return base

    if message_type == "sticker":
        sticker_id = (payload.sticker_id or "").strip()
        if sticker_id not in _STICKER_IDS:
            raise HTTPException(status_code=400, detail="Unknown sticker")
        base["sticker_id"] = sticker_id
        base["text"] = f"[sticker:{sticker_id}]"
        return base

    if message_type == "voice":
        if not payload.voice_url:
            raise HTTPException(status_code=400, detail="Voice message is missing its URL")
        base["voice_url"] = _validate_voice_url(payload.voice_url)
        duration_ms = int(payload.voice_duration_ms or 0)
        if duration_ms <= 0 or duration_ms > MAX_VOICE_DURATION_MS:
            raise HTTPException(status_code=400, detail="Invalid voice message duration")
        base["voice_duration_ms"] = duration_ms
        base["text"] = "[voice message]"
        return base

    raise HTTPException(status_code=400, detail=f"Unsupported message type: {message_type}")


def _thread_for(threads: list, first_id: str, second_id: str) -> dict:
    participants = sorted((first_id, second_id))
    thread = next(
        (item for item in threads if item.get("participant_ids") == participants), None
    )
    if thread is None:
        thread = {"id": str(uuid.uuid4()), "participant_ids": participants, "messages": []}
        threads.append(thread)
    return thread


@router.get("/friends")
def get_friends(current_user: dict = Depends(get_current_user)):
    with _social_lock:
        users = load_users()
        users_by_id = {user["id"]: user for user in users}
        friendships = _load_list(FRIENDSHIPS_FILE)
        my_id = current_user["id"]

        friends = []
        incoming = []
        outgoing = []
        for friendship in friendships:
            requester_id = friendship["requester_id"]
            recipient_id = friendship["recipient_id"]
            if friendship["status"] == "accepted" and my_id in {requester_id, recipient_id}:
                other_id = recipient_id if requester_id == my_id else requester_id
                other = users_by_id.get(other_id)
                if other is not None:
                    friends.append(_public_user(other))
            elif friendship["status"] == "pending" and recipient_id == my_id:
                requester = users_by_id.get(requester_id)
                if requester is not None:
                    incoming.append(
                        {
                            "request_id": friendship["id"],
                            "user": _public_user(requester),
                            "created_at": friendship["created_at"],
                        }
                    )
            elif friendship["status"] == "pending" and requester_id == my_id:
                recipient = users_by_id.get(recipient_id)
                if recipient is not None:
                    outgoing.append(
                        {
                            "request_id": friendship["id"],
                            "user": _public_user(recipient),
                            "created_at": friendship["created_at"],
                        }
                    )

        return {
            "friends": sorted(friends, key=lambda user: user["full_name"].lower()),
            "incoming_requests": incoming,
            "outgoing_requests": outgoing,
        }


@router.post("/friends/requests", status_code=201)
def send_friend_request(
    payload: FriendRequestCreate, current_user: dict = Depends(get_current_user)
):
    username = payload.username.strip().lower().lstrip("@")
    if not username:
        raise HTTPException(status_code=400, detail="Enter a username")

    with _social_lock:
        users = load_users()
        recipient = next(
            (user for user in users if str(user.get("username", "")).lower() == username),
            None,
        )
        if recipient is None:
            raise HTTPException(status_code=404, detail="No user has that username")
        if recipient["id"] == current_user["id"]:
            raise HTTPException(status_code=400, detail="You cannot add yourself")

        friendships = _load_list(FRIENDSHIPS_FILE)
        existing = _friendship_between(friendships, current_user["id"], recipient["id"])
        if existing is not None:
            if existing["status"] == "accepted":
                detail = "You are already friends"
            elif existing["requester_id"] == current_user["id"]:
                detail = "Friend request already sent"
            else:
                detail = "This user has already sent you a friend request"
            raise HTTPException(status_code=400, detail=detail)

        now = datetime.now(timezone.utc).isoformat()
        request = {
            "id": str(uuid.uuid4()),
            "requester_id": current_user["id"],
            "recipient_id": recipient["id"],
            "status": "pending",
            "created_at": now,
            "updated_at": now,
        }
        friendships.append(request)
        _save(FRIENDSHIPS_FILE, friendships)
        return {"request_id": request["id"], "status": request["status"]}


@router.post("/friends/requests/{request_id}/accept")
def accept_friend_request(
    request_id: str, current_user: dict = Depends(get_current_user)
):
    with _social_lock:
        friendships = _load_list(FRIENDSHIPS_FILE)
        request = next((item for item in friendships if item["id"] == request_id), None)
        if request is None:
            raise HTTPException(status_code=404, detail="Friend request not found")
        if request["recipient_id"] != current_user["id"]:
            raise HTTPException(status_code=403, detail="Only the recipient can accept this request")
        if request["status"] != "pending":
            raise HTTPException(status_code=400, detail="This friend request is no longer pending")
        request["status"] = "accepted"
        request["updated_at"] = datetime.now(timezone.utc).isoformat()
        _save(FRIENDSHIPS_FILE, friendships)
        return {"request_id": request["id"], "status": request["status"]}


@router.delete("/friends/requests/{request_id}", status_code=204)
def decline_friend_request(
    request_id: str, current_user: dict = Depends(get_current_user)
):
    with _social_lock:
        friendships = _load_list(FRIENDSHIPS_FILE)
        request = next((item for item in friendships if item["id"] == request_id), None)
        if request is None:
            raise HTTPException(status_code=404, detail="Friend request not found")
        if current_user["id"] not in {request["requester_id"], request["recipient_id"]}:
            raise HTTPException(status_code=403, detail="You cannot remove this friend request")
        if request["status"] != "pending":
            raise HTTPException(status_code=400, detail="Only pending requests can be removed")
        _save(FRIENDSHIPS_FILE, [item for item in friendships if item["id"] != request_id])


@router.get("/friends/{friend_id}/messages")
def get_direct_messages(friend_id: str, current_user: dict = Depends(get_current_user)):
    with _social_lock:
        friendships = _load_list(FRIENDSHIPS_FILE)
        _require_friendship(friendships, current_user["id"], friend_id)
        threads = _load_list(DIRECT_THREADS_FILE)
        thread = _thread_for(threads, current_user["id"], friend_id)
        return thread["messages"]


@router.post("/friends/{friend_id}/messages", status_code=201)
def send_direct_message(
    friend_id: str,
    payload: TextMessageCreate,
    current_user: dict = Depends(get_current_user),
):
    with _social_lock:
        friendships = _load_list(FRIENDSHIPS_FILE)
        _require_friendship(friendships, current_user["id"], friend_id)
        threads = _load_list(DIRECT_THREADS_FILE)
        thread = _thread_for(threads, current_user["id"], friend_id)
        message = _message(current_user, payload)
        thread["messages"].append(message)
        _save(DIRECT_THREADS_FILE, threads)
        return message


@router.get("/groups")
def get_groups(current_user: dict = Depends(get_current_user)):
    with _social_lock:
        users_by_id = {user["id"]: user for user in load_users()}
        groups = _load_list(GROUPS_FILE)
        visible = []
        for group in groups:
            if current_user["id"] not in group.get("member_ids", []):
                continue
            members = [
                _public_user(users_by_id[member_id])
                for member_id in group["member_ids"]
                if member_id in users_by_id
            ]
            visible.append(
                {
                    "id": group["id"],
                    "name": group["name"],
                    "owner_id": group["owner_id"],
                    "members": members,
                    "created_at": group["created_at"],
                }
            )
        return sorted(visible, key=lambda group: group["created_at"], reverse=True)


@router.post("/groups", status_code=201)
def create_group(
    payload: GroupCreate, current_user: dict = Depends(get_current_user)
):
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Group name cannot be empty")
    if len(name) > 80:
        raise HTTPException(status_code=400, detail="Group name must be at most 80 characters")

    with _social_lock:
        users = load_users()
        users_by_id = {user["id"]: user for user in users}
        member_ids = list(dict.fromkeys(payload.member_ids))
        if not member_ids:
            raise HTTPException(status_code=400, detail="Select at least one friend")
        if any(member_id not in users_by_id for member_id in member_ids):
            raise HTTPException(status_code=404, detail="One or more selected users no longer exist")

        friendships = _load_list(FRIENDSHIPS_FILE)
        for member_id in member_ids:
            _require_friendship(friendships, current_user["id"], member_id)

        all_members = [current_user["id"], *member_ids]
        group = {
            "id": str(uuid.uuid4()),
            "name": name,
            "owner_id": current_user["id"],
            "member_ids": all_members,
            "messages": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        groups = _load_list(GROUPS_FILE)
        groups.append(group)
        _save(GROUPS_FILE, groups)
        return {
            "id": group["id"],
            "name": group["name"],
            "owner_id": group["owner_id"],
            "members": [_public_user(users_by_id[member_id]) for member_id in all_members],
            "created_at": group["created_at"],
        }


def _group_for_member(groups: list, group_id: str, member_id: str) -> dict:
    group = next((item for item in groups if item["id"] == group_id), None)
    if group is None:
        raise HTTPException(status_code=404, detail="Group not found")
    if member_id not in group["member_ids"]:
        raise HTTPException(status_code=403, detail="You are not a member of this group")
    return group


@router.get("/groups/{group_id}/messages")
def get_group_messages(group_id: str, current_user: dict = Depends(get_current_user)):
    with _social_lock:
        group = _group_for_member(_load_list(GROUPS_FILE), group_id, current_user["id"])
        return group.get("messages", [])


@router.post("/groups/{group_id}/messages", status_code=201)
def send_group_message(
    group_id: str,
    payload: TextMessageCreate,
    current_user: dict = Depends(get_current_user),
):
    with _social_lock:
        groups = _load_list(GROUPS_FILE)
        group = _group_for_member(groups, group_id, current_user["id"])
        message = _message(current_user, payload)
        group.setdefault("messages", []).append(message)
        _save(GROUPS_FILE, groups)
        return message


# ---- Sticker catalogue and voice uploads -----------------------------------


@router.get("/stickers")
def list_stickers(current_user: dict = Depends(get_current_user)):
    """
    The client fetches this once when the sticker picker opens. Requires
    auth to match every other social endpoint — no reason to serve the
    catalogue to logged-out visitors.
    """
    # current_user is unused here but keeping the dependency enforces auth
    # and lets us safely add per-user unlocks later.
    _ = current_user
    return STICKERS


_ALLOWED_VOICE_EXTENSIONS = {"m4a", "mp3", "aac", "wav", "ogg", "webm"}


def _voice_extension(filename: Optional[str], content_type: Optional[str]) -> str:
    # Prefer the client-provided filename extension so playback matches
    # the actual container. Fall back to a content-type mapping and, if
    # neither is usable, refuse the upload rather than guessing.
    if filename and "." in filename:
        candidate = filename.rsplit(".", 1)[-1].lower()
        if candidate in _ALLOWED_VOICE_EXTENSIONS:
            return candidate
    if content_type:
        mapping = {
            "audio/mp4": "m4a",
            "audio/aac": "aac",
            "audio/x-aac": "aac",
            "audio/mpeg": "mp3",
            "audio/wav": "wav",
            "audio/x-wav": "wav",
            "audio/wave": "wav",
            "audio/ogg": "ogg",
            "audio/webm": "webm",
        }
        if content_type.lower() in mapping:
            return mapping[content_type.lower()]
    raise HTTPException(
        status_code=400, detail="Unsupported voice message format"
    )


@router.post("/voice-messages", status_code=201)
async def upload_voice_message(
    file: UploadFile = File(...),
    duration_ms: int = Form(...),
    current_user: dict = Depends(get_current_user),
):
    """
    Two-step voice message flow: the client first uploads the audio bytes
    here to get back a URL + confirmed duration, then sends a normal
    /messages payload with type=voice + voice_url + voice_duration_ms.

    Splitting upload from send keeps the existing message endpoints as
    small JSON writes (no multipart there) and lets the recipient list a
    single JSON /messages call to load history — audio bytes stream from
    the /audio static mount.
    """
    if duration_ms <= 0 or duration_ms > MAX_VOICE_DURATION_MS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Voice message must be between 0 and "
                f"{MAX_VOICE_DURATION_MS // 1000} seconds"
            ),
        )

    extension = _voice_extension(file.filename, file.content_type)
    filename = f"{current_user['id']}_{uuid.uuid4().hex}.{extension}"
    target = VOICE_DIR / filename

    # Copy the upload directly to disk in a streaming fashion so a
    # too-large upload is refused early rather than after everything is
    # already in memory. shutil.copyfileobj is chunked (default 64 KiB).
    bytes_written = 0
    with open(target, "wb") as dest:
        while True:
            chunk = await file.read(64 * 1024)
            if not chunk:
                break
            bytes_written += len(chunk)
            if bytes_written > MAX_VOICE_BYTES:
                dest.close()
                target.unlink(missing_ok=True)
                raise HTTPException(
                    status_code=413,
                    detail=(
                        f"Voice message must be at most "
                        f"{MAX_VOICE_BYTES // (1024 * 1024)} MB"
                    ),
                )
            dest.write(chunk)

    if bytes_written == 0:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Voice message file is empty")

    return {
        "url": f"/audio/voice/{filename}",
        "duration_ms": duration_ms,
        "content_type": file.content_type or f"audio/{extension}",
    }
