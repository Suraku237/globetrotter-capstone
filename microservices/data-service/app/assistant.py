"""
Domain-restricted AI travel assistant, backed by Gemini.

Scope is enforced with a system prompt, not a keyword filter — Gemini itself
is instructed to only answer travel/Cameroon-tourism questions and to
decline anything else. The prompt is built fresh per request from the
current *approved* destinations (see models.load_destinations), so the
assistant always knows what's actually in the app rather than a stale or
hallucinated list.
"""

from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from .models import GEMINI_API_KEY, load_conversations, load_destinations, save_conversations
from .security import get_current_user

router = APIRouter(prefix="/assistant", tags=["assistant"])

GEMINI_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    # "-latest" alias instead of a pinned version — gemini-2.5-flash got cut
    # off for new API keys/projects and started 404ing; the alias tracks
    # whatever Google currently recommends instead of going stale again.
    "gemini-flash-latest:generateContent"
)

# How many past turns get sent back to Gemini as context — bounds prompt
# size/cost while still giving it real memory of the recent conversation.
# The full history still accumulates in conversations.json regardless.
MAX_HISTORY_TURNS = 20


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    reply: str


def _system_prompt() -> str:
    destinations = [
        d for d in load_destinations() if d.get("status", "approved") == "approved"
    ]
    names = ", ".join(f"{d['name']} ({d['region']})" for d in destinations) or "none yet"

    return (
        "You are the in-app travel assistant for GlobeTrotter / Fast Travel, "
        "a trip-planning app focused on Cameroon. "
        "Only answer questions about travel, tourism, and trip-planning in "
        "Cameroon, and about how to use this app (destinations, itineraries, "
        "recommendations, the social feed, suggesting new destinations). "
        "If asked anything outside that scope — coding help, general trivia, "
        "medical/legal/financial advice, or any other topic — politely "
        "decline in one sentence and steer the conversation back to travel. "
        "Keep answers concise and conversational, since they may be read "
        "aloud by text-to-speech. "
        f"Destinations currently in the app: {names}."
    )


@router.post("/chat", response_model=ChatResponse)
async def chat(payload: ChatRequest, current_user: dict = Depends(get_current_user)):
    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="The AI assistant isn't configured yet (missing GEMINI_API_KEY).",
        )

    conversations = load_conversations()
    past_turns = conversations.get(current_user["id"], [])

    contents = []
    for turn in past_turns[-MAX_HISTORY_TURNS:]:
        contents.append({
            "role": "model" if turn["role"] == "assistant" else "user",
            "parts": [{"text": turn["text"]}],
        })
    contents.append({"role": "user", "parts": [{"text": payload.message}]})

    body = {
        "contents": contents,
        "systemInstruction": {"parts": [{"text": _system_prompt()}]},
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        res = await client.post(
            GEMINI_URL,
            params={"key": GEMINI_API_KEY},
            json=body,
        )

    if res.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"The assistant is unavailable right now ({res.status_code}).",
        )

    data = res.json()
    try:
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        raise HTTPException(
            status_code=502,
            detail="The assistant didn't return a usable answer. Try again.",
        )
    reply = reply.strip()

    now = datetime.now(timezone.utc).isoformat()
    past_turns.append({"role": "user", "text": payload.message, "created_at": now})
    past_turns.append({"role": "assistant", "text": reply, "created_at": now})
    conversations[current_user["id"]] = past_turns
    save_conversations(conversations)

    return ChatResponse(reply=reply)
