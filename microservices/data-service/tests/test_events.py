import asyncio
import importlib.util
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt
from starlette.websockets import WebSocketDisconnect

from app import calls, chat, destinations, event_store, events, itineraries, models, posts, security, social


@pytest.fixture
def live_store(tmp_path, monkeypatch):
    users = [
        {"id": name, "username": name, "full_name": name.title()}
        for name in ("alice", "bob", "carol")
    ]
    monkeypatch.setattr(security, "load_users", lambda: users)
    monkeypatch.setattr(social, "load_users", lambda: users)
    monkeypatch.setattr(social, "FRIENDSHIPS_FILE", tmp_path / "friends.json")
    monkeypatch.setattr(social, "DIRECT_THREADS_FILE", tmp_path / "direct_threads.json")
    monkeypatch.setattr(social, "GROUPS_FILE", tmp_path / "groups.json")
    monkeypatch.setattr(chat, "ROOM_FILE", tmp_path / "room.json")
    monkeypatch.setattr(calls, "CALLS_FILE", tmp_path / "calls.json")
    monkeypatch.setattr(calls, "DEVICES_FILE", tmp_path / "devices.json")
    monkeypatch.setattr(events, "POLL_SECONDS", 0.01)
    app = FastAPI()
    app.include_router(events.router)
    app.include_router(social.router)
    app.include_router(chat.router)
    app.include_router(calls.router)
    return TestClient(app), users


def token(user="alice", **claims):
    assert security.SECRET_KEY is not None
    return jwt.encode(
        {"sub": user, "exp": int(time.time()) + 60, **claims},
        security.SECRET_KEY, algorithm="HS256",
    )


def headers(user="alice"):
    return {"Authorization": "Bearer " + token(user)}


def connect(client):
    socket = client.websocket_connect("/events/ws")
    return socket


def authenticate(socket, user="alice"):
    socket.send_json({"token": token(user)})
    assert socket.receive_json() == {"type": "ready", "topics": ["all"]}


