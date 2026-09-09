import time
import threading
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt

from app import calls, event_store, security, social


@pytest.fixture
def store(tmp_path, monkeypatch):
    monkeypatch.setattr(calls, "CALLS_FILE", tmp_path / "calls.json")
    monkeypatch.setattr(calls, "DEVICES_FILE", tmp_path / "devices.json")
    monkeypatch.setattr(social, "FRIENDSHIPS_FILE", tmp_path / "friends.json")
    monkeypatch.setattr(social, "GROUPS_FILE", tmp_path / "groups.json")
    users = [{"id": name, "full_name": name.title()} for name in ("alice", "bob", "carol", "outsider")]
    monkeypatch.setattr(social, "load_users", lambda: users)
    monkeypatch.setattr(security, "load_users", lambda: users)
    social._save(social.FRIENDSHIPS_FILE, [
        {"requester_id": "alice", "recipient_id": name, "status": "accepted"}
        for name in ("bob", "carol")
    ])
    social._save(social.GROUPS_FILE, [
        {"id": "group", "name": "Travel", "member_ids": ["alice", "bob", "carol"]}
    ])
    monkeypatch.setenv("LIVEKIT_URL", "wss://example.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", "test-key")
    monkeypatch.setenv("LIVEKIT_API_SECRET", "test-secret")
    clock = {"now": time.time()}
    monkeypatch.setattr(calls.time, "time", lambda: clock["now"])
    pushed, cleaned = [], []
    monkeypatch.setattr(calls.providers, "send_push", lambda device, data: pushed.append((dict(device), dict(data))))
    monkeypatch.setattr(calls.providers, "cleanup_room", lambda room, identity=None: cleaned.append((room, identity)))
    monkeypatch.setattr(calls.providers, "participant_present", lambda room, identity: False, raising=False)
    app = FastAPI()
    app.include_router(calls.router)
    client = TestClient(app)

    def request(method, path, user="alice", **kwargs):
        headers = kwargs.pop("headers", {})
        if user:
            token = jwt.encode({"sub": user}, security.SECRET_KEY, algorithm="HS256")
            headers["Authorization"] = f"Bearer {token}"
        return client.request(method, "/social" + path, headers=headers, **kwargs)

    return request, clock, pushed, cleaned


def create(request, target_type="direct", target_id="bob", kind="voice", **kwargs):
    return request("POST", "/calls", json={
        "kind": kind, "target_type": target_type, "target_id": target_id,
    }, **kwargs)


def test_auth_and_cross_user_isolation(store):
    request, _, _, _ = store
    assert create(request, user=None).status_code == 401
    call = create(request).json()
    for action in ("", "/accept", "/token", "/decline", "/leave", "/heartbeat"):
        method = "GET" if not action else "POST"
        assert request(method, f"/calls/{call['id']}{action}", user="outsider").status_code == 404
        assert request(method, f"/calls/{call['id']}{action}", user=None).status_code == 401
    assert request("GET", "/calls/incoming", user="outsider").json() == []
    assert request("GET", "/calls/incoming", user="bob").json() == [{**call, "title": "Alice"}]
    assert not any(key.startswith("_") for key in call)
    assert set(call) == set(calls.PUBLIC_FIELDS)
    for method in ("POST", "DELETE"):
        assert request(method, "/call-devices", user=None, json={
            "token": "fake-token", "platform": "android", "kind": "fcm",
        }).status_code == 401
    token = jwt.encode(
        {"sub": "alice", "purpose": "admin_approval"}, security.SECRET_KEY, algorithm="HS256"
    )
    assert request("GET", "/calls/incoming", user=None, headers={
        "Authorization": f"Bearer {token}",
    }).status_code == 401


@pytest.mark.parametrize("changes,status", [
    ({"kind": "screen"}, 422), ({"target_type": "public"}, 422),
    ({"target_id": "outsider"}, 403), ({"target_id": "missing"}, 404),
    ({"target_id": "alice"}, 400), ({"target_type": "group", "target_id": "missing"}, 404),
    ({"target_type": "group", "target_id": "group", "user": "outsider"}, 403),
])
def test_invalid_calls(store, changes, status):
    request, _, _, _ = store
    assert create(request, **changes).status_code == status


