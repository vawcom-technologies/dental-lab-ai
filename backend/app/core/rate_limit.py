"""Tiny sliding-window rate limit for the public auth endpoints.

ponytail: per-process memory — fine on one Railway instance; move to Redis
(or Supabase's own auth limits) if the API runs on several instances.
"""

from __future__ import annotations

import time
from collections import deque

from fastapi import HTTPException, Request, status

_hits: dict[str, deque[float]] = {}


def client_ip(request: Request) -> str:
    """Caller's IP; behind Railway's proxy the first X-Forwarded-For entry."""
    fwd = request.headers.get("x-forwarded-for", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else "-"


def check(key: str, *, limit: int, window: float) -> None:
    """Allow [limit] calls per [window] seconds for [key]; 429 past that."""
    now = time.monotonic()
    q = _hits.setdefault(key, deque())
    while q and q[0] <= now - window:
        q.popleft()
    if len(q) >= limit:
        retry = int(q[0] + window - now) + 1
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many attempts. Please wait a moment and try again.",
            headers={"Retry-After": str(retry)},
        )
    q.append(now)
    if len(_hits) > 10_000:  # forget idle keys
        for k in [k for k, v in _hits.items() if not v or v[-1] <= now - 3600]:
            _hits.pop(k, None)


def reset() -> None:
    _hits.clear()


def guard(request: Request, action: str, email: str = "", *, per_ip: int, per_email: int, window: float) -> None:
    """Limit both the caller's IP and the targeted email address."""
    check(f"{action}:ip:{client_ip(request)}", limit=per_ip, window=window)
    if email:
        check(f"{action}:email:{email}", limit=per_email, window=window)
