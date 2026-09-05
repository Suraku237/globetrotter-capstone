"""
Targeted tests for the "auto-sign-in after super admin approval" flow.

Exercises auth.check_admin_request_status directly (bypasses the router)
against a temp users store, so we can watch a real registration go from
pending_admin_approval -> active without booting the whole service.
"""
import pytest
from fastapi import HTTPException

from app import auth
from app.models import PendingSessionRequest


@pytest.fixture
def user_store(tmp_path, monkeypatch):
    users: list = []

    def _load():
        return users

    def _save(new_users):
        # Mirror save_users' behavior of replacing the whole list.
        users.clear()
        users.extend(new_users)

    monkeypatch.setattr(auth, "load_users", _load)
    monkeypatch.setattr(auth, "save_users", _save)
    return users


def _register_pending_admin(users: list, user_id: str = "u-1") -> str:
    users.append(
        {
            "id": user_id,
            "email": "candidate@example.com",
            "full_name": "Candidate",
            "username": "candidate",
            "role": "admin",
            "hashed_password": "hash",
            "preferences": [],
            "created_at": "2026-01-01T00:00:00+00:00",
            "email_verified": True,
            "status": "pending_admin_approval",
            "admin_approval_token": "approval-token",
        }
    )
    return auth.create_pending_session_token(user_id)


def test_status_is_pending_before_super_admin_approves(user_store):
    token = _register_pending_admin(user_store)

    result = auth.check_admin_request_status(
        PendingSessionRequest(pending_session_token=token)
    )

    assert result["status"] == "pending"
    # No access token leaks while still pending.
    assert "access_token" not in result


def test_status_returns_access_token_after_super_admin_approves(user_store):
    token = _register_pending_admin(user_store)

    # The super admin flips the record to active — same effect as clicking
    # the approve link in the notification email.
    user_store[0]["status"] = "active"
    user_store[0].pop("admin_approval_token", None)

    result = auth.check_admin_request_status(
        PendingSessionRequest(pending_session_token=token)
    )

    assert result["status"] == "approved"
    assert result["role"] == "admin"
    assert result["user_id"] == "u-1"
    assert result["email"] == "candidate@example.com"
    assert isinstance(result["access_token"], str) and result["access_token"]


def test_status_returns_rejected_when_user_record_gone(user_store):
    token = _register_pending_admin(user_store)

    # reject_admin_request deletes the record outright.
    user_store.clear()

    result = auth.check_admin_request_status(
        PendingSessionRequest(pending_session_token=token)
    )

    assert result["status"] == "rejected"
    assert "access_token" not in result


def test_status_rejects_a_fabricated_pending_session_token(user_store):
    _register_pending_admin(user_store)

    with pytest.raises(HTTPException) as excinfo:
        auth.check_admin_request_status(
            PendingSessionRequest(pending_session_token="not-a-real-token")
        )

    assert excinfo.value.status_code == 401


def test_pending_session_token_cannot_masquerade_as_access_token(user_store):
    # Defense-in-depth: the pending-session token is signed with the same
    # SECRET_KEY as real access tokens, so security.get_current_user must
    # refuse it based on the "purpose" claim rather than the signature.
    from jose import jwt
    from app.models import ALGORITHM, SECRET_KEY

    token = _register_pending_admin(user_store)
    claims = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert claims["purpose"] == "admin_approval_status"

    from app.security import get_current_user

    with pytest.raises(HTTPException) as excinfo:
        get_current_user(token=token)
    assert excinfo.value.status_code == 401
