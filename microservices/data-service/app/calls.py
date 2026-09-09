"""Leased call signalling. All store access shares social's single-worker lock."""

import hashlib
import logging
import re
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from pydantic import BaseModel, Field, model_validator

from . import call_providers as providers
from . import social
from .models import DATA_DIR
from .security import get_current_user
from .event_store import publish

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/social", tags=["calls"])
CALLS_FILE = DATA_DIR / "calls.json"
DEVICES_FILE = DATA_DIR / "call_devices.json"
RING_SECONDS = 45
LEASE_SECONDS = 55
_device_delivery_lock = threading.Lock()
_maintenance_lock = threading.Lock()
PUBLIC_FIELDS = (
    "id", "kind", "target_type", "target_id", "title", "caller_id", "caller_name",
    "caller_avatar_url", "status", "created_at", "expires_at", "participant_ids",
    "accepted_ids", "ended_reason",
)


class CallCreate(BaseModel):
    kind: Literal["voice", "video"]
    target_type: Literal["direct", "group", "community"]
    target_id: str = Field(min_length=1, max_length=128)

    @model_validator(mode="after")
    def validate_target(self):
        if self.target_type == "community" and self.target_id != "community":
            raise ValueError("Community calls must target the shared community room")
        return self


class CallDevice(BaseModel):
    token: str = Field(min_length=1, max_length=4096)
    platform: Literal["android", "ios", "web"]
    kind: Literal["fcm", "voip"]

    @model_validator(mode="after")
    def validate_device(self):
        if self.token != self.token.strip() or any(c.isspace() for c in self.token):
            raise ValueError("Invalid device token")
        if self.kind == "voip":
            if self.platform != "ios" or not re.fullmatch(r"[a-fA-F0-9]{64}", self.token):
                raise ValueError("VoIP requires an iOS APNs device token")
            self.token = self.token.lower()
        return self


def _iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat()


def _public(call: dict, viewer_id: str) -> dict:
    result = {key: call[key] for key in PUBLIC_FIELDS}
    if call["target_type"] == "direct":
        other_id = call["target_id"] if viewer_id == call["caller_id"] else call["caller_id"]
        other = social._user_by_id(social.load_users(), other_id)
        result["title"] = other.get("full_name", "")
    return result


def _atomic_save(path: Path, records: list) -> None:
    # Atomic replace prevents a process crash from leaving half-written call JSON.
    staging = path.with_suffix(".writing")
    social._save(staging, records)
    for attempt in range(4):
        try:
            staging.replace(path)
            return
        except PermissionError as exc:
            # Windows indexers/antivirus briefly hold newly written JSON files.
            if getattr(exc, "winerror", None) not in {5, 32} or attempt == 3:
                raise
            time.sleep(0.01 * 2**attempt)


def _save(calls: list) -> None:
    previous = {call["id"]: call for call in social._load_list(CALLS_FILE)}
    _atomic_save(CALLS_FILE, calls)
    changed_users = set()
    community_changed = False
    for call in calls:
        old = previous.get(call["id"])
        # Lease renewal and provider bookkeeping aren't visible state changes.
        if old is None or any(
            old.get(key) != call.get(key) for key in (*PUBLIC_FIELDS, "_departed")
        ):
            changed_users.update(call["participant_ids"])
            if old:
                changed_users.update(old["participant_ids"])
            if call["target_type"] == "community":
                community_changed = True
    if changed_users:
        # Persist signalling invalidations before the independent FCM/APNs worker
        # touches a provider. Slow/offline pushes must never postpone ringing.
        publish(["calls"], changed_users)
    if community_changed:
        # Discovery banners are public metadata, never incoming-call invitations.
        publish(["community_calls"])


def _save_devices(devices: list) -> None:
    _atomic_save(DEVICES_FILE, devices)


def _eligible(call: dict) -> set[str]:
    users = {user["id"] for user in social.load_users()}
    if call["target_type"] == "community":
        return users
    if call["target_type"] == "group":
        group = next(
            (item for item in social._load_list(social.GROUPS_FILE)
             if item["id"] == call["target_id"]), None,
        )
        return users.intersection(group["member_ids"]) if group else set()
    friendship = social._friendship_between(
        social._load_list(social.FRIENDSHIPS_FILE),
        call["caller_id"], call["target_id"],
    )
    if not friendship or friendship["status"] != "accepted":
        return set()
    return users.intersection(call["participant_ids"])