def test_voice_video_token_grants_and_accept_gate(store):
    request, _, _, _ = store
    call = create(request).json()
    assert request("POST", f"/calls/{call['id']}/token", user="bob").status_code == 403
    joined = request("POST", f"/calls/{call['id']}/token").json()
    claims = jwt.decode(joined["token"], "test-secret", algorithms=["HS256"])
    assert joined["url"] == "wss://example.livekit.cloud"
    assert claims["sub"] == "alice"
    assert claims["iss"] == "test-key"
    assert claims["exp"] - claims["iat"] == calls.providers.TOKEN_SECONDS
    assert claims["video"]["canPublishSources"] == ["microphone"]
    assert claims["video"]["roomJoin"]
    assert not claims["video"]["canPublishData"]
    assert "roomAdmin" not in claims["video"]
    assert "roomCreate" not in claims["video"]
    assert claims["video"]["room"] != call["target_id"]
    accepted = request("POST", f"/calls/{call['id']}/accept", user="bob").json()
    assert accepted["call"]["status"] == "active"
    assert accepted["call"]["accepted_ids"] == ["alice", "bob"]
    assert request("POST", f"/calls/{call['id']}/accept", user="bob").json()["call"] == accepted["call"]
    request("POST", f"/calls/{call['id']}/leave")
    video = create(request, kind="video").json()
    second = request("POST", f"/calls/{video['id']}/token").json()
    second_claims = jwt.decode(second["token"], "test-secret", algorithms=["HS256"])
    assert second_claims["video"]["room"] != claims["video"]["room"]
    assert second_claims["video"]["canPublishSources"] == ["microphone", "camera"]


@pytest.mark.parametrize("action,user,reason", [
    ("decline", "bob", "declined"), ("leave", "alice", "cancelled"),
])
def test_direct_terminal_idempotency(store, action, user, reason):
    request, _, _, _ = store
    call_id = create(request).json()["id"]
    path = f"/calls/{call_id}"
    ended = request("POST", f"{path}/{action}", user=user).json()
    assert ended["status"] == "ended" and ended["ended_reason"] == reason
    assert ended["accepted_ids"] == []
    assert request("POST", f"{path}/{action}", user=user).json() == ended
    assert request("POST", f"{path}/heartbeat").json() == {**ended, "title": "Bob"}
    assert request("POST", f"{path}/token").status_code == 409
    assert request("POST", f"{path}/accept", user="bob").status_code == 409
    assert request("GET", "/calls/incoming", user="bob").json() == []


def test_group_departure_keeps_others_and_last_leave_ends(store):
    request, _, _, cleaned = store
    call_id = create(request, "group", "group").json()["id"]
    path = f"/calls/{call_id}"
    request("POST", f"{path}/token")
    request("POST", f"{path}/accept", user="bob")
    request("POST", f"{path}/accept", user="carol")
    left = request("POST", f"{path}/leave").json()
    assert left["status"] == "active" and left["accepted_ids"] == ["bob", "carol"]
    assert request("POST", f"{path}/accept").status_code == 409
    calls.maintain_calls()
    assert cleaned[-1][1] == "alice"
    assert request("POST", f"{path}/leave", user="bob").json()["status"] == "active"
    assert request("POST", f"{path}/leave", user="carol").json()["status"] == "ended"
    calls.maintain_calls()
    assert cleaned[-1][1] is None


def test_group_all_declined_and_partial_decline(store):
    request, _, _, _ = store
    call_id = create(request, "group", "group").json()["id"]
    path = f"/calls/{call_id}"
    assert request("POST", f"{path}/decline", user="bob").json()["status"] == "ringing"
    assert request("POST", f"{path}/decline", user="carol").json()["ended_reason"] == "declined"


def test_timeouts_and_leases_without_requests(store):
    request, clock, _, _ = store
    call_id = create(request).json()["id"]
    clock["now"] += calls.RING_SECONDS
    calls.maintain_calls()
    assert social._load_list(calls.CALLS_FILE)[0]["ended_reason"] == "no_answer"
    assert request("POST", f"/calls/{call_id}/accept", user="bob").status_code == 409
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/accept", user="bob")
    clock["now"] += 40
    request("POST", f"/calls/{call_id}/heartbeat")
    clock["now"] += 16
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["ended_reason"] == "connection_lost"


def test_restart_after_long_absence_still_reports_no_answer(store):
    request, clock, _, _ = store
    call_id = create(request).json()["id"]
    clock["now"] += 600
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["ended_reason"] == "no_answer"


def test_group_lease_expiration_preserves_healthy_members(store):
    request, clock, _, _ = store
    call_id = create(request, "group", "group").json()["id"]
    path = f"/calls/{call_id}"
    request("POST", f"{path}/accept", user="bob")
    request("POST", f"{path}/accept", user="carol")
    clock["now"] += 40
    request("POST", f"{path}/heartbeat", user="bob")
    request("POST", f"{path}/heartbeat", user="carol")
    clock["now"] += 16
    calls.maintain_calls()
    call = request("GET", path, user="bob").json()
    assert call["status"] == "active" and call["accepted_ids"] == ["bob", "carol"]
    assert request("POST", f"{path}/token").status_code == 409


