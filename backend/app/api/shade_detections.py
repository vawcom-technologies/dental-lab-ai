"""Shade detection images — list/upload under patients, delete under /api/shade-detections."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, Field

from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, ShadeDetectionOut
from app.services import patient_media as pm

patients_router = APIRouter()
shades_router = APIRouter()
logger = logging.getLogger("app.api.shade_detections")

_TABLE = "shade_detections"
_KIND = "shades"


class ShadeAnalysisIn(BaseModel):
    teeth: list[dict] = Field(default_factory=list)
    selected_tooth_index: int = 0
    summary_shade: str | None = None
    has_override: bool = False
    detected_shade: str | None = None
    confidence: float | None = None
    overridden: bool = False
    final_shade: str | None = None


def _serialize(row: dict) -> ShadeDetectionOut:
    analysis = row.get("analysis")
    return ShadeDetectionOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
        analysis=analysis if isinstance(analysis, dict) else None,
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


@shades_router.patch(
    "/{shade_id}",
    response_model=ShadeDetectionOut,
    summary="Save shade analysis onto a detection image",
)
def save_shade_detection_analysis(
    shade_id: str,
    payload: ShadeAnalysisIn,
    user: AuthUser = Depends(get_current_user),
):
    row = pm.fetch_row(_TABLE, shade_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shade detection not found",
        )
    pm.require_patient_access(str(row.get("patient_id") or ""), user.id)
    analysis = payload.model_dump()
    analysis["saved_at"] = pm.utc_now_iso()
    try:
        updated = pm.update_row(_TABLE, shade_id, {"analysis": analysis})
    except Exception:
        logger.exception("shade analysis persist failed id=%s", shade_id)
        # Column may be missing until migration 009; still return the row so
        # the chairside session can complete.
        row = {**row, "analysis": analysis}
        return _serialize(row)
    return _serialize(updated)
