"""Load a stored patient file's bytes (photos / scans / shades / smiles)."""

from __future__ import annotations

import logging

from fastapi import HTTPException, status

from app.services.r2 import (
    LOCAL_PHOTO_URL_PREFIX,
    bucket_for,
    download_r2_object_bytes,
    file_key_from_patient_photo_url,
    is_local_patient_photo_url,
    local_patient_photo_path,
)

logger = logging.getLogger("app.shade_media")


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")


def load_media_bytes(kind: str, row: dict) -> bytes:
    """Bytes of `row`'s file: its kind's bucket by `file_key`.

    Two fallbacks for older records, each logged and confined to the row's own
    patient folder so a bad key can never reach another patient's file:
    - a camera photo on local disk (development without R2)
    - a shade/smile/scan row still pointing at its camera photo (data from
      before the cleanup script, or app builds from before real copies)
    """
    pid = str(row.get("patient_id") or "")
    url = str(row.get("file_url") or "")

    if kind == "photos" and is_local_patient_photo_url(url):
        parts = url[len(LOCAL_PHOTO_URL_PREFIX) + 1 :].split("/")
        path = local_patient_photo_path(*parts) if len(parts) == 2 and parts[0] == pid else None
        if path is None or not path.is_file():
            raise _not_found()
        return path.read_bytes()

    key = str(row.get("file_key") or "")
    if not key and kind == "photos":
        key = file_key_from_patient_photo_url(url)
    own = f"patients/{pid}/"
    if not pid or not key.startswith(own):
        logger.warning("file outside patient folder kind=%s id=%s key=%s", kind, row.get("id"), key)
        raise _not_found()

    source = kind
    if kind != "photos" and key.startswith(f"{own}photos/"):
        logger.warning("legacy camera-photo pointer kind=%s id=%s key=%s", kind, row.get("id"), key)
        source = "photos"
    bucket, _ = bucket_for(source)
    return download_r2_object_bytes(bucket, key)
