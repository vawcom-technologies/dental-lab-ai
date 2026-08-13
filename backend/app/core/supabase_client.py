"""Supabase client helpers.

Uses the anon key for user-facing auth (signup / signin / password reset).
Uses the service-role key only when privileged server-side access is needed.

Clients are thread-local: FastAPI runs sync routes in a thread pool, and the
supabase/httpx sync client is not safe to share across threads. A process-wide
singleton produces intermittent ``Server disconnected`` 502s under concurrent
requests (e.g. appointment filter changes).
"""

from __future__ import annotations

import threading
import time
from collections.abc import Callable
from typing import TypeVar

from fastapi import HTTPException, status
from supabase import Client, create_client

from app.core.config import settings

_local = threading.local()
_T = TypeVar("_T")
_TRANSIENT = (
    "server disconnected",
    "connection reset",
    "connection aborted",
    "remote protocol",
    "server disconnected without sending a response",
)


def _require(value: str, name: str) -> str:
    if not value or not value.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Missing {name} — set it in backend/.env",
        )
    return value.strip()


def _make_client(key: str) -> Client:
    url = _require(settings.supabase_url, "SUPABASE_URL")
    return create_client(url, key)


def get_supabase() -> Client:
    client = getattr(_local, "anon", None)
    if client is None:
        key = _require(settings.supabase_anon_key, "SUPABASE_ANON_KEY")
        client = _make_client(key)
        _local.anon = client
    return client


def get_supabase_admin() -> Client:
    client = getattr(_local, "admin", None)
    if client is None:
        key = _require(settings.supabase_service_role_key, "SUPABASE_SERVICE_ROLE_KEY")
        client = _make_client(key)
        _local.admin = client
    return client


def is_transient_db_error(exc: BaseException) -> bool:
    msg = str(exc).lower()
    return any(token in msg for token in _TRANSIENT)


def reset_thread_clients() -> None:
    """Drop this thread's clients so the next call opens a fresh connection."""
    for name in ("anon", "admin"):
        if hasattr(_local, name):
            delattr(_local, name)


def run_db(fn: Callable[[], _T], *, retries: int = 2) -> _T:
    """Run a Supabase call, retrying transient disconnects on a fresh client."""
    last: Exception | None = None
    for attempt in range(retries + 1):
        try:
            return fn()
        except Exception as exc:
            last = exc
            if not is_transient_db_error(exc) or attempt >= retries:
                raise
            reset_thread_clients()
            time.sleep(0.05 * (attempt + 1))
    assert last is not None
    raise last
