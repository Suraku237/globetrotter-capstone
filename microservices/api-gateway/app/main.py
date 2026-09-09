"""
Single public entry point for the whole backend.

The Flutter app only ever talks to this service (baseUrl in
frontend/fast_travel/lib/Services/api_service.dart). It forwards each
request untouched — method, headers, query string, body — to whichever
internal service owns that route, and streams the response straight back.
This keeps the app's URLs (e.g. POST /login, GET /destinations) stable even
though auth and data now live in separate containers.
"""

import asyncio
import os
from urllib.parse import urlsplit, urlunsplit

import httpx
from fastapi import FastAPI, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from websockets.legacy.client import connect
from websockets.exceptions import ConnectionClosed, WebSocketException

app = FastAPI(title="GlobeTrotter API Gateway", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

AUTH_SERVICE_URL = os.getenv("AUTH_SERVICE_URL", "http://auth-service:8000")
DATA_SERVICE_URL = os.getenv("DATA_SERVICE_URL", "http://data-service:8000")

# Route by path prefix. Everything not matched here falls through to the
# data service, since that's where the majority of routes (destinations,
# itineraries, recommendations, stats, images) live.
AUTH_PREFIXES = (
    "/register",
    "/login",
    "/auth",
    "/me",
    "/verify-email",
    "/admin-requests",
)

_client = httpx.AsyncClient(timeout=30.0)


def _upstream_for(path: str) -> str:
    if path.startswith(AUTH_PREFIXES):
        return AUTH_SERVICE_URL
    return DATA_SERVICE_URL


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/events/ws")
async def event_socket(websocket: WebSocket):
    await websocket.accept()
    if websocket.query_params:
        await websocket.close(code=4400)
        return
    upstream = urlsplit(DATA_SERVICE_URL)
    url = urlunsplit((
        "wss" if upstream.scheme == "https" else "ws",
        upstream.netloc, upstream.path.rstrip("/") + "/events/ws", "", "",
    ))
    tasks = []
    try:
        async with connect(
            url, max_size=8192, max_queue=4, open_timeout=5,
            ping_interval=20, ping_timeout=20, close_timeout=2,
        ) as connection:
            async def forward_client():
                while True:
                    text = await websocket.receive_text()
                    if len(text.encode("utf-8")) > 8192:
                        await websocket.close(code=1009)
                        return
                    await asyncio.wait_for(connection.send(text), 5)

            async def forward_server():
                while True:
                    text = await connection.recv()
                    if not isinstance(text, str):
                        await websocket.close(code=4400)
                        return
                    await asyncio.wait_for(websocket.send_text(text), 5)

            tasks = [
                asyncio.create_task(forward_client()),
                asyncio.create_task(forward_server()),
            ]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
    except WebSocketDisconnect:
        pass
    except ConnectionClosed as exc:
        code = exc.code if exc.code not in {1005, 1006, 1015} else 1013
        await websocket.close(code=code)
    except (OSError, asyncio.TimeoutError, WebSocketException):
        await websocket.close(code=1013)
    except (KeyError, TypeError):
        await websocket.close(code=4400)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


@app.api_route(
    "/{full_path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
)
async def proxy(full_path: str, request: Request):
    upstream = _upstream_for("/" + full_path)
    url = f"{upstream}/{full_path}"

    body = await request.body()
    headers = {
        k: v for k, v in request.headers.items() if k.lower() != "host"
    }

    upstream_response = await _client.request(
        request.method,
        url,
        params=request.query_params,
        headers=headers,
        content=body,
    )

    response_headers = {
        k: v
        for k, v in upstream_response.headers.items()
        if k.lower() not in ("content-encoding", "transfer-encoding", "connection")
    }

    return Response(
        content=upstream_response.content,
        status_code=upstream_response.status_code,
        headers=response_headers,
    )
