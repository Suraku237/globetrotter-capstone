"""Bounded cross-process invalidations on the existing shared local data volume."""

import json
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path

from .models import DATA_DIR

TOPICS = {
    "friends", "calls", "chat", "posts", "destinations", "itineraries",
    "profile", "recommendations", "stats",
}
HISTORY_LIMIT = 2048
READ_LIMIT = 128
SCHEMA = """
CREATE TABLE IF NOT EXISTS invalidations (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    audience TEXT,
    topics TEXT NOT NULL
)
"""


class EventJournal:
    def __init__(self, path: Path):
        self.path = path
        self._initialized = False
        self._lock = threading.Lock()

    @contextmanager
    def connection(self):
        connection = sqlite3.connect(self.path, timeout=5)
        try:
            with self._lock:
                if not self._initialized:
                    connection.execute("PRAGMA journal_mode=WAL")
                    connection.execute(SCHEMA)
                    connection.commit()
                    self._initialized = True
            with connection:
                yield connection
        finally:
            connection.close()

    def publish(self, topics, user_ids=None):
        topics = sorted(set(topics))
        if not topics or not set(topics) <= TOPICS:
            raise ValueError("Unknown or empty invalidation topics")
        audiences = [None] if user_ids is None else sorted(set(user_ids))
        if not audiences:
            return
        encoded = json.dumps(topics, separators=(",", ":"))
        with self.connection() as connection:
            connection.executemany(
                "INSERT INTO invalidations(audience, topics) VALUES (?, ?)",
                ((audience, encoded) for audience in audiences),
            )
            connection.execute(
                "DELETE FROM invalidations WHERE sequence <= "
                "(SELECT MAX(sequence) FROM invalidations) - ?",
                (HISTORY_LIMIT,),
            )

    def watermark(self) -> int:
        with self.connection() as connection:
            return connection.execute(
                "SELECT COALESCE(MAX(sequence), 0) FROM invalidations"
            ).fetchone()[0]

    def read(self, user_id: str, cursor: int) -> tuple[int, list[str], bool]:
        with self.connection() as connection:
            # One snapshot prevents retention racing between the gap check and read.
            connection.execute("BEGIN")
            oldest, latest = connection.execute(
                "SELECT COALESCE(MIN(sequence), 0), COALESCE(MAX(sequence), 0) "
                "FROM invalidations"
            ).fetchone()
            if cursor > latest or (oldest and cursor < oldest - 1):
                return latest, [], True
            rows = connection.execute(
                "SELECT sequence, topics FROM invalidations "
                "WHERE sequence > ? AND (audience IS NULL OR audience = ?) "
                "ORDER BY sequence LIMIT ?",
                (cursor, user_id, READ_LIMIT),
            ).fetchall()
        topics = sorted({topic for _, encoded in rows for topic in json.loads(encoded)})
        next_cursor = rows[-1][0] if len(rows) == READ_LIMIT else latest
        return next_cursor, topics, False


journal = EventJournal(DATA_DIR / "events.sqlite3")


def publish(topics, user_ids=None):
    journal.publish(topics, user_ids)
