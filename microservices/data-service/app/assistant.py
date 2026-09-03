"""
Domain-restricted AI travel assistant, backed by Gemini.

Scope is enforced with a system prompt, not a keyword filter — Gemini itself
is instructed to only answer travel/Cameroon-tourism questions and to
decline anything else. The prompt is built fresh per request from the
current *approved* destinations (see models.load_destinations), so the
assistant always knows what's actually in the app rather than a stale or
hallucinated list.

Two chat endpoints are exposed:
  * POST /assistant/chat        — one shot, returns the full reply.
  * POST /assistant/chat/stream — Server-Sent Events, yields the reply
    token by token so the UI can render as Gemini generates.

Both share:
  * A per-user sliding-window rate limit (see _consume_rate_limit).
  * A shared prompt/history builder so the two endpoints can never drift
    apart in what they send Gemini.
  * A shared error path that surfaces upstream failure modes as
    actionable HTTP status codes (429 for quota, 400 for safety blocks,
    502 for transient upstream faults) instead of a generic 502.
"""

import asyncio
import json
import logging
import threading
import time
from collections import deque
from datetime import datetime, timezone
from typing import AsyncIterator, Deque, Dict, Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .models import (
    get_gemini_api_key,
    load_conversations,
    load_destinations,
    save_conversations,
)
from .security import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/assistant", tags=["assistant"])

# The "-latest" alias tracks whatever Google currently recommends —
# gemini-2.5-flash was cut off for new keys/projects at one point and
# started 404ing, and this alias sidesteps that whole class of failure.
_MODEL = "gemini-flash-latest"
_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
GEMINI_URL = f"{_BASE}/{_MODEL}:generateContent"
GEMINI_STREAM_URL = f"{_BASE}/{_MODEL}:streamGenerateContent"

# How many past turns get sent back to Gemini as context — bounds prompt
# size/cost while still giving it real memory of the recent conversation.
# The full history still accumulates in conversations.json regardless.
MAX_HISTORY_TURNS = 20

# ---- Rate limiting ---------------------------------------------------------

# Requests per user in the rolling window below. Deliberately generous —
# the assistant is meant to be conversational, not gated. The point is to
# stop a runaway client (or a misbehaving script) from burning through
# the Gemini quota.
_RATE_LIMIT = 15
_RATE_WINDOW = 60.0  # seconds

# user_id -> deque of unix-timestamps of accepted requests within the
# window. Serialised by a single lock because FastAPI's default sync
# executor may schedule the two endpoints on separate threads.
_recent_requests: Dict[str, Deque[float]] = {}
_recent_requests_lock = threading.Lock()


def _consume_rate_limit(user_id: str) -> None:
    """Raise 429 if this user has exceeded the sliding-window budget.
    Sets a Retry-After hint so the client can back off intelligently
    instead of retrying immediately."""
    now = time.monotonic()
    with _recent_requests_lock:
        bucket = _recent_requests.setdefault(user_id, deque())
        while bucket and (now - bucket[0]) > _RATE_WINDOW:
            bucket.popleft()
        if len(bucket) >= _RATE_LIMIT:
            retry_after = int(_RATE_WINDOW - (now - bucket[0])) + 1
            raise HTTPException(
                status_code=429,
                detail=(
                    f"Slow down — {_RATE_LIMIT} messages per minute per user. "
                    f"Try again in {retry_after} seconds."
                ),
                headers={"Retry-After": str(retry_after)},
            )
        bucket.append(now)


# ---- Request/response shapes ----------------------------------------------


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    reply: str


class HistoryTurn(BaseModel):
    role: str
    text: str
    created_at: str


# ---- Prompt / history builder ---------------------------------------------


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


def _build_gemini_body(user_id: str, message: str) -> tuple[list, dict]:
    conversations = load_conversations()
    past_turns = conversations.get(user_id, [])

    contents = []
    for turn in past_turns[-MAX_HISTORY_TURNS:]:
        contents.append(
            {
                "role": "model" if turn["role"] == "assistant" else "user",
                "parts": [{"text": turn["text"]}],
            }
        )
    contents.append({"role": "user", "parts": [{"text": message}]})

    body = {
        "contents": contents,
        "systemInstruction": {"parts": [{"text": _system_prompt()}]},
    }
    return past_turns, body


def _persist_turn(user_id: str, past_turns: list, question: str, reply: str) -> None:
    conversations = load_conversations()
    now = datetime.now(timezone.utc).isoformat()
    past_turns.append({"role": "user", "text": question, "created_at": now})
    past_turns.append({"role": "assistant", "text": reply, "created_at": now})
    conversations[user_id] = past_turns
    save_conversations(conversations)


# ---- Shared error / upstream helpers --------------------------------------


def _require_api_key() -> str:
    api_key = get_gemini_api_key()
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail=(
                "The AI assistant isn't configured yet (GEMINI_API_KEY is "
                "missing or empty in data-service). Set it in "
                "microservices/.env, then `docker compose up -d "
                "--force-recreate data-service` so the container picks up "
                "the new value."
            ),
        )
    return api_key