def test_pending_group_invitation_does_not_outlive_deadline(store):
    request, clock, _, _ = store
    call_id = create(request, "group", "group").json()["id"]
    path = f"/calls/{call_id}"
    request("POST", f"{path}/accept", user="bob")
    clock["now"] += calls.RING_SECONDS
    assert request("GET", "/calls/incoming", user="carol").json() == []
    assert request("POST", f"{path}/accept", user="carol").status_code == 409
    assert request("GET", path).json()["status"] == "active"


def test_membership_rechecked_and_connected_members_evicted(store):
    request, _, _, cleaned = store
    call_id = create(request, "group", "group").json()["id"]
    request("POST", f"/calls/{call_id}/accept", user="bob")
    social._save(social.GROUPS_FILE, [
        {"id": "group", "name": "Travel", "member_ids": ["alice", "carol"]}
    ])
    assert request("POST", f"/calls/{call_id}/token", user="bob").status_code == 403
    calls.maintain_calls()
    assert cleaned[-1][1] == "bob"
    assert request("GET", f"/calls/{call_id}").json()["accepted_ids"] == ["alice"]


def test_removed_friendship_ends_direct_call(store):
    request, _, _, _ = store
    call_id = create(request).json()["id"]
    social._save(social.FRIENDSHIPS_FILE, [])
    assert request("POST", f"/calls/{call_id}/accept", user="bob").status_code == 403
    assert social._load_list(calls.CALLS_FILE)[0]["ended_reason"] == "membership_changed"


def test_busy_and_create_idempotency(store):
    request, _, _, _ = store
    first = create(request, headers={"Idempotency-Key": "retry-key"}).json()
    assert create(request).json() == first
    assert create(request, target_id="carol").status_code == 409
    assert create(request, target_id="alice", user="bob").status_code == 409
    request("POST", f"/calls/{first['id']}/leave")
    assert create(request, headers={"Idempotency-Key": "retry-key"}).json()["status"] == "ended"
    assert create(request, target_id="carol", headers={"Idempotency-Key": "retry-key"}).status_code == 409
    assert create(request).json()["id"] != first["id"]


def test_parallel_create_and_accept_decline_are_serialized(store):
    request, _, _, _ = store
    with ThreadPoolExecutor(max_workers=6) as executor:
        results = list(executor.map(lambda _: create(request).json(), range(6)))
    assert len({call["id"] for call in results}) == 1
    assert len(social._load_list(calls.CALLS_FILE)) == 1
    call_id = results[0]["id"]
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(
            lambda action: request("POST", f"/calls/{call_id}/{action}", user="bob"),
            ["accept", "decline"],
        ))
    assert sorted(response.status_code for response in results) == [200, 409]


def test_device_transfer_old_logout_and_push_isolation(store):
    request, _, pushed, _ = store
    device = {"token": "private-token", "platform": "android", "kind": "fcm"}
    assert request("POST", "/call-devices", user="bob", json=device).json() == {"ok": True}
    create(request)
    # Transfer before queued delivery: no caller name leaks to the new account.
    request("POST", "/call-devices", user="outsider", json=device)
    request("DELETE", "/call-devices", user="bob", json=device)
    assert social._load_list(calls.DEVICES_FILE)[0]["user_id"] == "outsider"
    calls.maintain_calls()
    assert pushed == []
    request("DELETE", "/call-devices", user="outsider", json=device)
    assert social._load_list(calls.DEVICES_FILE) == []


def test_push_contract_and_stale_invites_suppressed(store):
    request, _, pushed, _ = store
    device = {"token": "bob-token", "platform": "android", "kind": "fcm"}
    request("POST", "/call-devices", user="bob", json=device)
    call = create(request).json()
    calls.maintain_calls()
    assert pushed[0][1] == {
        "type": "incoming_call", "call_id": call["id"], "caller_name": "Alice",
        "kind": "voice", "expires_at": call["expires_at"],
    }
    request("POST", f"/calls/{call['id']}/leave")
    calls.maintain_calls()
    assert pushed[-1][1] == {"type": "call_ended", "call_id": call["id"]}
    pushed.clear()
    call = create(request).json()
    request("POST", f"/calls/{call['id']}/decline", user="bob")
    calls.maintain_calls()
    assert all(data["type"] == "call_ended" for _, data in pushed)