def test_audience_isolation_and_cross_process_delivery(live_store):
    client, _ = live_store
    with connect(client) as alice, connect(client) as bob, connect(client) as carol:
        for socket, user in ((alice, "alice"), (bob, "bob"), (carol, "carol")):
            authenticate(socket, user)
        # A separate interpreter represents a writer in another Uvicorn worker.
        result = subprocess.run(
            [sys.executable, "-c", (
                "from pathlib import Path; from app.event_store import EventJournal; "
                "import sys; j = EventJournal(Path(sys.argv[1])); "
                "j.publish(['friends'], ['alice', 'bob']); j.publish(['chat'])"
            ), str(event_store.journal.path)],
            cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr
        for socket in (alice, bob):
            received = set()
            while "chat" not in received:
                received.update(socket.receive_json()["topics"])
            assert received == {"friends", "chat"}
        assert carol.receive_json() == {"type": "invalidate", "topics": ["chat"]}


@pytest.mark.parametrize("bad_token", [
    "not-a-jwt", token("unknown"), token(purpose="admin_approval_status"), token(exp=1),
])
def test_socket_rejects_invalid_scoped_expired_and_missing_users(live_store, bad_token):
    client, _ = live_store
    with connect(client) as socket:
        socket.send_json({"token": bad_token})
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 4401


@pytest.mark.parametrize("frame", ["[]", "invalid-json", '{"token": 123}'])
def test_invalid_auth_frames_are_rejected(live_store, frame):
    client, _ = live_store
    with connect(client) as socket:
        socket.send_text(frame)
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code in {4400, 4401}


def test_query_tokens_are_not_accepted(live_store):
    client, _ = live_store
    with client.websocket_connect("/events/ws?token=must-not-be-used") as socket:
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 4400


def test_first_frame_deadline_and_oversized_auth(live_store, monkeypatch):
    client, _ = live_store
    monkeypatch.setattr(events, "AUTH_TIMEOUT", 0.03)
    with connect(client) as socket:
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 1013
    with connect(client) as socket:
        socket.send_text("x" * (events.MAX_FRAME_BYTES + 1))
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 1009


def test_client_cannot_change_audience(live_store):
    client, _ = live_store
    with connect(client) as socket:
        authenticate(socket, "carol")
        socket.send_json({"type": "subscribe", "user_id": "alice", "topics": ["calls"]})
        with pytest.raises(WebSocketDisconnect) as error:
            socket.receive_json()
        assert error.value.code == 4400


def test_heartbeat_revalidates_deleted_user(live_store, monkeypatch):
    client, users = live_store
    monkeypatch.setattr(events, "HEARTBEAT_SECONDS", 0.03)
    with connect(client) as socket:
        authenticate(socket)
        socket.send_json({"type": "ping"})
        assert socket.receive_json() == {"type": "invalidate", "topics": []}
        users[:] = [user for user in users if user["id"] != "alice"]
        with pytest.raises(WebSocketDisconnect) as error:
            # A heartbeat may already have been sent before the deletion.
            while True:
                socket.receive_json()
        assert error.value.code == 4401


def test_friendship_send_accept_decline_and_group_target_all_members(live_store):
    _, users = live_store
    alice, bob, _ = users
    for action in ("accept", "decline"):
        social._save(social.FRIENDSHIPS_FILE, [])
        cursor = event_store.journal.watermark()
        request = social.send_friend_request(
            social.FriendRequestCreate(username="bob"), current_user=alice,
        )
        for user in (alice, bob):
            assert event_store.journal.read(user["id"], cursor)[1] == ["friends"]
        assert event_store.journal.read("carol", cursor)[1] == []
        cursor = event_store.journal.watermark()
        if action == "accept":
            social.accept_friend_request(request["request_id"], current_user=bob)
        else:
            social.decline_friend_request(request["request_id"], current_user=bob)
        for user in (alice, bob):
            assert event_store.journal.read(user["id"], cursor)[1] == ["friends"]
        assert event_store.journal.read("carol", cursor)[1] == []
    request = social.send_friend_request(social.FriendRequestCreate(username="bob"), alice)
    social.accept_friend_request(request["request_id"], bob)
    cursor = event_store.journal.watermark()
    social.create_group(social.GroupCreate(name="Trip", member_ids=["bob"]), alice)
    assert event_store.journal.read("bob", cursor)[1] == ["friends"]
    assert event_store.journal.read("alice", cursor)[1] == ["friends"]
    assert event_store.journal.read("carol", cursor)[1] == []


@pytest.mark.parametrize("target", ["direct", "group"])
def test_private_message_invalidations_target_members_only(live_store, target):
    _, users = live_store
    alice, _, _ = users
    social._save(social.FRIENDSHIPS_FILE, [{
        "requester_id": "alice", "recipient_id": "bob", "status": "accepted",
    }])
    social._save(social.GROUPS_FILE, [{
        "id": "trip", "member_ids": ["alice", "bob"], "messages": [],
    }])
    cursor = event_store.journal.watermark()
    payload = social.TextMessageCreate(text="Private hello")
    if target == "direct":
        social.send_direct_message("bob", payload, alice)
    else:
        social.send_group_message("trip", payload, alice)
    assert event_store.journal.read("alice", cursor)[1] == ["friends"]
    assert event_store.journal.read("bob", cursor)[1] == ["friends"]
    assert event_store.journal.read("carol", cursor)[1] == []


@pytest.mark.parametrize("target", ["direct", "group"])
def test_private_history_pagination_and_permissions(live_store, target):
    client, _ = live_store
    messages = [
        {"id": f"message-{i}", "text": f"Hello {i}", "created_at": "same-timestamp"}
        for i in range(5)
    ]
    social._save(social.FRIENDSHIPS_FILE, [{
        "requester_id": "alice", "recipient_id": "bob", "status": "accepted",
    }])
    social._save(social.DIRECT_THREADS_FILE, [{
        "id": "thread", "participant_ids": ["alice", "bob"], "messages": messages,
    }])
    social._save(social.GROUPS_FILE, [{
        "id": "trip", "member_ids": ["alice", "bob"], "messages": messages,
    }])
    path = (
        "/social/friends/bob/messages"
        if target == "direct" else "/social/groups/trip/messages"
    )
    assert client.get(path, headers=headers()).json() == messages
    assert client.get(path + "?limit=2", headers=headers()).json() == messages[-2:]
    assert client.get(
        path + "?limit=2&before=message-3", headers=headers(),
    ).json() == messages[1:3]
    assert client.get(
        path + "?before=message-3", headers=headers(),
    ).json() == messages[:3]
    assert client.get(
        path + "?limit=2&before=message-0", headers=headers(),
    ).json() == []
    for invalid in ("limit=0", "limit=201", "limit=bad", "before="):
        assert client.get(path + "?" + invalid, headers=headers()).status_code == 422
    assert client.get(path + "?limit=2&before=missing", headers=headers()).status_code == 404
    assert client.get(path + "?limit=2").status_code == 401
    # Membership is checked before looking up cursor IDs, avoiding a history oracle.
    for cursor in ("message-3", "missing"):
        assert client.get(
            path + f"?limit=2&before={cursor}", headers=headers("carol"),
        ).status_code == 403


def test_call_invalidation_precedes_slow_push_and_tracks_active_end(live_store, monkeypatch):
    client, users = live_store
    alice, bob, _ = users
    social._save(social.FRIENDSHIPS_FILE, [{
        "requester_id": "alice", "recipient_id": "bob", "status": "accepted",
    }])
    monkeypatch.setattr(calls.providers, "livekit_config", lambda: None)
    monkeypatch.setattr(calls.providers, "join_token", lambda *args: ("wss://example.test", "join"))
    monkeypatch.setattr(calls.providers, "cleanup_room", lambda *args: None)
    started, release = threading.Event(), threading.Event()

    def slow_push(*args):
        started.set()
        assert release.wait(5)

    monkeypatch.setattr(calls.providers, "send_push", slow_push)
    calls.register_device(
        calls.CallDevice(token="test-device", platform="android", kind="fcm"), bob,
    )
    with connect(client) as socket:
        authenticate(socket, "bob")
        cursor = event_store.journal.watermark()
        call = calls.create_call(
            calls.CallCreate(kind="video", target_type="direct", target_id="bob"), alice,
            idempotency_key=None,
        )
        with ThreadPoolExecutor(max_workers=1) as pool:
            worker = pool.submit(calls.maintain_calls)
            try:
                assert started.wait(3)
                assert socket.receive_json() == {"type": "invalidate", "topics": ["calls"]}
                assert event_store.journal.read("alice", cursor)[1] == ["calls"]
                assert event_store.journal.read("carol", cursor)[1] == []
                calls.accept_call(call["id"], bob)
                assert socket.receive_json() == {"type": "invalidate", "topics": ["calls"]}
                cursor = event_store.journal.watermark()
                calls.heartbeat(call["id"], bob)
                assert event_store.journal.watermark() == cursor
                calls.leave_call(call["id"], alice)
                assert socket.receive_json() == {"type": "invalidate", "topics": ["calls"]}
            finally:
                release.set()
            worker.result(timeout=5)


def test_reconnect_resync_and_mutation_racing_ready(live_store, monkeypatch):
    client, _ = live_store
    with connect(client) as socket:
        authenticate(socket)
    event_store.publish(["friends"], ["alice"])
    with connect(client) as socket:
        authenticate(socket)
        # First ready is sufficient catch-up; no saved client sequence required.
    original = events._send

    async def race_ready(websocket, kind, topics):
        if kind == "ready":
            event_store.publish(["calls"], ["alice"])
        await original(websocket, kind, topics)

    monkeypatch.setattr(events, "_send", race_ready)
    with connect(client) as socket:
        authenticate(socket)
        assert socket.receive_json() == {"type": "invalidate", "topics": ["calls"]}


def test_history_is_bounded_and_slow_subscribers_resync(live_store, monkeypatch):
    client, _ = live_store
    monkeypatch.setattr(event_store, "HISTORY_LIMIT", 4)
    with connect(client) as socket:
        authenticate(socket)
        # One transaction advances beyond the subscriber's old cursor.
        event_store.publish(["friends"], [f"user-{i}" for i in range(12)])
        assert socket.receive_json() == {"type": "ready", "topics": ["all"]}
    with event_store.journal.connection() as connection:
        assert connection.execute("SELECT COUNT(*) FROM invalidations").fetchone()[0] == 4
    assert event_store.journal.read("alice", 0)[2]


def test_slow_socket_send_has_deadline(monkeypatch):
    monkeypatch.setattr(events, "SEND_TIMEOUT", 0.01)

    async def slow_send(message):
        await asyncio.sleep(30)

    socket = AsyncMock()
    socket.send_json.side_effect = slow_send
    with pytest.raises(asyncio.TimeoutError):
        asyncio.run(events._send(socket, "ready", ["all"]))


def test_room_changes_broadcast_and_pagination_is_backward_compatible(live_store):
    client, _ = live_store
    ids = []
    with connect(client) as socket:
        authenticate(socket, "carol")
        for i in range(5):
            response = client.post("/chat/room/messages", headers=headers(), json={
                "type": "text", "content": f"Message {i}",
            })
            assert response.status_code == 201
            ids.append(response.json()["id"])
            assert socket.receive_json() == {"type": "invalidate", "topics": ["chat"]}
        latest = client.get("/chat/room/messages?limit=2", headers=headers()).json()
        assert [item["id"] for item in latest] == ids[-2:]
        older = client.get(
            f"/chat/room/messages?limit=2&before={ids[-2]}", headers=headers(),
        ).json()
        assert [item["id"] for item in older] == ids[1:3]
        assert len(client.get("/chat/room/messages", headers=headers()).json()) == 5
        assert client.get(
            f"/chat/room/messages?limit=2&before={ids[0]}", headers=headers(),
        ).json() == []
        assert client.post(
            f"/chat/room/messages/{ids[-1]}/react",
            headers=headers("bob"), json={"emoji": "👍"},
        ).status_code == 200
        assert socket.receive_json() == {"type": "invalidate", "topics": ["chat"]}
        assert client.delete(
            f"/chat/room/messages/{ids[-1]}", headers=headers(),
        ).status_code == 200
        assert socket.receive_json() == {"type": "invalidate", "topics": ["chat"]}
    for query in ("limit=0", "limit=201", "limit=bad"):
        assert client.get("/chat/room/messages?" + query, headers=headers()).status_code == 422
    assert client.get(
        "/chat/room/messages?limit=2&before=unknown", headers=headers(),
    ).status_code == 404
    assert client.get("/chat/room/messages?limit=2").status_code == 401


def test_failed_mutation_does_not_invalidate(live_store):
    client, _ = live_store
    before = event_store.journal.watermark()
    assert client.post(
        "/social/friends/requests", headers=headers(), json={"username": "unknown"},
    ).status_code == 404
    assert client.post(
        "/chat/room/messages", headers=headers(), json={"type": "text", "content": " "},
    ).status_code == 400
    assert event_store.journal.watermark() == before


def test_auth_service_publisher_uses_same_journal_and_isolates_profiles(live_store, monkeypatch):
    _, users = live_store
    path = Path(__file__).resolve().parents[2] / "auth-service" / "app" / "events.py"
    spec = importlib.util.spec_from_file_location("app.auth_events_test", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "DATA_DIR", event_store.journal.path.parent)
    social._save(module.DATA_DIR / "friendships.json", [{
        "requester_id": "alice", "recipient_id": "bob", "status": "accepted",
    }])
    updated = [{**user, "full_name": "New Alice"} if user["id"] == "alice" else user for user in users]
    module.users_changed(users, updated)
    assert event_store.journal.read("alice", 0)[1] == ["friends", "profile", "recommendations"]
    assert event_store.journal.read("bob", 0)[1] == ["friends"]
    assert event_store.journal.read("carol", 0)[1] == []
    module.users_changed(updated, updated)
    cursor = event_store.journal.watermark()
    module.users_changed(updated, updated + [{"id": "new-user"}])
    assert event_store.journal.read("carol", cursor)[1] == ["stats"]


def test_content_mutations_invalidate_only_relevant_audiences(live_store, tmp_path, monkeypatch):
    _, users = live_store
    alice, _, _ = users
    monkeypatch.setattr(models, "POSTS_FILE", tmp_path / "posts.json")
    monkeypatch.setattr(models, "DESTINATIONS_FILE", tmp_path / "destinations.json")
    monkeypatch.setattr(models, "ITINERARIES_FILE", tmp_path / "itineraries.json")
    post = asyncio.run(posts.create_post("Hello", None, None, alice))
    assert event_store.journal.read("carol", 0)[1] == ["posts"]
    cursor = event_store.journal.watermark()
    posts.like_post(post["id"], alice)
    assert event_store.journal.read("bob", cursor)[1] == ["posts"]
    models._save(models.DESTINATIONS_FILE, [{"id": "place", "status": "pending"}])
    cursor = event_store.journal.watermark()
    destinations.approve_destination("place", alice)
    assert event_store.journal.read("bob", cursor)[1] == ["destinations", "recommendations"]
    cursor = event_store.journal.watermark()
    itineraries.create_itinerary(models.ItineraryCreate(
        title="Trip", destination_id="place", start_date="2026-12-01", end_date="2026-12-02",
    ), alice)
    assert event_store.journal.read("alice", cursor)[1] == ["itineraries"]
    assert event_store.journal.read("bob", cursor)[1] == []