def _handle_gemini_error(status_code: int, body_text: str) -> None:
    """Translate Google's error JSON into a user-facing HTTPException.

    Gemini uses a fairly consistent error envelope:
        {"error": {"code": 429, "message": "...", "status": "RESOURCE_EXHAUSTED"}}

    That lets us tell "the assistant is over quota" (429 back to the
    client with a Retry-After) apart from "you sent something malformed"
    (400) or "Google's having a bad time" (502)."""
    try:
        parsed = json.loads(body_text)
        error = parsed.get("error", {}) if isinstance(parsed, dict) else {}
        message = error.get("message") or ""
        status = (error.get("status") or "").upper()
    except (ValueError, AttributeError):
        message = ""
        status = ""

    if status_code == 429 or status == "RESOURCE_EXHAUSTED":
        raise HTTPException(
            status_code=429,
            detail=(
                "The AI assistant is busy right now (Gemini quota reached). "
                "Try again in a moment."
            ),
            headers={"Retry-After": "30"},
        )
    if status_code == 400 or status in {"INVALID_ARGUMENT", "FAILED_PRECONDITION"}:
        raise HTTPException(
            status_code=400,
            detail=(
                message.strip()
                or "The assistant couldn't process that message. Try rephrasing."
            ),
        )
    if status_code in {401, 403} or status == "PERMISSION_DENIED":
        raise HTTPException(
            status_code=503,
            detail=(
                "The AI assistant's key was rejected by Google. Verify "
                "GEMINI_API_KEY in microservices/.env and recreate the "
                "data-service container."
            ),
        )
    # Anything else (5xx from Google, 404, etc.) is transient to us.
    logger.warning("Gemini upstream error %d: %s", status_code, body_text[:200])
    raise HTTPException(
        status_code=502,
        detail=f"The assistant is unavailable right now ({status_code}).",
    )


def _extract_text_from_chunk(chunk: dict) -> Optional[str]:
    """Pull the text delta out of one Gemini response object, whether it
    came from the single-shot endpoint or one frame of the SSE stream.
    Returns None on chunks with no visible text (safety metadata,
    prompt-feedback frames, etc.)."""
    candidates = chunk.get("candidates") or []
    if not candidates:
        return None
    parts = ((candidates[0].get("content") or {}).get("parts")) or []
    texts = [p.get("text") for p in parts if isinstance(p.get("text"), str)]
    if not texts:
        return None
    return "".join(texts)


def _check_prompt_block(chunk: dict) -> None:
    """Gemini may refuse a prompt outright via `promptFeedback.blockReason`
    or refuse mid-generation via a candidate's `finishReason: SAFETY`.
    Either surfaces here as a 400 with a hint to rephrase, rather than
    the client seeing an empty assistant reply and wondering why."""
    prompt_feedback = chunk.get("promptFeedback") or {}
    reason = prompt_feedback.get("blockReason")
    if reason:
        raise HTTPException(
            status_code=400,
            detail=(
                "The assistant couldn't answer that. "
                "Try rephrasing your question."
            ),
        )
    candidates = chunk.get("candidates") or []
    if candidates:
        finish = (candidates[0].get("finishReason") or "").upper()
        if finish == "SAFETY":
            raise HTTPException(
                status_code=400,
                detail=(
                    "The assistant stopped mid-reply for safety reasons. "
                    "Try rephrasing your question."
                ),
            )


async def _post_gemini(
    client: httpx.AsyncClient,
    url: str,
    api_key: str,
    body: dict,
    *,
    params: Optional[dict] = None,
    max_attempts: int = 3,
) -> httpx.Response:
    """POST to Gemini with retry-on-transient-5xx and connection errors.
    Backoff is short (0.4 s, 1.2 s) — the goal is to absorb a hiccup, not
    to sit on a slow connection for minutes. Any non-transient error
    surfaces immediately via _handle_gemini_error at the call site."""
    query = {"key": api_key}
    if params:
        query.update(params)
    last_exc: Optional[Exception] = None
    for attempt in range(max_attempts):
        try:
            res = await client.post(url, params=query, json=body)
        except httpx.HTTPError as exc:
            last_exc = exc
            if attempt + 1 == max_attempts:
                raise HTTPException(
                    status_code=502,
                    detail="Couldn't reach the assistant right now. Try again.",
                ) from exc
            await asyncio.sleep(0.4 * (attempt + 1) ** 2)
            continue
        if res.status_code >= 500 and attempt + 1 < max_attempts:
            await asyncio.sleep(0.4 * (attempt + 1) ** 2)
            continue
        return res
    # Unreachable — every path above either returns or raises — but keeps
    # the type checker happy.
    raise HTTPException(  # pragma: no cover
        status_code=502,
        detail="Couldn't reach the assistant right now. Try again.",
    ) from last_exc