def test_cleanup_failure_is_persisted_and_retried(store, monkeypatch, caplog):
    request, _, _, cleaned = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/leave")
    original = calls.providers.cleanup_room

    def fail(*args):
        raise calls.providers.ProviderError("offline")

    monkeypatch.setattr(calls.providers, "cleanup_room", fail)
    calls.maintain_calls()
    assert social._load_list(calls.CALLS_FILE)[0]["_cleanup"] == ["alice"]
    assert "cleanup pending" in caplog.text
    monkeypatch.setattr(calls.providers, "cleanup_room", original)
    calls.maintain_calls()
    assert social._load_list(calls.CALLS_FILE)[0]["_cleanup"] == []
    assert cleaned[-1][1] is None


def test_push_failure_retries_and_invalid_device_is_pruned(store, monkeypatch, caplog):
    request, _, _, _ = store
    device = {"token": "private-token", "platform": "android", "kind": "fcm"}
    request("POST", "/call-devices", user="bob", json=device)
    create(request)

    def failed(*args):
        raise calls.providers.ProviderError("offline")

    monkeypatch.setattr(calls.providers, "send_push", failed)
    calls.maintain_calls()
    assert social._load_list(calls.CALLS_FILE)[0]["_events"]
    assert "delivery pending" in caplog.text and "private-token" not in caplog.text

    def invalid(*args):
        raise calls.providers.InvalidDevice("invalid")

    monkeypatch.setattr(calls.providers, "send_push", invalid)
    calls.maintain_calls()
    assert social._load_list(calls.DEVICES_FILE) == []


def test_missing_provider_configuration_does_not_create_call(store, monkeypatch):
    request, _, _, _ = store
    monkeypatch.delenv("LIVEKIT_API_SECRET")
    assert create(request).status_code == 503
    assert social._load_list(calls.CALLS_FILE) == []


def test_slow_push_does_not_block_heartbeats_but_serializes_ownership(store, monkeypatch):
    request, _, _, _ = store
    device = {"token": "shared-token", "platform": "android", "kind": "fcm"}
    request("POST", "/call-devices", user="bob", json=device)
    call_id = create(request).json()["id"]
    sending = threading.Event()
    finish_send = threading.Event()

    def slow_push(device, data):
        sending.set()
        assert finish_send.wait(5)

    monkeypatch.setattr(calls.providers, "send_push", slow_push)
    with ThreadPoolExecutor(max_workers=3) as executor:
        delivery = executor.submit(calls.maintain_calls)
        assert sending.wait(2)
        transfer = executor.submit(request, "POST", "/call-devices", user="outsider", json=device)
        heartbeat = executor.submit(request, "POST", f"/calls/{call_id}/heartbeat")
        try:
            assert heartbeat.result(timeout=2).status_code == 200
            assert not transfer.done()
        finally:
            finish_send.set()
        delivery.result(timeout=3)
        assert transfer.result(timeout=3).status_code == 200
    assert social._load_list(calls.DEVICES_FILE)[0]["user_id"] == "outsider"


def test_cleanup_can_overlap_new_signalling_without_losing_writes(store, monkeypatch):
    request, _, _, _ = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/leave")
    created = []

    def cleanup(room, identity=None):
        if identity:
            created.append(create(request).json()["id"])

    monkeypatch.setattr(calls.providers, "cleanup_room", cleanup)
    calls.maintain_calls()
    assert len(social._load_list(calls.CALLS_FILE)) == 2
    assert request("GET", f"/calls/{created[0]}").json()["status"] == "ringing"


@pytest.mark.parametrize("payload", [
    {"token": " ", "platform": "android", "kind": "fcm"},
    {"token": "fake", "platform": "android", "kind": "voip"},
    {"token": "fake", "platform": "ios", "kind": "voip"},
    {"token": "a" * 4097, "platform": "web", "kind": "fcm"},
    {"token": "fake", "platform": "desktop", "kind": "fcm"},
])
def test_invalid_devices(store, payload):
    request, _, _, _ = store
    assert request("POST", "/call-devices", json=payload).status_code == 422


def test_busy_group_members_are_skipped_and_accept_denied(store):
    request, _, _, _ = store
    other = create(request, user="bob", target_id="alice").json()
    group = create(request, "group", "group", user="carol").json()
    # Both other members are busy, so there is no viable group call.
    assert "id" not in group
    assert group["detail"] == "The selected participants are busy"
    request("POST", f"/calls/{other['id']}/leave", user="bob")
    # A second friendship outside the group makes Bob busy without Alice.
    friendships = social._load_list(social.FRIENDSHIPS_FILE)
    friendships.append({"requester_id": "bob", "recipient_id": "outsider", "status": "accepted"})
    social._save(social.FRIENDSHIPS_FILE, friendships)
    create(request, user="bob", target_id="outsider")
    group_id = create(request, "group", "group").json()["id"]
    assert request("GET", "/calls/incoming", user="bob").json() == []
    assert request("POST", f"/calls/{group_id}/accept", user="bob").status_code == 409
    assert request("POST", f"/calls/{group_id}/accept", user="carol").status_code == 200


