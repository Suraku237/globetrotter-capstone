import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import assistant, chat, destinations, itineraries, posts, recommendations, social, stats
from .models import DATA_DIR, get_gemini_api_key

logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # A visible line in the container logs makes it obvious whether env
    # actually made it into the process — the #1 cause of the AI assistant
    # 503 has been "container was started before .env was populated".
    # Uses the current lifespan-events API instead of the deprecated
    # @app.on_event("startup") hook that was warned on in the CI logs.
    key = get_gemini_api_key()
    if key:
        logger.info(
            "AI assistant configured (GEMINI_API_KEY present, %d chars).",
            len(key),
        )
    else:
        logger.warning(
            "AI assistant NOT configured — GEMINI_API_KEY is missing/empty. "
            "Set it in microservices/.env, then recreate the data-service "
            "container so the new value takes effect."
        )
    yield
    # No shutdown work needed today — file writes are synchronous and
    # everything else uses per-request httpx clients.


app = FastAPI(
    title="GlobeTrotter Data Service",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Created eagerly (rather than mounted conditionally) so uploads that land
# here after startup — avatars, post photos, suggested-destination photos —
# are always served. A conditional mount would miss them: StaticFiles is
# attached once at boot, so if the directory didn't exist yet at that
# moment, files written into it later would 404 forever.
images_dir = DATA_DIR / "images"
images_dir.mkdir(parents=True, exist_ok=True)
app.mount("/images", StaticFiles(directory=str(images_dir)), name="images")

# Same reasoning as /images above — created eagerly so voice messages
# uploaded after startup are actually reachable, not 404s.
audio_dir = DATA_DIR / "audio"
audio_dir.mkdir(parents=True, exist_ok=True)
app.mount("/audio", StaticFiles(directory=str(audio_dir)), name="audio")

app.include_router(assistant.router)
app.include_router(chat.router)
app.include_router(social.router)
app.include_router(destinations.router)
app.include_router(itineraries.router)
app.include_router(posts.router)
app.include_router(recommendations.router)
app.include_router(stats.router)


@app.get("/health")
def health():
    # Reports whether the assistant is usable, so a browser hit to
    # /api/health (or a curl from your laptop) diagnoses the 503 without
    # needing shell access to the server.
    return {
        "status": "ok",
        "assistant_configured": bool(get_gemini_api_key()),
    }