"""Dental Lab AI — FastAPI application entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, health, admin
from app.core.debug_middleware import DebugRequestMiddleware, configure_api_logging


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_api_logging()
    yield


app = FastAPI(
    title="Dental Lab AI API",
    version="0.3.0",
    description="Elite Dent API — Supabase authentication",
    lifespan=lifespan,
)

# Outer middleware runs first on the way in — CORS should stay outermost.
app.add_middleware(DebugRequestMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(admin.router, prefix="/api/admin", tags=["admin"])

try:
    from app.api import ai_poc

    app.include_router(ai_poc.router, prefix="/api/ai", tags=["ai-poc"])
except Exception as exc:  # pragma: no cover
    print(f"AI POC routes not loaded: {exc}")
