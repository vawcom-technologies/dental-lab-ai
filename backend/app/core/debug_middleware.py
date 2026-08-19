"""Request/response debug logging for every API call.

Never logs response bodies, Authorization headers, or query strings that may
contain JWTs — those are PHI / credential material.
"""

from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger("app.api")


def _safe_path(request: Request) -> str:
    path = request.url.path
    # JWTs arrive as ?token= on the chat WebSocket; never echo query strings.
    return path


class DebugRequestMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        # BaseHTTPMiddleware can break WebSocket upgrades — skip WS paths
        if request.url.path.startswith("/ws/"):
            return await call_next(request)

        request_id = uuid.uuid4().hex[:8]
        method = request.method
        path = _safe_path(request)
        client = request.client.host if request.client else "-"
        auth = "yes" if request.headers.get("authorization") else "no"

        logger.debug(
            "[%s] → %s %s client=%s auth=%s",
            request_id,
            method,
            path,
            client,
            auth,
        )

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed_ms = (time.perf_counter() - started) * 1000
            logger.exception(
                "[%s] crashed %s %s after %.1fms",
                request_id,
                method,
                path,
                elapsed_ms,
            )
            raise

        elapsed_ms = (time.perf_counter() - started) * 1000
        content_type = response.headers.get("content-type", "")
        length = response.headers.get("content-length", "-")
        logger.debug(
            "[%s] ← %s %s status=%s %.1fms bytes=%s type=%s",
            request_id,
            method,
            path,
            response.status_code,
            elapsed_ms,
            length,
            content_type.split(";")[0] if content_type else "-",
        )

        response.headers["X-Request-Id"] = request_id
        return response


def configure_api_logging(level: int | None = None) -> None:
    """Console logging. Default INFO so PHI is not dumped at DEBUG."""
    from app.core.config import settings

    if level is None:
        name = (getattr(settings, "log_level", None) or "INFO").upper()
        level = getattr(logging, name, logging.INFO)
    root = logging.getLogger("app")
    if not root.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
        )
        root.addHandler(handler)
    root.setLevel(level)
    logging.getLogger("app.api").setLevel(level)
