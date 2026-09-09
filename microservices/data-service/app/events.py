"""Authenticated, metadata-only WebSocket stream; HTTP remains authoritative."""

import asyncio
import json
import logging
import sqlite3

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from . import event_store
from .security import get_current_user

router = APIRouter(prefix="/events", tags=["events"])
logger = logging.getLogger(__name__)
AUTH_TIMEOUT = 10
SEND_TIMEOUT = 5
POLL_SECONDS = 0.5
HEARTBEAT_SECONDS = 25
MAX_FRAME_BYTES = 8192


async def _send(websocket: WebSocket, kind: str, topics: list[str]):
    await asyncio.wait_for(
        websocket.send_json({"type": kind, "topics": topics}), SEND_TIMEOUT
    )


async def _receive(websocket: WebSocket):
    while True:
        # Only authentication and an optional application ping are accepted.
        text = await websocket.receive_text()
        if len(text.encode("utf-8")) > MAX_FRAME_BYTES:
            await websocket.close(code=1009)
            return
        if json.loads(text) != {"type": "ping"}:
            await websocket.close(code=4400)
            return


async def _stream(websocket: WebSocket, token: str, user_id: str):
    cursor = await run_in_threadpool(event_store.journal.watermark)
    # Capture the watermark BEFORE ready so mutations racing the client's initial
    # HTTP refresh aren't skipped. Reconnect always refreshes even after pruning.
    await _send(websocket, "ready", ["all"])
    loop = asyncio.get_running_loop()
    next_heartbeat = loop.time() + HEARTBEAT_SECONDS
    while True:
        await asyncio.sleep(POLL_SECONDS)
        if loop.time() >= next_heartbeat:
            await run_in_threadpool(get_current_user, token)
            await _send(websocket, "invalidate", [])
            next_heartbeat = loop.time() + HEARTBEAT_SECONDS
        cursor, topics, gap = await run_in_threadpool(
            event_store.journal.read, user_id, cursor
        )
        if gap:
            await _send(websocket, "ready", ["all"])
        elif topics:
            await _send(websocket, "invalidate", topics)


@router.websocket("/ws")
async def websocket_events(websocket: WebSocket):
    await websocket.accept()
    tasks = []
    try:
        if websocket.query_params:
            await websocket.close(code=4400)
            return
        text = await asyncio.wait_for(websocket.receive_text(), AUTH_TIMEOUT)
        if len(text.encode("utf-8")) > MAX_FRAME_BYTES:
            await websocket.close(code=1009)
            return
        message = json.loads(text)
        token = message.get("token") if isinstance(message, dict) else None
        if not isinstance(token, str) or not token:
            await websocket.close(code=4401)
            return
        user = await run_in_threadpool(get_current_user, token)
        tasks = [
            asyncio.create_task(_stream(websocket, token, user["id"])),
            asyncio.create_task(_receive(websocket)),
        ]
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    except HTTPException:
        await websocket.close(code=4401)
    except (ValueError, KeyError, TypeError):
        await websocket.close(code=4400)
    except asyncio.TimeoutError:
        await websocket.close(code=1013)
    except WebSocketDisconnect:
        pass
    except (sqlite3.Error, OSError):
        logger.exception("Invalidation stream unavailable")
        await websocket.close(code=1013)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
