import time
import uuid
from datetime import datetime, timezone

import httpx
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwt

from app import call_providers as providers


@pytest.fixture
def incoming():
    return {
        "type": "incoming_call", "call_id": str(uuid.uuid4()), "caller_name": "Alice",
        "kind": "video", "expires_at": datetime.fromtimestamp(
            time.time() + 45, timezone.utc
        ).isoformat(),
    }


def test_fcm_android_is_high_priority_data_only(monkeypatch, incoming):
    sent = []
    monkeypatch.setattr(providers, "_firebase_app", lambda: object())
    monkeypatch.setattr(providers.messaging, "send", lambda message, **kwargs: sent.append(message))
    providers.send_push({"platform": "android", "kind": "fcm", "token": "fake"}, incoming)
    message = sent[0]
    assert message.data == incoming
    assert message.notification is None
    assert message.android.priority == "high"
    assert 0 < message.android.ttl.total_seconds() <= 45


def test_web_data_only_push_has_safe_configured_link(monkeypatch, incoming):
    sent = []
    monkeypatch.setenv("CALLS_PUBLIC_APP_URL", "https://travel.example/app?lang=en")
    monkeypatch.setattr(providers, "_firebase_app", lambda: object())
    monkeypatch.setattr(providers.messaging, "send", lambda message, **kwargs: sent.append(message))
    providers.send_push({"platform": "web", "kind": "fcm", "token": "fake"}, incoming)
    assert sent[0].notification is None
    assert sent[0].webpush.notification is None
    assert sent[0].webpush.fcm_options is None
    assert sent[0].webpush.data["link"] == (
        f'https://travel.example/app?lang=en&call_id={incoming["call_id"]}'
    )
    assert sent[0].data == incoming
    assert {key: sent[0].webpush.data[key] for key in incoming} == incoming
    monkeypatch.setenv("CALLS_PUBLIC_APP_URL", "javascript:alert(1)")
    with pytest.raises(providers.ProviderError):
        providers.send_push({"platform": "web", "kind": "fcm", "token": "fake"}, incoming)


def test_apns_pushkit_es256_headers_payload_and_cancellation_safety(monkeypatch, tmp_path, incoming):
    key = ec.generate_private_key(ec.SECP256R1())
    path = tmp_path / "test-key.p8"
    path.write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ))
    for name, value in {
        "APNS_KEY_FILE": str(path), "APNS_KEY_ID": "TESTKEY", "APNS_TEAM_ID": "TESTTEAM",
        "APNS_VOIP_TOPIC": "com.example.travel.voip", "APNS_ENVIRONMENT": "sandbox",
    }.items():
        monkeypatch.setenv(name, value)
    requests = []
    original_client = httpx.Client

    def respond(request):
        requests.append(request)
        return httpx.Response(200)

    monkeypatch.setattr(providers.httpx, "Client", lambda **kwargs: original_client(
        transport=httpx.MockTransport(respond)
    ))
    device = {"kind": "voip", "platform": "ios", "token": "a" * 64}
    providers.send_push(device, incoming)
    request = requests[0]
    assert request.url.host == "api.sandbox.push.apple.com"
    assert request.headers["apns-topic"] == "com.example.travel.voip"
    assert request.headers["apns-push-type"] == "voip"
    assert request.headers["apns-priority"] == "10"
    assert request.headers["apns-expiration"] == "0"
    token = request.headers["authorization"].split(" ")[1]
    public_key = key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    assert jwt.get_unverified_header(token)["kid"] == "TESTKEY"
    assert jwt.decode(token, public_key, algorithms=["ES256"])["iss"] == "TESTTEAM"
    import json
    assert json.loads(request.content) == {"aps": {"content-available": 1}, **incoming}
    providers.send_push(device, incoming)
    assert requests[1].headers["authorization"] == request.headers["authorization"]
    providers.send_push(device, {"type": "call_ended", "call_id": incoming["call_id"]})
    assert len(requests) == 2


def test_ios_fcm_only_sends_background_cancellation(monkeypatch, incoming):
    sent = []
    monkeypatch.setattr(providers, "_firebase_app", lambda: object())
    monkeypatch.setattr(providers.messaging, "send", lambda message, **kwargs: sent.append(message))
    device = {"kind": "fcm", "platform": "ios", "token": "fake"}
    providers.send_push(device, incoming)
    assert sent == []
    providers.send_push(device, {"type": "call_ended", "call_id": incoming["call_id"]})
    assert sent[0].apns.headers["apns-push-type"] == "background"
    assert sent[0].apns.payload.aps.content_available


