"""Dental Lab AI — FastAPI application entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, health


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield


app = FastAPI(
    title="Dental Lab AI API",
    version="0.3.0",
    description="Elite Dent API — Supabase authentication",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])

try:
    from app.api import ai_poc

    app.include_router(ai_poc.router, prefix="/api/ai", tags=["ai-poc"])
except Exception as exc:  # pragma: no cover
    print(f"AI POC routes not loaded: {exc}")