def test_atomic_save_retries_windows_sharing_violation(store, monkeypatch):
    request, _, _, _ = store
    original = calls.Path.replace
    attempts = []

    def replace(path, target):
        attempts.append(path)
        if len(attempts) == 1:
            error = PermissionError("transient test sharing violation")
            error.winerror = 32
            raise error
        return original(path, target)

    monkeypatch.setattr(calls.Path, "replace", replace)
    assert create(request).status_code == 200
    assert len(attempts) >= 2


def test_connected_background_call_survives_missing_http_heartbeats(store, monkeypatch):
    request, clock, _, cleaned = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/accept", user="bob")
    checked = []

    def present(room, identity):
        checked.append(identity)
        return True

    monkeypatch.setattr(calls.providers, "participant_present", present)
    for _ in range(3):
        clock["now"] += calls.LEASE_SECONDS + 1
        assert request("GET", f"/calls/{call_id}").json()["status"] == "active"
        calls.maintain_calls()
        assert request("GET", f"/calls/{call_id}").json()["accepted_ids"] == ["alice", "bob"]
    assert checked == ["alice", "bob"] * 3
    assert cleaned == []


def test_presence_outage_keeps_active_call_until_absence_confirmed(store, monkeypatch, caplog):
    request, clock, _, _ = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/accept", user="bob")
    clock["now"] += calls.LEASE_SECONDS + 1

    def offline(room, identity):
        raise calls.providers.ProviderError("unavailable")

    monkeypatch.setattr(calls.providers, "participant_present", offline)
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["status"] == "active"
    assert "presence check pending" in caplog.text
    monkeypatch.setattr(calls.providers, "participant_present", lambda room, identity: False)
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["ended_reason"] == "connection_lost"


def test_presence_response_cannot_override_concurrent_heartbeat(store, monkeypatch):
    request, clock, _, _ = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/accept", user="bob")
    clock["now"] += calls.LEASE_SECONDS + 1

    def disconnected_before_new_heartbeat(room, identity):
        assert request("POST", f"/calls/{call_id}/heartbeat", user=identity).status_code == 200
        return False

    monkeypatch.setattr(calls.providers, "participant_present", disconnected_before_new_heartbeat)
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["status"] == "active"


def test_group_presence_keeps_connected_members_and_expires_only_absent_member(store, monkeypatch):
    request, clock, _, cleaned = store
    call_id = create(request, "group", "group").json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/accept", user="bob")
    request("POST", f"/calls/{call_id}/accept", user="carol")
    clock["now"] += calls.LEASE_SECONDS + 1
    monkeypatch.setattr(calls.providers, "participant_present", lambda room, identity: identity != "bob")
    calls.maintain_calls()
    call = request("GET", f"/calls/{call_id}").json()
    assert call["status"] == "active" and call["accepted_ids"] == ["alice", "carol"]
    assert len(cleaned) == 1 and cleaned[0][1] == "bob"


def test_presence_cannot_resurrect_a_concurrently_ended_call(store, monkeypatch):
    request, clock, _, _ = store
    call_id = create(request).json()["id"]
    request("POST", f"/calls/{call_id}/token")
    request("POST", f"/calls/{call_id}/accept", user="bob")
    clock["now"] += calls.LEASE_SECONDS + 1

    def connected_before_leave(room, identity):
        assert request("POST", f"/calls/{call_id}/leave").status_code == 200
        return True

    monkeypatch.setattr(calls.providers, "participant_present", connected_before_leave)
    calls.maintain_calls()
    assert request("GET", f"/calls/{call_id}").json()["status"] == "ended"


def test_direct_title_is_other_participant_on_every_response(store):
    request, _, _, _ = store
    response = create(request)
    assert response.status_code == 200 and response.json()["title"] == "Bob"
    call_id = response.json()["id"]
    assert request("GET", "/calls/incoming", user="bob").json()[0]["title"] == "Alice"
    assert request("POST", f"/calls/{call_id}/accept", user="bob").json()["call"]["title"] == "Alice"
    for user, title in (("alice", "Bob"), ("bob", "Alice")):
        assert request("GET", f"/calls/{call_id}", user=user).json()["title"] == title
        assert request("POST", f"/calls/{call_id}/token", user=user).json()["call"]["title"] == title
        assert request("POST", f"/calls/{call_id}/heartbeat", user=user).json()["title"] == title
    assert request("POST", f"/calls/{call_id}/leave", user="bob").json()["title"] == "Alice"
    assert request("POST", f"/calls/{call_id}/decline", user="alice").json()["title"] == "Bob"
    assert request("POST", f"/calls/{call_id}/heartbeat", user="bob").json()["title"] == "Alice"


