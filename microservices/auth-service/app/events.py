"""Write-only side of data-service's shared SQLite invalidation protocol."""

import json
import sqlite3

from .models import DATA_DIR, _load

# Keep the schema/retention compatible with data-service/app/event_store.py.
# Services intentionally remain independently buildable (no cross-app imports).
HISTORY_LIMIT = 2048


def _publish(topics, user_ids=None):
    audiences = [None] if user_ids is None else sorted(set(user_ids))
    if not audiences:
        return
    connection = sqlite3.connect(DATA_DIR / "events.sqlite3", timeout=5)
    try:
        connection.execute("PRAGMA journal_mode=WAL")
        with connection:
            connection.execute("""
                CREATE TABLE IF NOT EXISTS invalidations (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    audience TEXT,
                    topics TEXT NOT NULL
                )
            """)
            connection.executemany(
                "INSERT INTO invalidations(audience, topics) VALUES (?, ?)",
                ((audience, json.dumps(sorted(set(topics)))) for audience in audiences),
            )
            connection.execute(
                "DELETE FROM invalidations WHERE sequence <= "
                "(SELECT MAX(sequence) FROM invalidations) - ?",
                (HISTORY_LIMIT,),
            )
    finally:
        connection.close()


def users_changed(previous: list, current: list):
    old = {user["id"]: user for user in previous}
    new = {user["id"]: user for user in current}
    if old.keys() != new.keys():
        _publish(["stats"])
    fields = ("full_name", "username", "avatar_url", "role", "preferences", "status")
    changed = {
        user_id for user_id in old.keys() | new.keys()
        if user_id not in old or user_id not in new
        or any(old[user_id].get(key) != new[user_id].get(key) for key in fields)
    }
    if not changed:
        return
    _publish(["profile", "recommendations"], changed)
    audience = set(changed)
    for friendship in _load(DATA_DIR / "friendships.json"):
        pair = {friendship["requester_id"], friendship["recipient_id"]}
        if pair & changed:
            audience.update(pair)
    for group in _load(DATA_DIR / "chat_groups.json"):
        if set(group["member_ids"]) & changed:
            audience.update(group["member_ids"])
    _publish(["friends"], audience)
