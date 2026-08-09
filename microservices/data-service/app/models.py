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
# whole service (destinations/itineraries/posts don't need it). assistant.py
# checks for this itself and returns a clear error only when /assistant/chat
# is actually called without it configured.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
DESTINATIONS_FILE = DATA_DIR / "destinations.json"
ITINERARIES_FILE = DATA_DIR / "itineraries.json"
POSTS_FILE = DATA_DIR / "posts.json"


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
