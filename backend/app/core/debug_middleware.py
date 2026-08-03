"""Request/response debug logging for every API call."""

from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger("app.api")


class DebugRequestMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = uuid.uuid4().hex[:8]
        method = request.method
        path = request.url.path
        query = str(request.url.query) if request.url.query else ""
        client = request.client.host if request.client else "-"
        auth = "yes" if request.headers.get("authorization") else "no"

        logger.debug(
            "[%s] → %s %s%s client=%s auth=%s",
            request_id,
            method,
            path,
            f"?{query}" if query else "",
            client,
            auth,
        )

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed_ms = (time.perf_counter() - started) * 1000
            logger.exception(
                "[%s] ✕ %s %s crashed after %.1fms",
                request_id,
                method,
                path,
                elapsed_ms,
            )
            raise

        # Consume body so we can log the full response the client receives
        body = b""
        async for chunk in response.body_iterator:
            body += chunk if isinstance(chunk, (bytes, bytearray)) else chunk.encode()

        elapsed_ms = (time.perf_counter() - started) * 1000
        content_type = response.headers.get("content-type", "")
        try:
            body_text = body.decode("utf-8")
        except UnicodeDecodeError:
            body_text = f"<binary {len(body)} bytes content_type={content_type!r}>"

        logger.debug(
            "[%s] ← %s %s status=%s %.1fms\nresponse_body=%s",
            request_id,
            method,
            path,
            response.status_code,
            elapsed_ms,
            body_text,
        )
        # Also print so it always shows in the uvicorn terminal
        print(
            f"[DEBUG {request_id}] {method} {path} -> {response.status_code} "
            f"({elapsed_ms:.1f}ms)\n{body_text}\n",
            flush=True,
        )

        headers = {
            k: v
            for k, v in response.headers.items()
            if k.lower() not in ("content-length", "content-encoding")
        }
        headers["X-Request-Id"] = request_id

        return Response(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
            background=response.background,
        )


def configure_api_logging(level: int = logging.DEBUG) -> None:
    """Ensure API debug logs show in the uvicorn console."""
    root = logging.getLogger("app")
    if not root.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
        )
        root.addHandler(handler)
    root.setLevel(level)
    logging.getLogger("app.api").setLevel(level)