# ---- Endpoints -------------------------------------------------------------


@router.get("/history", response_model=list[HistoryTurn])
def history(current_user: dict = Depends(get_current_user)):
    """The current user's full persisted conversation — lets the chat
    screen show past messages when reopened, instead of starting blank
    even though the assistant itself already remembers everything."""
    conversations = load_conversations()
    return conversations.get(current_user["id"], [])


@router.post("/chat", response_model=ChatResponse)
async def chat(payload: ChatRequest, current_user: dict = Depends(get_current_user)):
    _consume_rate_limit(current_user["id"])
    api_key = _require_api_key()

    past_turns, body = _build_gemini_body(current_user["id"], payload.message)

    async with httpx.AsyncClient(timeout=30.0) as client:
        res = await _post_gemini(client, GEMINI_URL, api_key, body)

    if res.status_code != 200:
        _handle_gemini_error(res.status_code, res.text)

    try:
        data = res.json()
    except ValueError as exc:
        # A 200 with a body that isn't actually JSON (e.g. an upstream/proxy
        # error page slipping through) would otherwise raise unhandled here
        # and surface as a bare 500 with no explanation.
        raise HTTPException(
            status_code=502,
            detail="The assistant sent back an unexpected response. Try again.",
        ) from exc

    _check_prompt_block(data)

    text = _extract_text_from_chunk(data)
    if not text:
        raise HTTPException(
            status_code=502,
            detail="The assistant didn't return a usable answer. Try again.",
        )
    reply = text.strip()

    _persist_turn(current_user["id"], past_turns, payload.message, reply)
    return ChatResponse(reply=reply)


async def _stream_gemini_chunks(
    api_key: str, body: dict, request: Request
) -> AsyncIterator[str]:
    """Async generator that yields plain text deltas from Gemini's
    streaming endpoint, one per `data:` frame. Handles the SSE framing
    inline rather than pulling in a full SSE client library."""
    async with httpx.AsyncClient(timeout=None) as client:
        async with client.stream(
            "POST",
            GEMINI_STREAM_URL,
            params={"key": api_key, "alt": "sse"},
            json=body,
        ) as res:
            if res.status_code != 200:
                error_body = await res.aread()
                _handle_gemini_error(res.status_code, error_body.decode("utf-8", "replace"))
            async for line in res.aiter_lines():
                if await request.is_disconnected():
                    # The client (Flutter app) closed the tab / navigated
                    # away. Stop hitting the upstream so we don't run up
                    # someone's Gemini bill on a reply nobody will read.
                    return
                if not line or not line.startswith("data:"):
                    continue
                payload = line[len("data:") :].strip()
                if not payload or payload == "[DONE]":
                    continue
                try:
                    chunk = json.loads(payload)
                except ValueError:
                    continue
                _check_prompt_block(chunk)
                text = _extract_text_from_chunk(chunk)
                if text:
                    yield text


@router.post("/chat/stream")
async def chat_stream(
    payload: ChatRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Same conversation shape as /chat, but streamed. The response body
    is our own tiny newline-delimited-JSON protocol:
        {"type":"delta","text":"partial "}
        {"type":"delta","text":"reply"}
        {"type":"done"}
    We deliberately don't forward Gemini's SSE format directly — the
    Flutter client shouldn't have to care about upstream framing, and
    this simple shape survives every intermediate proxy that has ever
    stripped or reformatted SSE events on us."""
    _consume_rate_limit(current_user["id"])
    api_key = _require_api_key()
    user_id = current_user["id"]
    past_turns, body = _build_gemini_body(user_id, payload.message)

    async def event_source() -> AsyncIterator[bytes]:
        collected: list[str] = []
        try:
            async for delta in _stream_gemini_chunks(api_key, body, request):
                collected.append(delta)
                frame = json.dumps({"type": "delta", "text": delta})
                yield f"{frame}\n".encode("utf-8")
        except HTTPException as exc:
            frame = json.dumps(
                {"type": "error", "status": exc.status_code, "detail": exc.detail}
            )
            yield f"{frame}\n".encode("utf-8")
            return
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("Unexpected streaming error: %s", exc)
            frame = json.dumps(
                {"type": "error", "status": 502, "detail": "Streaming failed."}
            )
            yield f"{frame}\n".encode("utf-8")
            return

        reply = "".join(collected).strip()
        if reply:
            _persist_turn(user_id, past_turns, payload.message, reply)
        yield f"{json.dumps({'type': 'done'})}\n".encode("utf-8")

    return StreamingResponse(
        event_source(),
        media_type="application/x-ndjson",
        headers={
            # Ask any intermediate proxy (nginx especially) not to buffer
            # — otherwise streaming degenerates back into a single big
            # response only released when everything's done.
            "X-Accel-Buffering": "no",
            "Cache-Control": "no-cache",
        },
    )

