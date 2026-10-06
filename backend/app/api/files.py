"""Authenticated file access for patient media in private R2 buckets."""

from __future__ import annotations

import mimetypes

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.core.security import AuthUser, get_current_user
from app.services import patient_media as pm
from app.services.shade_media import load_media_bytes

router = APIRouter()

_TABLES = {
    "photos": "patient_photos",
    "scans": "patient_scans",
    "shades": "shade_detections",
    "smiles": "smile_previews",
}


@router.get("/{kind}/{row_id}", summary="Download a patient file (access-checked)")
def get_file(
    kind: str,
    row_id: str,
    part: str | None = None,
    user: AuthUser = Depends(get_current_user),
):
    table = _TABLES.get(kind)
    if table is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown file kind")
    row = pm.fetch_row(table, row_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    pm.require_patient_access(str(row.get("patient_id") or ""), user.id)
    # ponytail: whole file in memory; stream from R2 if scans get very large.
    if part == "base":
        # Smile preview: the photo without overlays.
        if not row.get("base_file_key"):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
        row = {**row, "file_key": row["base_file_key"], "file_name": ""}
    data = load_media_bytes(kind, row)
    # Display names can lack an extension ("Upper smile"); the key never does.
    name = str(row.get("file_name") or row.get("filename") or "")
    media_type = mimetypes.guess_type(name)[0] or mimetypes.guess_type(
        str(row.get("file_key") or row.get("file_url") or "")
    )[0]
    return Response(
        content=data,
        media_type=media_type or "application/octet-stream",
        headers={"Cache-Control": "private, max-age=300"},
    )
