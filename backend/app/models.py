import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext


def load_environment() -> None:
    env_files = [
        Path(__file__).resolve().parent / ".env",
        Path(__file__).resolve().parent.parent / ".env",
    ]
    for env_file in env_files:
        if env_file.exists():
            load_dotenv(env_file, override=False)


load_environment()

SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError(
        "JWT_SECRET is not set. Create a .env file in backend/ with "
        "JWT_SECRET=<output of `openssl rand -hex 32`>, or set it as an env var."
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
DESTINATIONS_FILE = DATA_DIR / "destinations.json"
ITINERARIES_FILE = DATA_DIR / "itineraries.json"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    role: Optional[str] = "user"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: str
    email: str
    full_name: str


class ItineraryCreate(BaseModel):
    title: str
    destination_id: str
    start_date: str
    end_date: str
    notes: Optional[str] = None


def _load(path: Path) -> list:
    if not path.exists():
        return []
    with open(path, "r") as f:
        return json.load(f)


def _save(path: Path, data: list) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def seed_destinations() -> None:
    sample = [
        {
            "id": str(uuid.uuid4()),
            "name": "Yaoundé",
            "region": "Centre",
            "tags": ["city", "culture", "history"],
            "image_url": "https://images.unsplash.com/photo-1518548419970-58e3b4079ab2?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Douala",
            "region": "Littoral",
            "tags": ["city", "nightlife"],
            "image_url": "https://images.unsplash.com/photo-1449824913935-59a10b8d2000?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Limbe",
            "region": "Southwest",
            "tags": ["beach", "relax"],
            "image_url": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Kribi",
            "region": "South",
            "tags": ["beach", "relax"],
            "image_url": "https://images.unsplash.com/photo-1519046904884-53103b34b206?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Foumban",
            "region": "West",
            "tags": ["culture", "history"],
            "image_url": "https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Dschang",
            "region": "West",
            "tags": ["mountain", "relax"],
            "image_url": "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Buea",
            "region": "Southwest",
            "tags": ["mountain", "hiking", "adventure"],
            "image_url": "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Bamenda",
            "region": "Northwest",
            "tags": ["mountain", "hiking"],
            "image_url": "https://images.unsplash.com/photo-1483728642387-6c3bdd6c93e5?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Rhumsiki",
            "region": "Far North",
            "tags": ["adventure", "mountain"],
            "image_url": "https://images.unsplash.com/photo-1509316785289-025f5b846b35?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Waza National Park",
            "region": "Far North",
            "tags": ["wildlife", "safari"],
            "image_url": "https://images.unsplash.com/photo-1516426122078-c23e76319801?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Ebolowa",
            "region": "South",
            "tags": ["wildlife", "safari", "culture"],
            "image_url": "https://images.unsplash.com/photo-1547471080-7cc2caa01a7e?auto=format&fit=crop&w=1200&q=80",
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Bafoussam",
            "region": "West",
            "tags": ["culture", "city"],
            "image_url": "https://images.unsplash.com/photo-1524492412937-b28074a5d7da?auto=format&fit=crop&w=1200&q=80",
        },
    ]
    # Only seed if the file doesn't exist yet or is genuinely empty.
    # Never overwrite existing data — that data might be a manual edit,
    # a git-deployed update, or real content added after launch.
    if DESTINATIONS_FILE.exists():
        current = _load(DESTINATIONS_FILE)
        if current:
            return
    _save(DESTINATIONS_FILE, sample)


def seed_users() -> None:
    users = _load(USERS_FILE)
    existing_emails = {u.get("email") for u in users if u.get("email")}

    sample_users = [
        {
            "id": str(uuid.uuid4()),
            "email": "admin@example.com",
            "full_name": "Admin User",
            "role": "admin",
            "hashed_password": pwd_context.hash("admin123"),
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": str(uuid.uuid4()),
            "email": "worker@example.com",
            "full_name": "Worker User",
            "role": "worker",
            "hashed_password": pwd_context.hash("worker123"),
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": str(uuid.uuid4()),
            "email": "user@example.com",
            "full_name": "Regular User",
            "role": "user",
            "hashed_password": pwd_context.hash("user123"),
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
    ]

    added = False
    for sample_user in sample_users:
        if sample_user["email"] not in existing_emails:
            users.append(sample_user)
            existing_emails.add(sample_user["email"])
            added = True

    if added or not USERS_FILE.exists():
        _save(USERS_FILE, users)


seed_destinations()
seed_users()


def load_users() -> list:
    return _load(USERS_FILE)


def save_users(users: list) -> None:
    _save(USERS_FILE, users)


def load_destinations() -> list:
    return _load(DESTINATIONS_FILE)


def load_itineraries() -> list:
    return _load(ITINERARIES_FILE)


def save_itineraries(itineraries: list) -> None:
    _save(ITINERARIES_FILE, itineraries)