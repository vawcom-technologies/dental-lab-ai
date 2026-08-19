"""Load shade-detection image bytes from local disk or R2 (no client re-upload)."""

from __future__ import annotations

import logging
from urllib.request import Request, urlopen

from fastapi import HTTPException, status

from app.services.r2 import (
    LOCAL_PHOTO_URL_PREFIX,
    download_r2_object_bytes,
    file_key_from_patient_photo_url,
    is_local_patient_photo_url,
    is_patient_images_url,
    local_patient_photo_path,
    patient_images_r2_configured,
)

logger = logging.getLogger("app.shade_media")


def load_shade_detection_bytes(row: dict) -> bytes:
    """Return original image bytes for a `shade_detections` row."""
    file_url = str(row.get("file_url") or "").strip()
    file_key = str(row.get("file_key") or "").strip()

    if is_local_patient_photo_url(file_url):
        rest = file_url[len(LOCAL_PHOTO_URL_PREFIX) + 1 :]
        parts = rest.split("/")
        if len(parts) != 2:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Shade photo path is invalid",
            )
        path = local_patient_photo_path(parts[0], parts[1])
        if path is None or not path.is_file():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Shade photo is missing on the server",
            )
        return path.read_bytes()

    if is_patient_images_url(file_url) and patient_images_r2_configured():
        from app.services.r2 import _require_patient_images_bucket

        key = file_key or file_key_from_patient_photo_url(file_url)
        bucket, _ = _require_patient_images_bucket()
        return download_r2_object_bytes(bucket, key)

    if file_key and "/shades/" in file_key:
        from app.services.r2 import _require_patient_bucket

        bucket, _ = _require_patient_bucket("shades")
        return download_r2_object_bytes(bucket, file_key)

    if file_url.startswith("http://") or file_url.startswith("https://"):
        return _http_get_bytes(file_url)

    if file_key:
        from app.services.r2 import _require_patient_bucket

        bucket, _ = _require_patient_bucket("shades")
        return download_r2_object_bytes(bucket, file_key)

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Shade photo has no stored file",
    )


def _http_get_bytes(url: str) -> bytes:
    req = Request(url, method="GET")
    try:
        with urlopen(req, timeout=20) as resp:  # noqa: S310 — clinic CDN / R2 public URL
            data = resp.read()
    except Exception as exc:
        logger.exception("shade photo HTTP fetch failed url=%s", url)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not fetch shade photo for analysis",
        ) from exc
    if not data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shade photo download was empty",
        )
    return data
