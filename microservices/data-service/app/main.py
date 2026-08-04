import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import destinations, itineraries, recommendations, stats
from .models import DATA_DIR

app = FastAPI(title="GlobeTrotter Data Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

images_dir = DATA_DIR / "images"
if images_dir.exists():
    app.mount("/images", StaticFiles(directory=str(images_dir)), name="images")
    print(f"Serving images from {images_dir}")
else:
    print(f"WARNING: Images directory not found at {images_dir}")

app.include_router(destinations.router)
app.include_router(itineraries.router)
app.include_router(recommendations.router)
app.include_router(stats.router)


@app.get("/health")
def health():
    return {"status": "ok"}
