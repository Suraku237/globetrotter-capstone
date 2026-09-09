import asyncio
import importlib.util
import socket
import threading
import time
from pathlib import Path

import pytest
import uvicorn
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt
from starlette.websockets import WebSocketDisconnect
from websockets.exceptions import ConnectionClosedError
from websockets.frames import Close


@pytest.fixture
def gateway():
    path = Path(__file__).resolve().parents[2] / "api-gateway" / "app" / "main.py"
    spec = importlib.util.spec_from_file_location("event_gateway_test", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    yield module
    asyncio.run(module._client.aclose())


def test_gateway_relays_first_frame_without_url_credentials(gateway, monkeypatch):
    received = []
    options = {}

    class Upstream:
        def __init__(self):
            self.messages = asyncio.Queue(maxsize=4)

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            pass

        async def send(self, message):
            received.append(message)
            await self.messages.put('{"type":"ready","topics":["all"]}')

        async def recv(self):
            return await self.messages.get()

    def connect(url, **kwargs):
        options.update(url=url, **kwargs)
        return Upstream()

    monkeypatch.setattr(gateway, "connect", connect)
    monkeypatch.setattr(gateway, "DATA_SERVICE_URL", "https://data.internal/prefix")
    with TestClient(gateway.app).websocket_connect("/events/ws") as socket:
        socket.send_json({"token": "only-in-frame"})
        assert socket.receive_json() == {"type": "ready", "topics": ["all"]}
    assert options["url"] == "wss://data.internal/prefix/events/ws"
    assert options["max_queue"] == 4
    assert options["max_size"] == 8192
    assert received == ['{"token":"only-in-frame"}']


def test_gateway_preserves_authentication_close_code(gateway, monkeypatch):
    class Rejected:
        async def __aenter__(self):
            raise ConnectionClosedError(Close(4401, ""), Close(4401, ""), True)

        async def __aexit__(self, *args):
            pass

    monkeypatch.setattr(gateway, "connect", lambda *args, **kwargs: Rejected())
    with TestClient(gateway.app).websocket_connect("/events/ws") as socket:
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 4401


def test_gateway_rejects_query_before_connecting_upstream(gateway, monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("A query credential must never be forwarded upstream")

    monkeypatch.setattr(gateway, "connect", forbidden)
    with TestClient(gateway.app).websocket_connect("/events/ws?token=bad") as socket:
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 4400


def test_gateway_unavailable_upstream_closes_with_retry_code(gateway, monkeypatch):
    def unavailable(*args, **kwargs):
        raise OSError("upstream down")

    monkeypatch.setattr(gateway, "connect", unavailable)
    with TestClient(gateway.app).websocket_connect("/events/ws") as socket:
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 1013


def test_real_gateway_to_data_service_websocket(gateway, monkeypatch):
    from app import event_store, events, security

    monkeypatch.setattr(security, "load_users", lambda: [{"id": "alice"}])
    monkeypatch.setattr(events, "POLL_SECONDS", 0.01)
    app = FastAPI()
    app.include_router(events.router)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(
        app, log_level="error", lifespan="off", ws="websockets", ws_max_size=8192,
    ))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 5
        while not server.started and thread.is_alive() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert server.started
        monkeypatch.setattr(gateway, "DATA_SERVICE_URL", f"http://127.0.0.1:{port}")
        assert security.SECRET_KEY is not None
        with TestClient(gateway.app).websocket_connect("/events/ws") as stream:
            stream.send_json({"token": jwt.encode(
                {"sub": "alice"}, security.SECRET_KEY, algorithm="HS256",
            )})
            assert stream.receive_json() == {"type": "ready", "topics": ["all"]}
            event_store.publish(["calls"], ["alice"])
            assert stream.receive_json() == {"type": "invalidate", "topics": ["calls"]}
        with TestClient(gateway.app).websocket_connect("/events/ws") as stream:
            stream.send_json({"token": "invalid"})
            with pytest.raises(WebSocketDisconnect) as error:
                stream.receive_json()
            assert error.value.code == 4401
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        listener.close()
    assert not thread.is_alive()
