import uuid
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from .models import DATA_DIR, _load, _save, load_users
from .security import get_current_user

router = APIRouter(prefix="/chat", tags=["chat"])

# Deliberately its own file, separate from CONVERSATIONS_FILE — that one
# already belongs to the AI assistant's per-user chat history (see
# models.py). Mixing the two would corrupt the assistant's history with
# user-to-user messages and vice versa.
CHAT_FILE = DATA_DIR / "chat_conversations.json"
AUDIO_DIR = DATA_DIR / "audio" / "chat"


def _load_conversations() -> list:
    return _load(CHAT_FILE)


def _save_conversations(conversations: list) -> None:
    _save(CHAT_FILE, conversations)


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "full_name": user["full_name"],
        "avatar_url": user.get("avatar_url"),
    }


def _find_conversation(conversations: list, conversation_id: str) -> dict:
    convo = next((c for c in conversations if c["id"] == conversation_id), None)
    if convo is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return convo


def _require_participant(convo: dict, user_id: str) -> None:
    if user_id not in convo["participant_ids"]:
        raise HTTPException(status_code=403, detail="Not a participant in this conversation")


class StartConversation(BaseModel):
    other_user_id: str


class MessageCreate(BaseModel):
    type: Literal["text", "sticker"]
    # Caption text for "text" messages, or the sticker/emoji itself
    # (a plain unicode character, e.g. "🎉") for "sticker" messages —
    # stickers are rendered client-side at large size rather than shipped
    # as image assets, so no upload/storage is needed for them.
    content: str


@router.get("/users")
def list_chat_users(current_user: dict = Depends(get_current_user)):
    """Everyone the current user could start a conversation with."""
    users = load_users()
    return [_public_user(u) for u in users if u["id"] != current_user["id"]]


@router.get("/conversations")
def list_conversations(current_user: dict = Depends(get_current_user)):
    conversations = _load_conversations()
    users_by_id = {u["id"]: u for u in load_users()}
    my_id = current_user["id"]

    result = []
    for convo in conversations:
        if my_id not in convo["participant_ids"]:
            continue
        other_id = next((p for p in convo["participant_ids"] if p != my_id), my_id)
        other_user = users_by_id.get(other_id)
        messages = convo["messages"]
        last_message = messages[-1] if messages else None
        unread_count = sum(
            1
            for m in messages
            if m["sender_id"] != my_id and my_id not in m.get("read_by", [])
        )
        result.append(
            {
                "id": convo["id"],
                "other_user": _public_user(other_user) if other_user else None,
                "last_message": last_message,
                "unread_count": unread_count,
                "updated_at": convo["updated_at"],
            }
        )
    return sorted(result, key=lambda c: c["updated_at"], reverse=True)


@router.post("/conversations", status_code=201)
def start_conversation(
    payload: StartConversation, current_user: dict = Depends(get_current_user)
):
    my_id = current_user["id"]
    if payload.other_user_id == my_id:
        raise HTTPException(status_code=400, detail="Can't start a conversation with yourself")

    users_by_id = {u["id"]: u for u in load_users()}
    if payload.other_user_id not in users_by_id:
        raise HTTPException(status_code=404, detail="User not found")

    conversations = _load_conversations()
    # Reuse an existing conversation between this pair rather than creating
    # a duplicate every time someone taps "message" on the same person.
    existing = next(
        (
            c
            for c in conversations
            if set(c["participant_ids"]) == {my_id, payload.other_user_id}
        ),
        None,
    )
    if existing is not None:
        return existing

    now = datetime.now(timezone.utc).isoformat()
    convo = {
        "id": str(uuid.uuid4()),
        "participant_ids": [my_id, payload.other_user_id],
        "messages": [],
        "created_at": now,
        "updated_at": now,
    }
    conversations.append(convo)
    _save_conversations(conversations)
    return convo


@router.get("/conversations/{conversation_id}/messages")
def get_messages(conversation_id: str, current_user: dict = Depends(get_current_user)):
    conversations = _load_conversations()
    convo = _find_conversation(conversations, conversation_id)
    _require_participant(convo, current_user["id"])
    return convo["messages"]


@router.post("/conversations/{conversation_id}/messages", status_code=201)
def send_message(
    conversation_id: str,
    payload: MessageCreate,
    current_user: dict = Depends(get_current_user),
):
    conversations = _load_conversations()
    convo = _find_conversation(conversations, conversation_id)
    _require_participant(convo, current_user["id"])

    message = {
        "id": str(uuid.uuid4()),
        "sender_id": current_user["id"],
        "type": payload.type,
        "text": payload.content if payload.type == "text" else None,
        "sticker": payload.content if payload.type == "sticker" else None,
        "audio_url": None,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "read_by": [current_user["id"]],
    }
    convo["messages"].append(message)
    convo["updated_at"] = message["created_at"]
    _save_conversations(conversations)
    return message


@router.post("/conversations/{conversation_id}/messages/audio", status_code=201)
async def send_audio_message(
    conversation_id: str,
    audio: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    conversations = _load_conversations()
    convo = _find_conversation(conversations, conversation_id)
    _require_participant(convo, current_user["id"])

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    extension = (
        audio.filename.rsplit(".", 1)[-1].lower()
        if audio.filename and "." in audio.filename
        else "m4a"
    )
    filename = f"{uuid.uuid4().hex}.{extension}"
    contents = await audio.read()
    with open(AUDIO_DIR / filename, "wb") as f:
        f.write(contents)

    message = {
        "id": str(uuid.uuid4()),
        "sender_id": current_user["id"],
        "type": "audio",
        "text": None,
        "sticker": None,
        "audio_url": f"/audio/chat/{filename}",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "read_by": [current_user["id"]],
    }
    convo["messages"].append(message)
    convo["updated_at"] = message["created_at"]
    _save_conversations(conversations)
    return message


@router.post("/conversations/{conversation_id}/read")
def mark_read(conversation_id: str, current_user: dict = Depends(get_current_user)):
    conversations = _load_conversations()
    convo = _find_conversation(conversations, conversation_id)
    _require_participant(convo, current_user["id"])

    my_id = current_user["id"]
    changed = False
    for message in convo["messages"]:
        if my_id not in message.setdefault("read_by", []):
            message["read_by"].append(my_id)
            changed = True
    if changed:
        _save_conversations(conversations)
    return {"status": "ok"}