def _event(call: dict, user_ids, incoming: bool = False) -> None:
    if call["target_type"] == "community":
        return
    data = {"type": "incoming_call" if incoming else "call_ended", "call_id": call["id"]}
    if incoming:
        data.update(
            caller_name=call["caller_name"], kind=call["kind"], expires_at=call["expires_at"],
        )
    # Resolve token ownership at delivery time, not when an invite is queued.
    call["_events"].append({
        "id": str(uuid.uuid4()), "users": list(user_ids), "data": data, "sent": [],
        "until": call["_ring_until"] if incoming else time.time() + 120,
    })


def _remove(call: dict, user_id: str) -> None:
    if user_id in call["accepted_ids"]:
        call["accepted_ids"].remove(user_id)
    if call["target_type"] == "community" and user_id in call["participant_ids"]:
        call["participant_ids"].remove(user_id)
    call["_leases"].pop(user_id, None)
    if user_id not in call["_departed"]:
        call["_departed"].append(user_id)
    if user_id in call["_issued"] and user_id not in call["_cleanup"]:
        call["_cleanup"].append(user_id)


def _end(call: dict, reason: str) -> None:
    if call["status"] == "ended":
        return
    call["status"] = "ended"
    call["ended_reason"] = reason
    for user_id in list(call["accepted_ids"]):
        _remove(call, user_id)
    call["_delete_room"] = bool(call["_issued"])
    _event(call, call["participant_ids"])


def _sweep(calls: list, now: float) -> None:
    for call in calls:
        if call["status"] == "ended":
            continue
        eligible = _eligible(call)
        removed = set(call["participant_ids"]) - eligible - set(call["_departed"])
        for user_id in removed:
            _remove(call, user_id)
            _event(call, [user_id])
        if call["target_type"] == "direct" and removed:
            _end(call, "membership_changed")
            continue
        if call["status"] == "ringing" and call["caller_id"] not in call["accepted_ids"]:
            _end(call, "caller_left")
            continue
        if call["status"] == "ringing" and now >= call["_ring_until"]:
            _end(call, "no_answer")
            continue
        expired = [
            user_id for user_id, until in call["_leases"].items()
            if until <= now and not (call["status"] == "active" and user_id in call["_issued"])
        ]
        for user_id in expired:
            _remove(call, user_id)
            _event(call, [user_id])
        if expired and (call["target_type"] == "direct" or not call["accepted_ids"]):
            _end(call, "connection_lost")
        elif not call["accepted_ids"]:
            _end(call, "last_participant_left")
        elif (
            call["target_type"] != "community"
            and call["status"] == "active" and now >= call["_ring_until"]
        ):
            pending = set(call["participant_ids"]) - set(call["accepted_ids"]) - set(call["_departed"])
            for user_id in pending:
                _remove(call, user_id)
            if pending:
                _event(call, pending)


def _load_current() -> list:
    calls = social._load_list(CALLS_FILE)
    _sweep(calls, time.time())
    _save(calls)
    return calls


def _get(calls: list, call_id: str, user_id: str) -> dict:
    call = next((item for item in calls if item["id"] == call_id), None)
    if call is None or (
        call["target_type"] != "community" and user_id not in call["participant_ids"]
    ):
        raise HTTPException(404, "Call not found")
    if user_id not in _eligible(call):
        raise HTTPException(403, "Call membership is no longer valid")
    return call


def _busy(calls: list, user_id: str, exclude: str | None = None) -> bool:
    return any(
        call["id"] != exclude and call["status"] != "ended"
        and user_id in (
            call["accepted_ids"] if call["target_type"] == "community" else call["participant_ids"]
        )
        and user_id not in call["_departed"]
        for call in calls
    )


@router.post("/call-devices")
def register_device(payload: CallDevice, current_user: dict = Depends(get_current_user)):
    with _device_delivery_lock, social._social_lock:
        devices = social._load_list(DEVICES_FILE)
        key = hashlib.sha256(f"{payload.kind}:{payload.token}".encode()).hexdigest()
        # The same installation can change account. Registration is a single
        # ownership transfer, and an old owner's DELETE cannot remove the new one.
        devices = [device for device in devices if device["key"] != key]
        if sum(device["user_id"] == current_user["id"] for device in devices) >= 20:
            raise HTTPException(409, "Too many registered call devices")
        devices.append({
            **payload.model_dump(), "key": key, "user_id": current_user["id"],
            "generation": str(uuid.uuid4()),
        })
        _save_devices(devices)
    return {"ok": True}


@router.delete("/call-devices")
def unregister_device(payload: CallDevice, current_user: dict = Depends(get_current_user)):
    with _device_delivery_lock, social._social_lock:
        devices = social._load_list(DEVICES_FILE)
        devices = [
            device for device in devices
            if not (
                device["user_id"] == current_user["id"]
                and device["token"] == payload.token and device["kind"] == payload.kind
            )
        ]
        _save_devices(devices)
    return {"ok": True}