def test_group_title_is_not_personalized(store):
    request, _, _, _ = store
    call_id = create(request, "group", "group").json()["id"]
    for user in ("alice", "bob", "carol"):
        assert request("GET", f"/calls/{call_id}", user=user).json()["title"] == "Travel"


def test_community_discovery_requires_auth_and_explicit_join(store):
    request, _, _, _ = store
    assert request("GET", "/calls/community", user=None).status_code == 401
    assert request("GET", "/calls/community", user="missing").status_code == 401
    assert create(request, "community", "community", user=None).status_code == 401
    assert create(request, "community", "community", user="missing").status_code == 401
    assert create(request, "community", "another-room").status_code == 422
    empty = request("GET", "/calls/community")
    assert empty.status_code == 200 and empty.json() is None
    assert empty.headers["cache-control"] == "no-store"
    call = create(request, "community", "community").json()
    assert call["status"] == "active"
    assert call["participant_ids"] == call["accepted_ids"] == ["alice"]
    assert set(call) == set(calls.PUBLIC_FIELDS)
    path = f"/calls/{call['id']}"
    discovered = request("GET", "/calls/community", user="outsider")
    assert discovered.json() == call
    assert discovered.headers["cache-control"] == "no-store"
    assert request("GET", path, user="outsider").json() == call
    for action in ("accept", "token", "heartbeat", "leave", "decline"):
        assert request("POST", f"{path}/{action}", user=None).status_code == 401
        if action != "accept":
            assert request("POST", f"{path}/{action}", user="outsider").status_code == 403
    joined = request("POST", f"{path}/accept", user="outsider")
    assert joined.status_code == 200
    assert joined.json()["call"]["participant_ids"] == ["alice", "outsider"]
    assert joined.json()["call"]["accepted_ids"] == ["alice", "outsider"]
    assert request("POST", f"{path}/decline", user="outsider").status_code == 409
    # Eligibility is evaluated on join, not snapshotted when the call starts.
    social.load_users().append({"id": "new-user", "full_name": "New User"})
    assert request("POST", f"{path}/accept", user="new-user").status_code == 200


@pytest.mark.parametrize("kind,sources", [
    ("voice", ["microphone"]), ("video", ["microphone", "camera"]),
])
def test_community_tokens_and_no_native_events_at_any_stage(store, kind, sources):
    request, clock, pushed, _ = store
    for index, user in enumerate(("alice", "bob", "carol", "outsider"), 1):
        for platform, device_kind, token in (
            ("android", "fcm", f"{user}-token"),
            ("ios", "voip", str(index) * 64),
        ):
            assert request("POST", "/call-devices", user=user, json={
                "platform": platform, "kind": device_kind, "token": token,
            }).status_code == 200
    call = create(request, "community", "community", kind=kind).json()
    path = f"/calls/{call['id']}"
    calls.maintain_calls()
    for user in ("alice", "bob", "carol", "outsider"):
        assert request("GET", "/calls/incoming", user=user).json() == []
    for action, user in (("token", "alice"), ("accept", "outsider")):
        joined = request("POST", f"{path}/{action}", user=user).json()
        claims = jwt.decode(joined["token"], "test-secret", algorithms=["HS256"])
        assert claims["sub"] == user
        assert claims["video"]["canPublishSources"] == sources
        assert claims["video"]["roomJoin"] and not claims["video"]["canPublishData"]
        assert "roomAdmin" not in claims["video"] and "roomCreate" not in claims["video"]
        assert claims["video"]["room"] != "community"
    calls.maintain_calls()
    assert request("POST", f"{path}/leave", user="outsider").status_code == 200
    calls.maintain_calls()
    clock["now"] += calls.LEASE_SECONDS + 1
    calls.maintain_calls()
    assert request("GET", path).json()["status"] == "ended"
    assert social._load_list(calls.CALLS_FILE)[0]["_events"] == []
    assert pushed == []
    assert request("GET", "/calls/community").json() is None


