"""Shade detection images — list/upload under patients, delete under /api/shade-detections."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel, Field, ValidationError

from app.services.file_urls import client_file_url
from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, ShadeDetectionOut
from app.services import patient_media as pm
from app.services.shade_media import load_media_bytes

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
    gum: dict | None = None
    # App's session-tab entry + workspace (tooth outlines, overrides, guide
    # lines) so a saved shade reopens exactly. No image bytes, no patient PII.
    session: dict | None = None


def _serialize(row: dict) -> ShadeDetectionOut:
    analysis = row.get("analysis")
    return ShadeDetectionOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=client_file_url("shades", row),
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


def _analysis_json(payload: ShadeAnalysisIn) -> dict:
    analysis = payload.model_dump()
    analysis["saved_at"] = pm.utc_now_iso()
    return analysis


@patients_router.post(
    "/{patient_id}/shade-detections",
    response_model=ShadeDetectionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Save a shade detection to the patient record",
)
async def upload_shade_detection(
    patient_id: str,
    file: UploadFile | None = File(None),
    photo_id: str | None = Form(None),
    analysis: str | None = Form(None),
    user: AuthUser = Depends(get_current_user),
):
    """Send either the image (`file`) or a camera photo of this patient
    (`photo_id`, copied into the shades bucket server-side), optionally with
    the `analysis` JSON. Saving the same image again updates its record."""
    pm.require_patient_access(patient_id, user.id)
    if file is not None:
        data, filename, ctype = await file.read(), file.filename, file.content_type
    elif photo_id:
        photo = pm.fetch_row("patient_photos", photo_id)
        if photo is None or str(photo.get("patient_id")) != patient_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
        data, filename, ctype = load_media_bytes("photos", photo), photo.get("filename"), None
    else:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Send a file or a photo_id")

    extra = None
    if analysis:
        try:
            extra = {"analysis": _analysis_json(ShadeAnalysisIn.model_validate_json(analysis))}
        except ValidationError as exc:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid analysis") from exc

    logger.debug(
        "save shade patient_id=%s user_id=%s photo_id=%s filename=%s",
        patient_id,
        user.id,
        photo_id,
        filename,
    )
    row = pm.upload_and_insert(
        table=_TABLE,
        kind=_KIND,
        patient_id=patient_id,
        user_id=user.id,
        data=data,
        filename=filename,
        content_type=ctype,
        extra=extra,
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
    updated = pm.update_row(_TABLE, shade_id, {"analysis": _analysis_json(payload)})
    return _serialize(updated)
