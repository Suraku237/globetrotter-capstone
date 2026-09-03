import json
import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from pydantic import BaseModel


def load_environment() -> None:
    env_files = [
        Path(__file__).resolve().parent / ".env",
        Path(__file__).resolve().parent.parent / ".env",
    ]
    for env_file in env_files:
        if env_file.exists():
            load_dotenv(env_file, override=False)


load_environment()

# Same secret as auth-service — needed here only to verify the JWTs
# auth-service issues (see security.py). This service never mints tokens.
SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError(
        "JWT_SECRET is not set. It must match the value used by auth-service. "
        "Create a .env file in data-service/ with JWT_SECRET=..., or set it as an env var."
    )
ALGORITHM = "HS256"

# Optional — unlike JWT_SECRET, a missing key here shouldn't take down the
# whole service (destinations/itineraries/posts don't need it). Read at
# request time via get_gemini_api_key() below rather than caching here, so
# that:
#   1. If the container was started before .env was populated and someone
#      later injects the env var (e.g. `docker compose up -d` after editing
#      .env), the next request picks it up without rebuilding the image.
#   2. A key pasted with surrounding whitespace/quotes doesn't silently
#      fail as a bad request to Google (which would surface as an opaque
#      502 rather than the clean 503 users can actually act on).
def get_gemini_api_key() -> Optional[str]:
    raw = os.getenv("GEMINI_API_KEY") or ""
    key = raw.strip().strip('"').strip("'")
    return key or None


# Kept for backwards compatibility with any callers doing
# `from .models import GEMINI_API_KEY` — but prefer get_gemini_api_key()
# in new code so the request-time lookup above is used.
GEMINI_API_KEY = get_gemini_api_key()

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
DESTINATIONS_FILE = DATA_DIR / "destinations.json"
ITINERARIES_FILE = DATA_DIR / "itineraries.json"
POSTS_FILE = DATA_DIR / "posts.json"
CONVERSATIONS_FILE = DATA_DIR / "conversations.json"


class ItineraryCreate(BaseModel):
    title: str
    destination_id: str
    start_date: str
    end_date: str
    notes: Optional[str] = None


class CommentCreate(BaseModel):
    text: str


class DestinationUpdate(BaseModel):
    name: Optional[str] = None
    region: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[list] = None
    lat: Optional[float] = None
    lng: Optional[float] = None


def _load(path: Path):
    if not path.exists():
        return []
    with open(path, "r") as f:
        return json.load(f)


def _save(path: Path, data) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def load_users() -> list:
    return _load(USERS_FILE)


def load_destinations() -> list:
    data = _load(DESTINATIONS_FILE)
    if isinstance(data, dict):
        return data.get("destinations", [])
    return data


def save_destinations(destinations: list) -> None:
    # Preserve the {"destinations": [...]} wrapper if that's how the file
    # is currently shaped; fall back to a plain list otherwise.
    existing = _load(DESTINATIONS_FILE)
    if isinstance(existing, dict):
        existing["destinations"] = destinations
        _save(DESTINATIONS_FILE, existing)
    else:
        _save(DESTINATIONS_FILE, destinations)


def load_itineraries() -> list:
    return _load(ITINERARIES_FILE)


def save_itineraries(itineraries: list) -> None:
    _save(ITINERARIES_FILE, itineraries)


def load_posts() -> list:
    return _load(POSTS_FILE)


def save_posts(posts: list) -> None:
    _save(POSTS_FILE, posts)


def load_conversations() -> dict:
    # Keyed by user id -> list of {"role", "text", "created_at"} turns, so
    # the assistant can pick back up with a user across sessions/devices
    # instead of starting from nothing every time the chat screen opens.
    if not CONVERSATIONS_FILE.exists():
        return {}
    with open(CONVERSATIONS_FILE, "r") as f:
        return json.load(f)


def save_conversations(conversations: dict) -> None:
    _save(CONVERSATIONS_FILE, conversations)