def test_community_creation_race_and_idempotency(store):
    request, _, _, _ = store
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(
            lambda user: create(request, "community", "community", user=user),
            ("alice", "bob", "carol", "outsider"),
        ))
    assert sorted(result.status_code for result in results) == [200, 409, 409, 409]
    for result in results:
        if result.status_code == 409:
            assert "join" in result.json()["detail"].lower()
    call = next(result.json() for result in results if result.status_code == 200)
    assert len(social._load_list(calls.CALLS_FILE)) == 1
    assert create(
        request, "community", "community", user=call["caller_id"]
    ).json() == call
    assert create(
        request, "community", "community", kind="video", user=call["caller_id"]
    ).status_code == 409
    assert request("POST", f"/calls/{call['id']}/leave", user=call["caller_id"]).status_code == 200
    second = create(
        request, "community", "community", headers={"Idempotency-Key": "public-retry"}
    ).json()
    assert second["id"] != call["id"]
    assert create(
        request, "community", "community", headers={"Idempotency-Key": "public-retry"}
    ).json() == second


def test_community_does_not_reserve_other_users_and_enforces_busy_joiners(store):
    request, _, _, _ = store
    call = create(request, "community", "community", user="outsider").json()
    path = f"/calls/{call['id']}"
    private = create(request).json()
    assert private["status"] == "ringing"
    assert request("POST", f"{path}/accept").status_code == 409
    assert request("POST", f"{path}/accept", user="bob").status_code == 409
    assert request("POST", f"/calls/{private['id']}/leave").status_code == 200
    assert request("POST", f"{path}/accept").status_code == 200
    assert create(request, target_id="carol").status_code == 409
    assert create(request, user="carol", target_id="alice").status_code == 409
    assert request("POST", f"{path}/leave").status_code == 200
    assert create(request, target_id="carol").status_code == 200
    assert request("POST", f"{path}/accept").status_code == 409


def test_community_busy_caller_cannot_start(store):
    request, _, _, _ = store
    create(request)
    assert create(request, "community", "community").status_code == 409
    assert request("GET", "/calls/community").json() is None


def test_community_late_join_and_no_invitation_expiration(store):
    request, clock, _, _ = store
    call = create(request, "community", "community").json()
    path = f"/calls/{call['id']}"
    clock["now"] += calls.RING_SECONDS + 1
    calls.maintain_calls()
    assert request("GET", "/calls/community").json()["status"] == "active"
    assert request("POST", f"{path}/accept", user="outsider").status_code == 200
    clock["now"] += 10
    calls.maintain_calls()
    active = request("GET", "/calls/community").json()
    assert active["accepted_ids"] == active["participant_ids"] == ["outsider"]
    assert request("POST", f"{path}/accept", user="carol").status_code == 200
    assert request("POST", f"{path}/leave", user="outsider").json()["status"] == "active"
    ended = request("POST", f"{path}/leave", user="carol").json()
    assert ended["status"] == "ended" and ended["ended_reason"] == "last_participant_left"
    assert request("GET", "/calls/community").json() is None
    assert request("POST", f"{path}/accept").status_code == 409


def test_community_without_join_token_expires_after_lease_not_ring_timeout(store):
    request, clock, _, _ = store
    call = create(request, "community", "community").json()
    clock["now"] += calls.LEASE_SECONDS
    calls.maintain_calls()
    assert request("GET", "/calls/community").json() is None
    assert request("GET", f"/calls/{call['id']}").json()["ended_reason"] == "connection_lost"


def test_community_rejoin_waits_for_failed_and_inflight_cleanup(store, monkeypatch):
    request, _, _, cleaned = store
    call = create(request, "community", "community").json()
    path = f"/calls/{call['id']}"
    request("POST", f"{path}/token")
    request("POST", f"{path}/accept", user="outsider")
    assert request("POST", f"{path}/leave").json()["participant_ids"] == ["outsider"]
    for action in ("token", "heartbeat", "leave", "decline"):
        assert request("POST", f"{path}/{action}").status_code == 403
    assert request("POST", f"{path}/accept").status_code == 409
    original = calls.providers.cleanup_room

    def fail(room, identity=None):
        raise calls.providers.ProviderError("offline")

    monkeypatch.setattr(calls.providers, "cleanup_room", fail)
    calls.maintain_calls()
    assert request("POST", f"{path}/accept").status_code == 409
    cleaning, finish = threading.Event(), threading.Event()

    def slow_cleanup(room, identity=None):
        cleaning.set()
        assert finish.wait(5)
        original(room, identity)

    monkeypatch.setattr(calls.providers, "cleanup_room", slow_cleanup)
    with ThreadPoolExecutor(max_workers=2) as executor:
        pending = executor.submit(calls.maintain_calls)
        try:
            assert cleaning.wait(2)
            assert request("POST", f"{path}/accept").status_code == 409
            assert request("POST", f"{path}/heartbeat", user="outsider").status_code == 200
        finally:
            finish.set()
        pending.result(timeout=3)
    monkeypatch.setattr(calls.providers, "cleanup_room", original)
    rejoined = request("POST", f"{path}/accept")
    assert rejoined.status_code == 200
    assert rejoined.json()["call"]["accepted_ids"] == ["outsider", "alice"]
    assert request("POST", f"{path}/accept").json()["call"] == rejoined.json()["call"]
    assert social._load_list(calls.CALLS_FILE)[0]["_departed"] == []
    calls.maintain_calls()
    assert len(cleaned) == 1
    assert request("POST", f"{path}/leave").status_code == 200
    assert request("POST", f"{path}/accept").status_code == 409
    calls.maintain_calls()
    assert len(cleaned) == 2
    assert request("POST", f"{path}/accept").status_code == 200


