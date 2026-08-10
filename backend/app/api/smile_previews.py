"""Smile previews — list/upload under patients, delete under /api/smile-previews."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, UploadFile, status

from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, SmilePreviewOut
from app.services import patient_media as pm

patients_router = APIRouter()
smiles_router = APIRouter()
logger = logging.getLogger("app.api.smile_previews")

_TABLE = "smile_previews"
_KIND = "smiles"


def _serialize(row: dict) -> SmilePreviewOut:
    return SmilePreviewOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
    )


@patients_router.get(
    "/{patient_id}/smile-previews",
    response_model=list[SmilePreviewOut],
    summary="List patient smile previews",
)
def list_smile_previews(
    patient_id: str,
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    rows = pm.list_rows(_TABLE, patient_id)
    return [_serialize(r) for r in rows]


@patients_router.post(
    "/{patient_id}/smile-previews",
    response_model=SmilePreviewOut,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a smile preview image",
)
async def upload_smile_preview(
    patient_id: str,
    file: UploadFile = File(...),
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    logger.debug(
        "upload smile patient_id=%s user_id=%s filename=%s",
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


@smiles_router.delete(
    "/{preview_id}",
    response_model=DeleteOkOut,
    summary="Delete a smile preview (R2 + DB)",
)
def delete_smile_preview(
    preview_id: str,
    user: AuthUser = Depends(get_current_user),
):
    row = pm.delete_record_and_file(
        table=_TABLE,
        kind=_KIND,
        row_id=preview_id,
        user_id=user.id,
    )
    return DeleteOkOut(deleted=True, id=str(row["id"]))
