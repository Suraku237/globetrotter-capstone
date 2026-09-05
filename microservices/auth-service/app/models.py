import json
import os
import re
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
        "JWT_SECRET is not set. Create a .env file in auth-service/ with "
        "JWT_SECRET=<output of `openssl rand -hex 32`>, or set it as an env var."
    )
ALGORITHM = "HS256"
# A week — logging in should stick across app restarts instead of forcing
# a fresh sign-in every day.
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7
# 24 hours — a fresh pending-approval registrant may leave the app open
# and come back later, but shouldn't hold a valid poll token forever.
PENDING_SESSION_EXPIRE_MINUTES = 60 * 24

# Optional — unlike JWT_SECRET, a missing value here shouldn't take down the
# whole service (login/most of the app works fine without email). Endpoints
# that actually need to send mail check for this themselves and return a
# clear error if it's not configured, rather than crashing at startup.
BREVO_SMTP_LOGIN = os.getenv("BREVO_SMTP_LOGIN")
BREVO_SMTP_PASSWORD = os.getenv("BREVO_SMTP_PASSWORD")
BREVO_SENDER_EMAIL = os.getenv("BREVO_SENDER_EMAIL")
# Where "new admin wants to sign up" notifications go, and who has to click
# the approve/reject link in them.
SUPER_ADMIN_EMAIL = os.getenv("SUPER_ADMIN_EMAIL")
# Used to build the approve/reject links embedded in that notification
# email — needs to be the public URL the backend is actually reachable at.
PUBLIC_API_BASE_URL = os.getenv(
    "PUBLIC_API_BASE_URL", "https://fasttravel-web.duckdns.org/api"
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
# Signups from users/workers that haven't confirmed their code yet — kept
# out of users.json entirely so an unverified (possibly fake) email never
# has real, storable credentials sitting in the database.
PENDING_REGISTRATIONS_FILE = DATA_DIR / "pending_registrations.json"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

USERNAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_.]{2,23}$")


def normalize_username(value: str) -> str:
    return value.strip().lower()


def is_valid_username(value: str) -> bool:
    return bool(USERNAME_PATTERN.fullmatch(normalize_username(value)))


def unique_generated_username(value: str, used: set[str]) -> str:
    """Generate a stable, valid username for accounts created before handles."""
    base = re.sub(r"[^a-z0-9_.]+", "_", value.lower()).strip("_.")
    if not base or not base[0].isalnum():
        base = "traveler"
    base = base[:24]
    if len(base) < 3:
        base = f"{base}user"[:24]

    candidate = base
    suffix = 2
    while candidate in used:
        suffix_text = str(suffix)
        candidate = f"{base[:24 - len(suffix_text)]}{suffix_text}"
        suffix += 1
    return candidate


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    username: str
    role: Optional[str] = "user"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str


# Sent by the register-screen poller while an admin/worker signup is waiting
# for the super admin to click the approval link — proves "I'm the session
# that just registered this user_id" without holding the plaintext password.
class PendingSessionRequest(BaseModel):
    pending_session_token: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: str
    email: str
    full_name: str
    username: str = ""
    avatar_url: Optional[str] = None


class UpdateProfileRequest(BaseModel):
    full_name: str


def _load(path: Path) -> list:
    if not path.exists():
        return []
    with open(path, "r") as f:
        return json.load(f)


def _save(path: Path, data: list) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def seed_users() -> None:
    users = _load(USERS_FILE)
    existing_emails = {u.get("email") for u in users if u.get("email")}

    sample_users = [
        {
            "id": str(uuid.uuid4()),
            "email": "admin@example.com",
            "full_name": "Admin User",
            "username": "admin_user",
            "role": "admin",
            "hashed_password": pwd_context.hash("admin123"),
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": str(uuid.uuid4()),
            "email": "worker@example.com",
            "full_name": "Worker User",
            "username": "worker_user",
            "role": "worker",
            "hashed_password": pwd_context.hash("worker123"),
            "preferences": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": str(uuid.uuid4()),
            "email": "user@example.com",
            "full_name": "Regular User",
            "username": "regular_user",
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


def ensure_usernames() -> None:
    """Backfill unique handles for existing accounts before social features use them."""
    users = _load(USERS_FILE)
    used: set[str] = set()
    changed = False
    for user in users:
        current = normalize_username(str(user.get("username") or ""))
        if not is_valid_username(current) or current in used:
            source = str(user.get("email") or user.get("full_name") or "traveler")
            current = unique_generated_username(source.split("@", 1)[0], used)
            user["username"] = current
            changed = True
        elif user.get("username") != current:
            user["username"] = current
            changed = True
        used.add(current)
    if changed:
        _save(USERS_FILE, users)


seed_users()
ensure_usernames()


def load_users() -> list:
    return _load(USERS_FILE)


def save_users(users: list) -> None:
    _save(USERS_FILE, users)


def load_pending_registrations() -> list:
    return _load(PENDING_REGISTRATIONS_FILE)


def save_pending_registrations(pending: list) -> None:
    _save(PENDING_REGISTRATIONS_FILE, pending)