def test_community_unissued_caller_can_rejoin_immediately(store):
    request, _, _, cleaned = store
    call = create(request, "community", "community").json()
    path = f"/calls/{call['id']}"
    request("POST", f"{path}/accept", user="outsider")
    request("POST", f"{path}/leave")
    assert request("POST", f"{path}/accept").status_code == 200
    assert cleaned == []


def test_community_deleted_accounts_are_removed_and_cannot_rejoin(store):
    request, _, _, cleaned = store
    call = create(request, "community", "community").json()
    path = f"/calls/{call['id']}"
    request("POST", f"{path}/accept", user="outsider")
    users = social.load_users()
    users[:] = [user for user in users if user["id"] != "outsider"]
    calls.maintain_calls()
    assert request("GET", "/calls/community").json()["participant_ids"] == ["alice"]
    assert cleaned[-1][1] == "outsider"
    assert request("POST", f"{path}/accept", user="outsider").status_code == 401
    users[:] = [user for user in users if user["id"] != "alice"]
    calls.maintain_calls()
    assert request("GET", "/calls/community", user="carol").json() is None


def test_community_provider_presence_and_metadata_only_broadcasts(store, monkeypatch):
    request, clock, _, _ = store
    cursor = event_store.journal.watermark()
    call = create(request, "community", "community").json()
    path = f"/calls/{call['id']}"
    assert event_store.journal.read("alice", cursor)[1] == ["calls", "community_calls"]
    assert event_store.journal.read("outsider", cursor)[1] == ["community_calls"]
    request("POST", f"{path}/token")
    cursor = event_store.journal.watermark()
    request("POST", f"{path}/heartbeat")
    request("GET", "/calls/community")
    calls.maintain_calls()
    assert event_store.journal.watermark() == cursor
    request("POST", f"{path}/accept", user="outsider")
    for user in ("alice", "outsider"):
        assert event_store.journal.read(user, cursor)[1] == ["calls", "community_calls"]
    assert event_store.journal.read("carol", cursor)[1] == ["community_calls"]
    cursor = event_store.journal.watermark()
    clock["now"] += calls.LEASE_SECONDS + 1
    monkeypatch.setattr(calls.providers, "participant_present", lambda room, identity: True)
    calls.maintain_calls()
    assert request("GET", "/calls/community").json()["accepted_ids"] == ["alice", "outsider"]
    assert event_store.journal.watermark() == cursor
    clock["now"] += calls.LEASE_SECONDS + 1
    monkeypatch.setattr(calls.providers, "participant_present", lambda room, identity: identity == "alice")
    calls.maintain_calls()
    assert request("GET", "/calls/community").json()["accepted_ids"] == ["alice"]
    # The departing coordinator also needs the state change, not all app users.
    for user in ("alice", "outsider"):
        assert event_store.journal.read(user, cursor)[1] == ["calls", "community_calls"]
    assert event_store.journal.read("carol", cursor)[1] == ["community_calls"]
    cursor = event_store.journal.watermark()
    request("POST", f"{path}/leave")
    assert event_store.journal.read("alice", cursor)[1] == ["calls", "community_calls"]
    assert event_store.journal.read("carol", cursor)[1] == ["community_calls"]
    calls.maintain_calls()
    assert request("GET", "/calls/community").json() is None


def test_community_token_failure_does_not_enroll_joiner(store, monkeypatch):
    request, _, _, _ = store
    call = create(request, "community", "community").json()
    monkeypatch.delenv("LIVEKIT_API_SECRET")
    assert request("POST", f"/calls/{call['id']}/accept", user="outsider").status_code == 503
    assert request("GET", "/calls/community").json()["participant_ids"] == ["alice"]
