"""Smile previews — list/save under patients, update/delete under /api/smile-previews.

A saved smile is the photo with overlays (`file_key`, what the lab sees), the
photo without overlays (`base_file_key`) and the shape placements (`overlay`),
so the doctor can reopen it and keep editing.
"""

from __future__ import annotations

import json
import logging

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status

from app.services.file_urls import client_base_file_url, client_file_url
from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, SmilePreviewOut
from app.services import patient_media as pm
from app.services.r2 import upload_patient_asset
from app.services.shade_media import load_media_bytes

patients_router = APIRouter()
smiles_router = APIRouter()
logger = logging.getLogger("app.api.smile_previews")

_TABLE = "smile_previews"
_KIND = "smiles"


def _serialize(row: dict) -> SmilePreviewOut:
    overlay = row.get("overlay")
    return SmilePreviewOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=client_file_url("smiles", row),
        file_name=str(row.get("file_name") or ""),
        created_at=row.get("created_at"),
        base_file_url=client_base_file_url("smiles", row),
        overlay=overlay if isinstance(overlay, dict) else None,
    )


def _overlay_json(raw: str | None) -> dict | None:
    if not raw:
        return None
    try:
        value = json.loads(raw)
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid overlay") from exc
    if not isinstance(value, dict):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid overlay")
    return value


def _cleanup(key: str, patient_id: str) -> None:
    """Best-effort: drop a smiles file no saved smile of this patient uses."""
    try:
        pm.delete_file_if_unused(table=_TABLE, kind=_KIND, patient_id=patient_id, file_key=key)
    except HTTPException:
        logger.warning("smile file cleanup failed key=%s", key)


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
    summary="Save a smile preview to the patient record",
)
async def upload_smile_preview(
    patient_id: str,
    file: UploadFile = File(...),
    base: UploadFile | None = File(None),
    base_photo_id: str | None = Form(None),
    overlay: str | None = Form(None),
    user: AuthUser = Depends(get_current_user),
):
    """`file` is the photo with overlays. The photo without overlays comes as
    `base` (gallery) or `base_photo_id` (camera photo of this patient, copied
    server-side); `overlay` is the shape placements JSON. Older app builds send
    `file` alone."""
    pm.require_patient_access(patient_id, user.id)
    extra: dict = {}
    if base is not None or base_photo_id:
        if base is not None:
            data, name, ctype = await base.read(), base.filename, base.content_type
        else:
            photo = pm.fetch_row("patient_photos", base_photo_id)
            if photo is None or str(photo.get("patient_id")) != patient_id:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
            data, name, ctype = load_media_bytes("photos", photo), photo.get("filename"), None
        extra["base_file_key"], _, _ = upload_patient_asset(
            data=data, filename=name, content_type=ctype, kind=_KIND, patient_id=patient_id
        )
    placements = _overlay_json(overlay)
    if placements is not None:
        extra["overlay"] = placements

    logger.debug(
        "save smile patient_id=%s user_id=%s base_photo_id=%s",
        patient_id,
        user.id,
        base_photo_id,
    )
    row = pm.upload_and_insert(
        table=_TABLE,
        kind=_KIND,
        patient_id=patient_id,
        user_id=user.id,
        data=await file.read(),
        filename=file.filename,
        content_type=file.content_type,
        extra=extra or None,
    )
    return _serialize(row)


@smiles_router.patch(
    "/{preview_id}",
    response_model=SmilePreviewOut,
    summary="Update a reopened smile preview (new overlays, same photo)",
)
async def update_smile_preview(
    preview_id: str,
    file: UploadFile = File(...),
    overlay: str = Form(...),
    user: AuthUser = Depends(get_current_user),
):
    row = pm.fetch_row(_TABLE, preview_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Smile preview not found")
    patient_id = str(row.get("patient_id") or "")
    pm.require_patient_access(patient_id, user.id)
    old_key = str(row.get("file_key") or "")
    key, url, name = upload_patient_asset(
        data=await file.read(),
        filename=file.filename,
        content_type=file.content_type,
        kind=_KIND,
        patient_id=patient_id,
    )
    patch = {"file_key": key, "file_url": url, "file_name": name, "overlay": _overlay_json(overlay)}
    first_save = not row.get("base_file_key")
    if first_save:
        # Photo stored before overlays were saved: it becomes the base.
        patch["base_file_key"] = old_key
    updated = pm.update_row(_TABLE, preview_id, patch)
    if not first_save and old_key != key:
        _cleanup(old_key, patient_id)
    return _serialize(updated)


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
    _cleanup(str(row.get("base_file_key") or ""), str(row["patient_id"]))
    return DeleteOkOut(deleted=True, id=str(row["id"]))
