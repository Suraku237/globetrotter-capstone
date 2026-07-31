from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os
from . import auth, destinations, itineraries, recommendations, stats

app = FastAPI(title="GlobeTrotter API", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve static files (images) - make sure the directory exists
images_dir = "/app/data/images"
if os.path.exists(images_dir):
    app.mount("/images", StaticFiles(directory=images_dir), name="images")
    print(f"Serving images from {images_dir}")
else:
    print(f"WARNING: Images directory not found at {images_dir}")

# Include routers
app.include_router(auth.router)
app.include_router(destinations.router)
app.include_router(itineraries.router)
app.include_router(recommendations.router)
app.include_router(stats.router)

@app.get("/")
def root():
    return {"message": "GlobeTrotter API is running"}