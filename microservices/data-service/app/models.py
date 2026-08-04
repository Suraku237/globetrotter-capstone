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

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
DESTINATIONS_FILE = DATA_DIR / "destinations.json"
ITINERARIES_FILE = DATA_DIR / "itineraries.json"


class ItineraryCreate(BaseModel):
    title: str
    destination_id: str
    start_date: str
    end_date: str
    notes: Optional[str] = None


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


def load_itineraries() -> list:
    return _load(ITINERARIES_FILE)


def save_itineraries(itineraries: list) -> None:
    _save(ITINERARIES_FILE, itineraries)
