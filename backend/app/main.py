"""Dental Lab AI — FastAPI application entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, health, admin, chat, users
from app.core.debug_middleware import DebugRequestMiddleware, configure_api_logging
from app.openapi_docs import attach_custom_openapi


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_api_logging()
    yield


app = FastAPI(
    title="Dental Lab AI API",
    version="0.3.0",
    description="Elite Dent API — Supabase authentication + real-time chat",
    lifespan=lifespan,
)

# Document /ws/chat in Swagger (/docs) via custom OpenAPI injection
attach_custom_openapi(app)

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
app.include_router(users.router, prefix="/api", tags=["Users & Contacts"])
# Chat REST: /api/conversations...
app.include_router(chat.router, prefix="/api", tags=["chat"])
# Chat WebSocket: /ws/chat?token=<access_token>
app.include_router(chat.ws_router, tags=["chat"])

try:
    from app.api import ai_poc

    app.include_router(ai_poc.router, prefix="/api/ai", tags=["ai-poc"])
except Exception as exc:  # pragma: no cover
    print(f"AI POC routes not loaded: {exc}")
