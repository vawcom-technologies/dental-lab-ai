"""Copy camera captures (`patient_photos`) into shade/smile tables without re-upload."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_patient_media import ShadeDetectionOut, SmilePreviewOut
from app.services import patient_access as pa
from app.services import patient_media as pm
from app.services.r2 import file_key_from_patient_photo_url

router = APIRouter()
logger = logging.getLogger("app.api.camera_photos")


def _fetch_photo(photo_id: str) -> dict:
    try:
        result = (
            get_supabase_admin()
            .table("patient_photos")
            .select("*")
            .eq("id", photo_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Photo not found",
        )
    return rows[0]


def _copy_photo_row(
    *,
    photo: dict,
    table: str,
    user_id: str,
) -> dict:
    patient_id = str(photo.get("patient_id") or "")
    file_url = str(photo.get("file_url") or "").strip()
    if not patient_id or not file_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Photo is missing patient_id or file_url",
        )

    pm.require_patient_access(patient_id, user_id)

    file_key = str(photo.get("file_key") or "").strip()
    if not file_key:
        file_key = file_key_from_patient_photo_url(file_url)
    if not file_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not derive file_key from photo file_url",
        )

    file_name = str(photo.get("filename") or photo.get("file_name") or "photo.jpg")
    row = {
        "patient_id": patient_id,
        "uploaded_by": user_id,
        "file_key": file_key,
        "file_url": file_url,
        "file_name": file_name,
        "created_at": pm.utc_now_iso(),
    }
    return pm.insert_row(table, row)


def _shade_out(row: dict) -> ShadeDetectionOut:
    return ShadeDetectionOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
    )


def _smile_out(row: dict) -> SmilePreviewOut:
    return SmilePreviewOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
    )


@router.post(
    "/{photo_id}/copy-to-shade",
    response_model=ShadeDetectionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Copy a camera photo into shade_detections (no re-upload)",
)
def copy_photo_to_shade(
    photo_id: str,
    user: AuthUser = Depends(get_current_user),
):
    photo = _fetch_photo(photo_id)
    logger.debug(
        "copy-to-shade photo_id=%s user_id=%s patient_id=%s",
        photo_id,
        user.id,
        photo.get("patient_id"),
    )
    row = _copy_photo_row(photo=photo, table="shade_detections", user_id=user.id)
    return _shade_out(row)


@router.post(
    "/{photo_id}/copy-to-smile",
    response_model=SmilePreviewOut,
    status_code=status.HTTP_201_CREATED,
    summary="Copy a camera photo into smile_previews (no re-upload)",
)
def copy_photo_to_smile(
    photo_id: str,
    user: AuthUser = Depends(get_current_user),
):
    photo = _fetch_photo(photo_id)
    logger.debug(
        "copy-to-smile photo_id=%s user_id=%s patient_id=%s",
        photo_id,
        user.id,
        photo.get("patient_id"),
    )
    row = _copy_photo_row(photo=photo, table="smile_previews", user_id=user.id)
    return _smile_out(row)
