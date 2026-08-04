"""
Lightweight, self-hosted analytics counters.

Why this exists alongside Google Analytics:
Google Analytics (GA4) is excellent at deep behavioral analytics (bounce rate,
geography, session duration, etc.) but its numbers are only reachable through
the GA4 Data API, which requires server-side OAuth credentials and isn't
something a static HTML page can query directly or safely.

For the three specific numbers this project wants on its own dashboard —
visitors, registered users, and downloads — we track them ourselves here.
GA4 still runs in parallel on the site for the deeper analytics Google
provides; this endpoint is just the source of truth for the dashboard page.
"""

import json
from pathlib import Path
from threading import Lock

from fastapi import APIRouter, HTTPException

from .models import DATA_DIR, load_users

router = APIRouter(prefix="/stats", tags=["stats"])

STATS_FILE = DATA_DIR / "stats.json"
_lock = Lock()

DEFAULT_STATS = {"visitors": 0, "downloads": {"mobile": 0, "desktop": 0}}


def _load_stats() -> dict:
    if not STATS_FILE.exists():
        return dict(DEFAULT_STATS)
    with open(STATS_FILE, "r") as f:
        data = json.load(f)
    data.setdefault("visitors", 0)
    data.setdefault("downloads", {"mobile": 0, "desktop": 0})
    data["downloads"].setdefault("mobile", 0)
    data["downloads"].setdefault("desktop", 0)
    return data


def _save_stats(data: dict) -> None:
    with open(STATS_FILE, "w") as f:
        json.dump(data, f, indent=2)


@router.get("")
def get_stats():
    """Returns visitors, live user count, and download totals for the dashboard."""
    with _lock:
        data = _load_stats()

    users_count = len(load_users())
    downloads_total = data["downloads"]["mobile"] + data["downloads"]["desktop"]

    return {
        "visitors": data["visitors"],
        "users": users_count,
        "downloads": {
            "mobile": data["downloads"]["mobile"],
            "desktop": data["downloads"]["desktop"],
            "total": downloads_total,
        },
    }


@router.post("/visit")
def track_visit():
    """Call once per page load on the public site to count a visitor."""
    with _lock:
        data = _load_stats()
        data["visitors"] += 1
        _save_stats(data)
    return {"ok": True}


@router.post("/download/{platform}")
def track_download(platform: str):
    """Call when a download button is clicked. platform is 'mobile' or 'desktop'."""
    if platform not in ("mobile", "desktop"):
        raise HTTPException(status_code=400, detail="platform must be 'mobile' or 'desktop'")

    with _lock:
        data = _load_stats()
        data["downloads"][platform] += 1
        _save_stats(data)
    return {"ok": True}
