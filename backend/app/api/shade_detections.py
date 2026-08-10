"""Shade detection images — list/upload under patients, delete under /api/shade-detections."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, UploadFile, status

from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, ShadeDetectionOut
from app.services import patient_media as pm

patients_router = APIRouter()
shades_router = APIRouter()
logger = logging.getLogger("app.api.shade_detections")

_TABLE = "shade_detections"
_KIND = "shades"


def _serialize(row: dict) -> ShadeDetectionOut:
    return ShadeDetectionOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
    )


@patients_router.get(
    "/{patient_id}/shade-detections",
    response_model=list[ShadeDetectionOut],
    summary="List patient shade detections",
)
def list_shade_detections(
    patient_id: str,
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    rows = pm.list_rows(_TABLE, patient_id)
    return [_serialize(r) for r in rows]


@patients_router.post(
    "/{patient_id}/shade-detections",
    response_model=ShadeDetectionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a shade detection image",
)
async def upload_shade_detection(
    patient_id: str,
    file: UploadFile = File(...),
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    logger.debug(
        "upload shade patient_id=%s user_id=%s filename=%s",
        patient_id,
        user.id,
        file.filename,
    )
    row = pm.upload_and_insert(
        table=_TABLE,
        kind=_KIND,
        patient_id=patient_id,
        user_id=user.id,
        file=file,
    )
    return _serialize(row)


@shades_router.delete(
    "/{shade_id}",
    response_model=DeleteOkOut,
    summary="Delete a shade detection (R2 + DB)",
)
def delete_shade_detection(
    shade_id: str,
    user: AuthUser = Depends(get_current_user),
):
    row = pm.delete_record_and_file(
        table=_TABLE,
        kind=_KIND,
        row_id=shade_id,
        user_id=user.id,
    )
    return DeleteOkOut(deleted=True, id=str(row["id"]))
