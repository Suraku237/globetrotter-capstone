from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .auth import router as auth_router
from .destinations import router as destinations_router
from .itineraries import router as itineraries_router
from .recommendations import router as recommendations_router


def create_app() -> FastAPI:
    app = FastAPI(title="GlobeTrotter API", version="0.1.0")

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth_router)
    app.include_router(destinations_router)
    app.include_router(recommendations_router)
    app.include_router(itineraries_router)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    return app


app = create_app()