@router.post("/calls")
def create_call(
    payload: CallCreate,
    current_user: dict = Depends(get_current_user),
    idempotency_key: str | None = Header(default=None, max_length=128),
):
    with social._social_lock:
        calls = _load_current()
        my_id = current_user["id"]
        users = social.load_users()
        if payload.target_type == "direct":
            if payload.target_id == my_id:
                raise HTTPException(400, "Cannot call yourself")
            other = social._user_by_id(users, payload.target_id)
            social._require_friendship(
                social._load_list(social.FRIENDSHIPS_FILE), my_id, payload.target_id
            )
            participants = [my_id, payload.target_id]
            title = other.get("full_name", "")
        elif payload.target_type == "group":
            group = social._group_for_member(
                social._load_list(social.GROUPS_FILE), payload.target_id, my_id
            )
            participants = list(dict.fromkeys(
                member for member in group["member_ids"]
                if any(user["id"] == member for user in users)
            ))
            title = group["name"]
            if len(participants) < 2:
                raise HTTPException(400, "At least two group members are required")
        else:
            social._user_by_id(users, my_id)
            participants = [my_id]
            title = "Community"
        for call in calls:
            same = all(call[key] == value for key, value in payload.model_dump().items())
            if call["caller_id"] != my_id:
                continue
            if idempotency_key and call.get("_idempotency_key") == idempotency_key:
                if not same:
                    raise HTTPException(409, "Idempotency key belongs to a different call")
                return _public(call, my_id)
            if same and call["status"] != "ended" and my_id not in call["_departed"]:
                return _public(call, my_id)
        community = payload.target_type == "community"
        if community and any(
            call["target_type"] == "community" and call["status"] != "ended" for call in calls
        ):
            raise HTTPException(409, "A community call is already active. Join the active call instead.")
        try:
            providers.livekit_config()
        except providers.ProviderError as exc:
            raise HTTPException(503, str(exc)) from exc
        if _busy(calls, my_id):
            raise HTTPException(409, "You are already in a call")
        busy = [member for member in participants if member != my_id and _busy(calls, member)]
        if not community and len(busy) == len(participants) - 1:
            raise HTTPException(409, "The selected participants are busy")
        now = time.time()
        call = {
            "id": str(uuid.uuid4()), **payload.model_dump(), "title": title,
            "caller_id": my_id, "caller_name": current_user.get("full_name", ""),
            "caller_avatar_url": current_user.get("avatar_url"),
            "status": "active" if community else "ringing",
            "created_at": _iso(now),
            "expires_at": _iso(now + (LEASE_SECONDS if community else RING_SECONDS)),
            "participant_ids": participants, "accepted_ids": [my_id], "ended_reason": None,
            "_room": str(uuid.uuid4()), "_ring_until": now + RING_SECONDS,
            "_leases": {my_id: now + LEASE_SECONDS}, "_departed": busy,
            "_issued": [], "_cleanup": [], "_delete_room": False, "_events": [],
            "_idempotency_key": idempotency_key,
        }
        _event(call, [member for member in participants if member != my_id and member not in busy], True)
        calls.append(call)
        _save(calls)
        return _public(call, my_id)


@router.get("/calls/incoming")
def incoming_calls(current_user: dict = Depends(get_current_user)):
    with social._social_lock:
        calls = _load_current()
        user_id = current_user["id"]
        return [
            _public(call, user_id) for call in calls
            if call["target_type"] != "community"
            and call["status"] != "ended" and time.time() < call["_ring_until"]
            and user_id in call["participant_ids"] and user_id in _eligible(call)
            and user_id not in call["accepted_ids"] and user_id not in call["_departed"]
        ]


@router.get("/calls/community")
def community_call(response: Response, current_user: dict = Depends(get_current_user)):
    response.headers["Cache-Control"] = "no-store"
    with social._social_lock:
        call = next((
            call for call in _load_current()
            if call["target_type"] == "community" and call["status"] == "active"
        ), None)
        return _public(call, current_user["id"]) if call else None


@router.get("/calls/{call_id}")
def get_call(call_id: str, current_user: dict = Depends(get_current_user)):
    with social._social_lock:
        return _public(_get(_load_current(), call_id, current_user["id"]), current_user["id"])