def test_livekit_cleanup_uses_server_scoped_grants(monkeypatch):
    monkeypatch.setenv("LIVEKIT_URL", "wss://project.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", "test-key")
    monkeypatch.setenv("LIVEKIT_API_SECRET", "test-secret")
    requests = []

    def post(url, **kwargs):
        requests.append((url, kwargs))
        return httpx.Response(200, request=httpx.Request("POST", url))

    monkeypatch.setattr(providers.httpx, "post", post)
    providers.cleanup_room("room-uuid", "user-uuid")
    providers.cleanup_room("room-uuid")
    for (url, kwargs), grant in zip(requests, [
        {"room": "room-uuid", "roomAdmin": True}, {"roomCreate": True},
    ]):
        claims = jwt.decode(
            kwargs["headers"]["Authorization"].split(" ")[1], "test-secret",
            algorithms=["HS256"],
        )
        assert claims["video"] == grant
        assert url.startswith("https://project.livekit.cloud/twirp/livekit.RoomService/")
    assert requests[0][1]["json"] == {"room": "room-uuid", "identity": "user-uuid"}
    assert requests[1][1]["json"] == {"room": "room-uuid"}


@pytest.mark.parametrize("status,body,raises", [
    (404, {"code": "not_found"}, False),
    (404, {"code": "unknown"}, True),
    (500, {}, True),
])
def test_livekit_cleanup_failure_is_not_silently_ignored(monkeypatch, status, body, raises):
    monkeypatch.setenv("LIVEKIT_URL", "wss://project.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", "test-key")
    monkeypatch.setenv("LIVEKIT_API_SECRET", "test-secret")
    monkeypatch.setattr(providers.httpx, "post", lambda url, **kwargs: httpx.Response(
        status, json=body, request=httpx.Request("POST", url),
    ))
    if raises:
        with pytest.raises(providers.ProviderError):
            providers.cleanup_room("room", "identity")
    else:
        providers.cleanup_room("room", "identity")


def test_invalid_apns_signing_key_is_a_retryable_provider_error(monkeypatch, tmp_path, incoming):
    path = tmp_path / "invalid-test-key.p8"
    path.write_text("not-a-private-key", encoding="utf-8")
    for name, value in {
        "APNS_KEY_FILE": str(path), "APNS_KEY_ID": "TESTKEY", "APNS_TEAM_ID": "TESTTEAM",
        "APNS_VOIP_TOPIC": "com.example.travel.voip", "APNS_ENVIRONMENT": "sandbox",
    }.items():
        monkeypatch.setenv(name, value)
    with pytest.raises(providers.ProviderError, match="APNs delivery failed"):
        providers.send_push({"kind": "voip", "platform": "ios", "token": "a" * 64}, incoming)


def test_fcm_refresh_failure_is_retryable(monkeypatch, incoming):
    from google.auth.exceptions import RefreshError

    monkeypatch.setattr(providers, "_firebase_app", lambda: object())

    def send(*args, **kwargs):
        raise RefreshError("invalid test credentials")

    monkeypatch.setattr(providers.messaging, "send", send)
    with pytest.raises(providers.ProviderError, match="FCM delivery failed"):
        providers.send_push({"kind": "fcm", "platform": "android", "token": "fake"}, incoming)


@pytest.mark.parametrize("status,body,expected", [
    (200, {"identity": "user", "state": "ACTIVE"}, True),
    (200, {"identity": "user", "state": "JOINED"}, True),
    (200, {"identity": "user", "state": "DISCONNECTED"}, False),
    (200, {"identity": "user", "state": 2}, True),
    (200, {"identity": "user", "state": 3}, False),
    (404, {"code": "not_found"}, False),
    (200, {"identity": "different-user", "state": "ACTIVE"}, None),
    (200, {"identity": "user", "state": "UNKNOWN"}, None),
    (500, {}, None),
])
def test_livekit_presence_verifies_room_identity_and_provider_errors(monkeypatch, status, body, expected):
    monkeypatch.setenv("LIVEKIT_URL", "wss://project.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", "test-key")
    monkeypatch.setenv("LIVEKIT_API_SECRET", "test-secret")

    def post(url, **kwargs):
        assert url.endswith("/twirp/livekit.RoomService/GetParticipant")
        assert kwargs["json"] == {"room": "room", "identity": "user"}
        claims = jwt.decode(
            kwargs["headers"]["Authorization"].split(" ")[1],
            "test-secret", algorithms=["HS256"],
        )
        assert claims["video"] == {"room": "room", "roomAdmin": True}
        return httpx.Response(status, json=body, request=httpx.Request("POST", url))

    monkeypatch.setattr(providers.httpx, "post", post)
    if expected is None:
        with pytest.raises(providers.ProviderError):
            providers.participant_present("room", "user")
    else:
        assert providers.participant_present("room", "user") is expected
