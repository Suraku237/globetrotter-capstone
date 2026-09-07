"""Server-only LiveKit Cloud, FCM and APNs transports."""

import os
import threading
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import firebase_admin
import httpx
from firebase_admin import credentials, exceptions, messaging
from google.auth.exceptions import GoogleAuthError
from jose import jwt
from jose.exceptions import JWSError

TOKEN_SECONDS = 45
_apns_lock = threading.Lock()
_apns_cache: tuple[tuple, str, float] | None = None


class ProviderError(RuntimeError):
    """Retryable configuration or provider failure (never contains credentials)."""


class InvalidDevice(ProviderError):
    """The provider has permanently rejected this registration."""


def livekit_config() -> tuple[str, str, str]:
    url = os.getenv("LIVEKIT_URL", "").strip().rstrip("/")
    key = os.getenv("LIVEKIT_API_KEY", "").strip()
    secret = os.getenv("LIVEKIT_API_SECRET", "").strip()
    parsed = urlsplit(url)
    if (
        parsed.scheme != "wss" or not parsed.hostname or parsed.username
        or parsed.password or parsed.query or parsed.fragment or parsed.path
        or not key or not secret
    ):
        raise ProviderError("LiveKit Cloud is not configured")
    return url, key, secret


def join_token(call: dict, user: dict) -> tuple[str, str]:
    url, key, secret = livekit_config()
    now = int(time.time())
    token = jwt.encode(
        {
            "iss": key,
            "sub": user["id"],
            "name": user.get("full_name", ""),
            "iat": now,
            "nbf": now,
            "exp": now + TOKEN_SECONDS,
            "video": {
                "room": call["_room"],
                "roomJoin": True,
                "canPublish": True,
                "canSubscribe": True,
                "canPublishData": False,
                "canUpdateOwnMetadata": False,
                "canPublishSources": (
                    ["microphone"] if call["kind"] == "voice"
                    else ["microphone", "camera"]
                ),
            },
        },
        secret,
        algorithm="HS256",
    )
    return url, token


def cleanup_room(room: str, identity: str | None = None) -> None:
    url, key, secret = livekit_config()
    now = int(time.time())
    grant = {"room": room, "roomAdmin": True} if identity else {"roomCreate": True}
    token = jwt.encode(
        {"iss": key, "nbf": now, "exp": now + 30, "video": grant},
        secret, algorithm="HS256",
    )
    method = "RemoveParticipant" if identity else "DeleteRoom"
    body = {"room": room, "identity": identity} if identity else {"room": room}
    try:
        response = httpx.post(
            f"https://{urlsplit(url).netloc}/twirp/livekit.RoomService/{method}",
            json=body, headers={"Authorization": f"Bearer {token}"}, timeout=5,
        )
        # An absent participant/room is already in the desired state.
        if response.status_code == 404 and response.json().get("code") == "not_found":
            return
        response.raise_for_status()
    except (httpx.HTTPError, ValueError) as exc:
        raise ProviderError("LiveKit cleanup failed") from exc


def participant_present(room: str, identity: str) -> bool:
    url, key, secret = livekit_config()
    now = int(time.time())
    token = jwt.encode(
        {
            "iss": key, "nbf": now, "exp": now + 30,
            "video": {"room": room, "roomAdmin": True},
        },
        secret, algorithm="HS256",
    )
    try:
        response = httpx.post(
            f"https://{urlsplit(url).netloc}/twirp/livekit.RoomService/GetParticipant",
            json={"room": room, "identity": identity},
            headers={"Authorization": f"Bearer {token}"}, timeout=5,
        )
        if response.status_code == 404 and response.json().get("code") == "not_found":
            return False
        response.raise_for_status()
        participant = response.json()
        if participant.get("identity") != identity:
            raise ProviderError("LiveKit returned an unexpected participant")
        state = participant.get("state", "JOINING")
        if state not in {"JOINING", "JOINED", "ACTIVE", "DISCONNECTED", 0, 1, 2, 3}:
            raise ProviderError("LiveKit returned an unknown participant state")
        return state not in {"DISCONNECTED", 3}
    except (httpx.HTTPError, ValueError) as exc:
        raise ProviderError("LiveKit presence check failed") from exc


def _firebase_app():
    try:
        return firebase_admin.get_app("calls")
    except ValueError:
        path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")
        if not path:
            raise ProviderError("FCM credentials are not configured") from None
        try:
            return firebase_admin.initialize_app(
                credentials.Certificate(path), {"httpTimeout": 5}, name="calls"
            )
        except (ValueError, OSError) as exc:
            raise ProviderError("FCM credentials could not be loaded") from exc