def _join(call_id: str, user: dict, accept: bool) -> dict:
    with social._social_lock:
        calls = _load_current()
        user_id = user["id"]
        call = _get(calls, call_id, user_id)
        community = call["target_type"] == "community"
        if call["status"] == "ended" or (not community and user_id in call["_departed"]):
            raise HTTPException(409, "Call has ended or you have already left")
        if user_id not in call["accepted_ids"]:
            if not accept:
                raise HTTPException(403, "Accept the call before requesting a token")
            if community and user_id in call["_cleanup"]:
                raise HTTPException(409, "Your previous connection is still being cleaned up. Retry joining shortly.")
            if not community and time.time() >= call["_ring_until"]:
                raise HTTPException(409, "Call invitation has expired")
            if _busy(calls, user_id, call_id):
                raise HTTPException(409, "You are already in a call")
        try:
            url, token = providers.join_token(call, user)
        except providers.ProviderError as exc:
            raise HTTPException(503, str(exc)) from exc
        if user_id not in call["accepted_ids"]:
            if community:
                if user_id in call["_departed"]:
                    call["_departed"].remove(user_id)
                call["participant_ids"].append(user_id)
            call["accepted_ids"].append(user_id)
            call["status"] = "active"
            # Cancel ringing on all this user's other installations.
            _event(call, [user_id])
        call["_leases"][user_id] = time.time() + LEASE_SECONDS
        if user_id not in call["_issued"]:
            call["_issued"].append(user_id)
        _save(calls)
        return {"call": _public(call, user_id), "url": url, "token": token}


@router.post("/calls/{call_id}/token")
def call_token(call_id: str, current_user: dict = Depends(get_current_user)):
    return _join(call_id, current_user, False)


@router.post("/calls/{call_id}/accept")
def accept_call(call_id: str, current_user: dict = Depends(get_current_user)):
    return _join(call_id, current_user, True)


def _depart(call_id: str, user: dict, decline: bool) -> dict:
    with social._social_lock:
        calls = _load_current()
        user_id = user["id"]
        call = _get(calls, call_id, user_id)
        if call["target_type"] == "community" and user_id not in call["accepted_ids"]:
            raise HTTPException(403, "Join the community call before changing participation")
        if call["status"] == "ended" or user_id in call["_departed"]:
            return _public(call, user_id)
        if decline and user_id in call["accepted_ids"]:
            raise HTTPException(409, "Use leave for an accepted call")
        _remove(call, user_id)
        _event(call, [user_id])
        if call["target_type"] == "direct":
            _end(call, "declined" if decline else (
                "cancelled" if call["status"] == "ringing" else "participant_left"
            ))
        elif not call["accepted_ids"]:
            _end(call, "cancelled" if call["status"] == "ringing" else "last_participant_left")
        elif call["status"] == "ringing" and set(call["participant_ids"]) <= (
            set(call["accepted_ids"]) | set(call["_departed"])
        ):
            _end(call, "declined")
        _save(calls)
        return _public(call, user_id)


@router.post("/calls/{call_id}/decline")
def decline_call(call_id: str, current_user: dict = Depends(get_current_user)):
    return _depart(call_id, current_user, True)


@router.post("/calls/{call_id}/leave")
def leave_call(call_id: str, current_user: dict = Depends(get_current_user)):
    return _depart(call_id, current_user, False)


@router.post("/calls/{call_id}/heartbeat")
def heartbeat(call_id: str, current_user: dict = Depends(get_current_user)):
    with social._social_lock:
        calls = _load_current()
        call = _get(calls, call_id, current_user["id"])
        if call["target_type"] == "community" and current_user["id"] not in call["accepted_ids"]:
            raise HTTPException(403, "Join the community call before sending heartbeats")
        if call["status"] == "ended":
            return _public(call, current_user["id"])
        if current_user["id"] not in call["accepted_ids"]:
            raise HTTPException(409, "You are not participating in this call")
        call["_leases"][current_user["id"]] = time.time() + LEASE_SECONDS
        _save(calls)
        return _public(call, current_user["id"])


def _find(calls: list, call_id: str) -> dict:
    return next(call for call in calls if call["id"] == call_id)


