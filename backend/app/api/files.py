"""Authenticated file access for patient media in private R2 buckets."""

from __future__ import annotations

import mimetypes

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.core.security import AuthUser, get_current_user
from app.services import patient_media as pm
from app.services.r2 import _require_patient_bucket, download_r2_object_bytes
from app.services.shade_media import load_shade_detection_bytes

router = APIRouter()

_TABLES = {
    "photos": "patient_photos",
    "scans": "patient_scans",
    "shades": "shade_detections",
    "smiles": "smile_previews",
}


def _load_bytes(kind: str, row: dict) -> bytes:
    if kind in ("photos", "shades"):
        # Handles the camera-photo bucket, shade keys and the local fallback.
        return load_shade_detection_bytes(row)
    key = str(row.get("file_key") or "").strip()
    bucket, _ = _require_patient_bucket(kind)
    return download_r2_object_bytes(bucket, key)


@router.get("/{kind}/{row_id}", summary="Download a patient file (access-checked)")
def get_file(kind: str, row_id: str, user: AuthUser = Depends(get_current_user)):
    table = _TABLES.get(kind)
    if table is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown file kind")
    row = pm.fetch_row(table, row_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    pm.require_patient_access(str(row.get("patient_id") or ""), user.id)
    # ponytail: whole file in memory; stream from R2 if scans get very large.
    data = _load_bytes(kind, row)
    name = str(row.get("file_name") or row.get("filename") or "")
    return Response(
        content=data,
        media_type=mimetypes.guess_type(name)[0] or "application/octet-stream",
        headers={"Cache-Control": "private, max-age=300"},
    )
