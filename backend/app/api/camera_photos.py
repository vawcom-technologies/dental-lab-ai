"""Copy camera captures (`patient_photos`) into shade/smile records (older app builds)."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.services.file_urls import client_file_url
from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_patient_media import ShadeDetectionOut, SmilePreviewOut
from app.services import patient_access as pa
from app.services import patient_media as pm
from app.services.shade_media import load_media_bytes

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
    """Real copy into the kind's bucket; the same photo again reuses its record.

    Only app builds from before Save-time copies call this.
    """
    patient_id = str(photo.get("patient_id") or "")
    if not patient_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Photo is missing patient_id",
        )
    pm.require_patient_access(patient_id, user_id)
    return pm.upload_and_insert(
        table=table,
        kind="shades" if table == "shade_detections" else "smiles",
        patient_id=patient_id,
        user_id=user_id,
        data=load_media_bytes("photos", photo),
        filename=str(photo.get("filename") or "photo.jpg"),
    )


def _shade_out(row: dict) -> ShadeDetectionOut:
    return ShadeDetectionOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=client_file_url("shades", row),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
    )


def _smile_out(row: dict) -> SmilePreviewOut:
    return SmilePreviewOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=client_file_url("smiles", row),
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