def _deliver_event(call_id: str, event_id: str) -> None:
    with social._social_lock:
        generations = [device["generation"] for device in social._load_list(DEVICES_FILE)]
    pending = False
    for generation in generations:
        # Only device registration/logout waits for provider I/O. Signalling and
        # heartbeats must never wait behind slow FCM/APNs/LiveKit connections.
        with _device_delivery_lock:
            with social._social_lock:
                calls = social._load_list(CALLS_FILE)
                call = _find(calls, call_id)
                event = next((item for item in call["_events"] if item["id"] == event_id), None)
                if event is None:
                    return
                incoming = event["data"]["type"] == "incoming_call"
                if time.time() >= event["until"] or (incoming and call["status"] == "ended"):
                    call["_events"].remove(event)
                    _save(calls)
                    return
                device = next((
                    item for item in social._load_list(DEVICES_FILE)
                    if item["generation"] == generation
                ), None)
                if device is None:
                    continue
                user_id = device["user_id"]
                if (
                    user_id not in event["users"] or generation in event["sent"]
                    or (incoming and (
                        user_id not in _eligible(call) or user_id in call["accepted_ids"]
                        or user_id in call["_departed"]
                    ))
                ):
                    continue
                data = dict(event["data"])
            invalid = False
            try:
                providers.send_push(device, data)
            except providers.InvalidDevice:
                invalid = True
                logger.info("Removed invalid call push registration")
            except providers.ProviderError:
                pending = True
                logger.warning("Call push delivery pending for call %s", call_id)
                continue
            with social._social_lock:
                if invalid:
                    _save_devices([
                        item for item in social._load_list(DEVICES_FILE)
                        if item["generation"] != generation
                    ])
                calls = social._load_list(CALLS_FILE)
                call = _find(calls, call_id)
                event = next((item for item in call["_events"] if item["id"] == event_id), None)
                if event is not None:
                    event["sent"].append(generation)
                _save(calls)
    if not pending:
        with social._social_lock:
            calls = social._load_list(CALLS_FILE)
            call = _find(calls, call_id)
            call["_events"] = [event for event in call["_events"] if event["id"] != event_id]
            _save(calls)


def _check_expired_participants() -> None:
    with social._social_lock:
        candidates = [
            (call["id"], call["_room"], user_id, until)
            for call in _load_current() if call["status"] == "active"
            for user_id, until in call["_leases"].items()
            if until <= time.time() and user_id in call["_issued"]
        ]
    for call_id, room, user_id, deadline in candidates:
        with social._social_lock:
            call = _find(social._load_list(CALLS_FILE), call_id)
            if call["status"] != "active" or call["_leases"].get(user_id) != deadline:
                continue
        try:
            present = providers.participant_present(room, user_id)
        except providers.ProviderError:
            # A mobile OS may pause Dart timers while native WebRTC stays live.
            # A control-plane outage is not evidence that media disconnected.
            logger.warning("LiveKit presence check pending for call %s", call_id)
            continue
        with social._social_lock:
            calls = _load_current()
            call = _find(calls, call_id)
            # A heartbeat, leave or membership change can race the network query.
            if call["status"] != "active" or call["_leases"].get(user_id) != deadline:
                continue
            if present:
                call["_leases"][user_id] = time.time() + LEASE_SECONDS
            else:
                _remove(call, user_id)
                _event(call, [user_id])
                if call["target_type"] == "direct" or not call["accepted_ids"]:
                    _end(call, "connection_lost")
            _save(calls)


def maintain_calls() -> None:
    """Expire leases without client traffic and drain persisted provider work."""
    with _maintenance_lock:
        _check_expired_participants()
        with social._social_lock:
            snapshot = [
                call for call in _load_current()
                if call["_cleanup"] or call["_delete_room"] or call["_events"]
            ]
        for previous in snapshot:
            call_id = previous["id"]
            for identity in previous["_cleanup"]:
                try:
                    providers.cleanup_room(previous["_room"], identity)
                except providers.ProviderError:
                    logger.warning("LiveKit participant cleanup pending for call %s", call_id)
                else:
                    with social._social_lock:
                        calls = social._load_list(CALLS_FILE)
                        call = _find(calls, call_id)
                        call["_cleanup"].remove(identity)
                        _save(calls)
            with social._social_lock:
                call = _find(social._load_list(CALLS_FILE), call_id)
                delete = call["_delete_room"] and not call["_cleanup"]
            if delete:
                try:
                    providers.cleanup_room(previous["_room"])
                except providers.ProviderError:
                    logger.warning("LiveKit room cleanup pending for call %s", call_id)
                else:
                    with social._social_lock:
                        calls = social._load_list(CALLS_FILE)
                        _find(calls, call_id)["_delete_room"] = False
                        _save(calls)
            with social._social_lock:
                events = list(_find(social._load_list(CALLS_FILE), call_id)["_events"])
            for event in events:
                _deliver_event(call_id, event["id"])


def maintenance_loop(stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            maintain_calls()
        except (OSError, ValueError):
            logger.exception("Call maintenance failed; will retry")
        stop.wait(5)


def lease_loop(stop: threading.Event) -> None:
    # Provider retries must not postpone unjoined/no-answer expiry.
    while not stop.wait(5):
        try:
            with social._social_lock:
                _load_current()
        except (OSError, ValueError):
            logger.exception("Call lease expiry failed; will retry")
