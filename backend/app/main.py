"""
GlobeTrotter Travel Assistant - Phase 1 Monolith
FastAPI + JSON file storage + JWT auth
"""
import json
import os
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
from jose import JWTError, jwt


def load_environment() -> None:
    env_files = [
        Path(__file__).resolve().parent / ".env",
        Path(__file__).resolve().parent.parent / ".env",
    ]
    for env_file in env_files:
        if env_file.exists():
            load_dotenv(env_file, override=False)


load_environment()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError(
        "JWT_SECRET is not set. Create a .env file in backend/ with "
        "JWT_SECRET=<output of `openssl rand -hex 32`>, or set it as an env var."
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 1 day

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)
USERS_FILE = DATA_DIR / "users.json"
DESTINATIONS_FILE = DATA_DIR / "destinations.json"
ITINERARIES_FILE = DATA_DIR / "itineraries.json"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

app = FastAPI(title="GlobeTrotter API", version="0.1.0")

# Allow Flutter web / desktop / mobile to call the API during dev.
# Tighten allow_origins to your real domain(s) once deployed.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Tiny JSON "database" helpers
# ---------------------------------------------------------------------------
def _load(path: Path) -> list:
    if not path.exists():
        return []
    with open(path, "r") as f:
        return json.load(f)


def _save(path: Path, data: list) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def seed_destinations():
    sample = [
        {"id": str(uuid.uuid4()), "name": "Yaoundé", "region": "Centre", "tags": ["city", "culture", "museum"], "image_url": "https://images.unsplash.com/photo-1518548419970-58e3b4079ab2?auto=format&fit=crop&w=1200&q=80"},
        {"id": str(uuid.uuid4()), "name": "Mfoundi", "region": "Centre", "tags": ["city", "market", "business"], "image_url": "https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=1200&q=80"},
        {"id": str(uuid.uuid4()), "name": "Mbankomo", "region": "Centre", "tags": ["nature", "relax", "lake"], "image_url": "https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1200&q=80"},
        {"id": str(uuid.uuid4()), "name": "Nkolbisson", "region": "Centre", "tags": ["local", "food", "community"], "image_url": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=1200&q=80"},
    ]
    if DESTINATIONS_FILE.exists():
        current = _load(DESTINATIONS_FILE)
        if current and all(d.get("name") in {"Yaoundé", "Mfoundi", "Mbankomo", "Nkolbisson"} for d in current):
            return
    _save(DESTINATIONS_FILE, sample)


def seed_users():
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

# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------
def normalize_role(role: Optional[str]) -> str:
    if role in {"admin", "worker", "user"}:
        return role
    return "user"


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    users = _load(USERS_FILE)
    user = next((u for u in users if u["id"] == user_id), None)
    if user is None:
        raise credentials_exception
    return user


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.post("/register", status_code=201)
def register(payload: RegisterRequest):
    users = _load(USERS_FILE)
    if any(u["email"] == payload.email for u in users):
        raise HTTPException(status_code=400, detail="Email already registered")

    user = {
        "id": str(uuid.uuid4()),
        "email": payload.email,
        "full_name": payload.full_name,
        "role": normalize_role(payload.role),
        "hashed_password": pwd_context.hash(payload.password),
        "preferences": [],
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    users.append(user)
    _save(USERS_FILE, users)
    return {
        "id": user["id"],
        "email": user["email"],
        "full_name": user["full_name"],
        "role": user.get("role", "user"),
    }


@app.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest):
    users = _load(USERS_FILE)
    user = next((u for u in users if u["email"] == payload.email), None)
    if not user or not pwd_context.verify(payload.password, user["hashed_password"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    token = create_access_token({"sub": user["id"], "role": user.get("role", "user")})
    return TokenResponse(
        access_token=token,
        role=user.get("role", "user"),
        user_id=user["id"],
        email=user["email"],
        full_name=user["full_name"],
    )


@app.get("/destinations")
def get_destinations(q: Optional[str] = None):
    destinations = _load(DESTINATIONS_FILE)
    if q:
        q_lower = q.lower()
        destinations = [
            d for d in destinations
            if q_lower in d["name"].lower() or q_lower in d["region"].lower()
            or any(q_lower in tag for tag in d["tags"])
        ]
    return destinations


@app.get("/recommendations")
def get_recommendations(current_user: dict = Depends(get_current_user)):
    # Phase 1: naive recommendation — return destinations matching stored preferences,
    # falling back to the first 3 destinations. Replace with real logic in Phase 2.
    destinations = _load(DESTINATIONS_FILE)
    prefs = current_user.get("preferences", [])
    if prefs:
        matches = [d for d in destinations if any(tag in prefs for tag in d["tags"])]
        if matches:
            return matches
    return destinations[:3]


@app.post("/itineraries", status_code=201)
def create_itinerary(payload: ItineraryCreate, current_user: dict = Depends(get_current_user)):
    itineraries = _load(ITINERARIES_FILE)
    itinerary = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "title": payload.title,
        "destination_id": payload.destination_id,
        "start_date": payload.start_date,
        "end_date": payload.end_date,
        "notes": payload.notes,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    itineraries.append(itinerary)
    _save(ITINERARIES_FILE, itineraries)
    return itinerary


@app.get("/itineraries")
def get_itineraries(current_user: dict = Depends(get_current_user)):
    itineraries = _load(ITINERARIES_FILE)
    return [i for i in itineraries if i["user_id"] == current_user["id"]]


@app.get("/health")
def health():
    return {"status": "ok"}