def _web_link(call_id: str) -> str:
    value = os.getenv("CALLS_PUBLIC_APP_URL", "").strip()
    url = urlsplit(value)
    if (
        url.scheme != "https" or not url.hostname or url.username or url.password
        or url.fragment
    ):
        raise ProviderError("CALLS_PUBLIC_APP_URL must be a public HTTPS app URL")
    query = [(key, val) for key, val in parse_qsl(url.query) if key != "call_id"]
    return urlunsplit(url._replace(query=urlencode([*query, ("call_id", call_id)])))


def _remaining(data: dict) -> int:
    if data["type"] != "incoming_call":
        return 60
    return max(0, int(datetime.fromisoformat(data["expires_at"]).timestamp() - time.time()))


def _apns_authorization(key_id: str, team_id: str, key_file: str) -> str:
    global _apns_cache
    with _apns_lock:
        path = Path(key_file)
        config = (key_id, team_id, key_file, path.stat().st_mtime_ns)
        now = time.time()
        # APNs rejects excessive provider-token rotation; tokens are valid 1 hour.
        if _apns_cache and _apns_cache[0] == config and 0 <= now - _apns_cache[2] < 3000:
            return _apns_cache[1]
        token = jwt.encode(
            {"iss": team_id, "iat": int(now)}, path.read_text(encoding="utf-8"),
            algorithm="ES256", headers={"kid": key_id},
        )
        _apns_cache = (config, token, now)
        return token


def _send_fcm(device: dict, data: dict) -> None:
    from datetime import timedelta

    ttl = _remaining(data)
    if ttl == 0:
        return
    incoming = data["type"] == "incoming_call"
    platform = device["platform"]
    android = None
    webpush = None
    apns = None
    if platform == "android":
        android = messaging.AndroidConfig(priority="high", ttl=timedelta(seconds=ttl))
    elif platform == "web":
        # Only the service worker may display after checking expiry/logout state.
        webpush = messaging.WebpushConfig(
            headers={"Urgency": "high", "TTL": str(ttl)},
            data={**data, "link": _web_link(data["call_id"])} if incoming else None,
        )
    else:
        # Cancellation is ordinary background data, never a second VoIP push.
        apns = messaging.APNSConfig(
            headers={"apns-push-type": "background", "apns-priority": "5"},
            payload=messaging.APNSPayload(messaging.Aps(content_available=True)),
        )
    try:
        messaging.send(
            messaging.Message(
                token=device["token"], data=data, android=android,
                webpush=webpush, apns=apns,
            ),
            app=_firebase_app(),
        )
    except (messaging.UnregisteredError, messaging.SenderIdMismatchError) as exc:
        raise InvalidDevice("FCM registration is no longer valid") from exc
    except (exceptions.FirebaseError, GoogleAuthError, ValueError) as exc:
        raise ProviderError("FCM delivery failed") from exc


def _send_voip(device: dict, data: dict) -> None:
    if _remaining(data) == 0:
        return
    key_id = os.getenv("APNS_KEY_ID", "").strip()
    team_id = os.getenv("APNS_TEAM_ID", "").strip()
    topic = os.getenv("APNS_VOIP_TOPIC", "").strip()
    key_file = os.getenv("APNS_KEY_FILE", "").strip()
    environment = os.getenv("APNS_ENVIRONMENT", "production").strip()
    if not all((key_id, team_id, topic, key_file)) or not topic.endswith(".voip"):
        raise ProviderError("APNs VoIP is not configured")
    if environment not in {"production", "sandbox"}:
        raise ProviderError("APNS_ENVIRONMENT must be production or sandbox")
    try:
        token = _apns_authorization(key_id, team_id, key_file)
        host = "api.sandbox.push.apple.com" if environment == "sandbox" else "api.push.apple.com"
        with httpx.Client(http2=True, timeout=5) as client:
            response = client.post(
                f"https://{host}/3/device/{device['token']}",
                headers={
                    "authorization": f"bearer {token}",
                    "apns-topic": topic,
                    "apns-push-type": "voip",
                    "apns-priority": "10",
                    "apns-expiration": "0",
                    "apns-id": data["call_id"],
                },
                json={"aps": {"content-available": 1}, **data},
            )
        if response.status_code == 410:
            raise InvalidDevice("APNs registration is no longer valid")
        if response.status_code == 400 and response.json().get("reason") in {
            "BadDeviceToken", "DeviceTokenNotForTopic",
        }:
            raise InvalidDevice("APNs registration is not valid for this topic")
        response.raise_for_status()
    except (httpx.HTTPError, OSError, ValueError, JWSError) as exc:
        raise ProviderError("APNs delivery failed") from exc


def send_push(device: dict, data: dict) -> None:
    if device["kind"] == "voip":
        if data["type"] == "incoming_call":
            _send_voip(device, data)
    elif device["platform"] != "ios" or data["type"] == "call_ended":
        _send_fcm(device, data)
