"""Supabase client helpers.

Uses the anon key for user-facing auth (signup / signin / password reset).
Uses the service-role key only when privileged server-side access is needed.
"""

from functools import lru_cache

from fastapi import HTTPException, status
from supabase import Client, create_client

from app.core.config import settings


def _require(value: str, name: str) -> str:
    if not value or not value.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Missing {name} — set it in backend/.env",
        )
    return value.strip()


@lru_cache
def get_supabase() -> Client:
    url = _require(settings.supabase_url, "SUPABASE_URL")
    key = _require(settings.supabase_anon_key, "SUPABASE_ANON_KEY")
    return create_client(url, key)


@lru_cache
def get_supabase_admin() -> Client:
    url = _require(settings.supabase_url, "SUPABASE_URL")
    key = _require(settings.supabase_service_role_key, "SUPABASE_SERVICE_ROLE_KEY")
    return create_client(url, key)
