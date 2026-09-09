import json
import sqlite3

from app import events, models, profile


def test_profile_save_publishes_private_owner_and_friend_invalidations(tmp_path, monkeypatch):
    monkeypatch.setattr(models, "USERS_FILE", tmp_path / "users.json")
    monkeypatch.setattr(events, "DATA_DIR", tmp_path)
    users = [
        {"id": name, "email": f"{name}@example.test", "full_name": name.title(), "username": name}
        for name in ("alice", "bob", "carol")
    ]
    models._save(models.USERS_FILE, users)
    models._save(tmp_path / "friendships.json", [
        {"requester_id": "alice", "recipient_id": "bob", "status": "accepted"},
    ])
    result = profile.update_me(models.UpdateProfileRequest(full_name="New Alice"), users[0])
    assert result["full_name"] == "New Alice"
    connection = sqlite3.connect(tmp_path / "events.sqlite3")
    try:
        rows = connection.execute("SELECT audience, topics FROM invalidations").fetchall()
    finally:
        connection.close()
    assert set((audience, tuple(json.loads(topics))) for audience, topics in rows) == {
        ("alice", ("profile", "recommendations")), ("alice", ("friends",)), ("bob", ("friends",)),
    }
