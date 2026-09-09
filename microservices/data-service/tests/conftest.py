import pytest

from app import event_store, stats


@pytest.fixture(autouse=True)
def isolated_invalidations(tmp_path, monkeypatch):
    monkeypatch.setattr(event_store, "journal", event_store.EventJournal(tmp_path / "events.sqlite3"))
    monkeypatch.setattr(stats, "STATS_FILE", tmp_path / "stats.json")
