from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from .auth import router as auth_router
from .destinations import router as destinations_router
from .itineraries import router as itineraries_router
from .recommendations import router as recommendations_router
from .stats import router as stats_router


def create_app() -> FastAPI:
    app = FastAPI(title="GlobeTrotter API", version="0.1.0")

    # 1. CORS Middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # 2. 👇 FIXED: The correct path based on your docker-compose.yml mount
    # You mapped ./data to /app/data, so the images are at /app/data/images/destinations
    images_directory = "/app/data/images/destinations"
    
    # Safety check (optional, but good for debugging in logs)
    if not os.path.exists(images_directory):
        print(f"⚠️ WARNING: Image directory not found at {images_directory}. Check your docker-compose mount.")
    else:
        # Note: We are mounting to "/images/destinations" to match your JSON paths
        app.mount(
            "/images/destinations", 
            StaticFiles(directory=images_directory), 
            name="images"
        )
        print(f"✅ Serving images from: {images_directory}")

    # 3. Include all your routers
    app.include_router(auth_router)
    app.include_router(destinations_router)
    app.include_router(recommendations_router)
    app.include_router(itineraries_router)
    app.include_router(stats_router)

    # 4. Health check
    @app.get("/health")
    def health():
        return {"status": "ok"}

    return app


app = create_app()