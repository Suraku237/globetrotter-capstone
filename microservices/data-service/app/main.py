import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import assistant, destinations, itineraries, posts, recommendations, stats
from .models import DATA_DIR

app = FastAPI(title="GlobeTrotter Data Service", version="1.0.0")

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

app.include_router(assistant.router)
app.include_router(destinations.router)
app.include_router(itineraries.router)
app.include_router(posts.router)
app.include_router(recommendations.router)
app.include_router(stats.router)


@app.get("/health")
def health():
    return {"status": "ok"}
