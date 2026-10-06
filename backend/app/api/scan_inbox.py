"""Scan inbox: a PC uploads scans and photos to the web page, the dentist assigns them
to a patient on the iPad (scans → the patient's scans, photos → the patient's photos,
where Shade Detection and Smile Preview open them)."""

from __future__ import annotations

import logging
import mimetypes
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile, status
from fastapi.responses import FileResponse
from typing import Literal

from pydantic import BaseModel

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_patient_media import DeleteOkOut
from app.services import patient_access as pa
from app.services import patient_media as pm
from app.services.r2 import (
    INBOX_EXPIRY_DAYS,
    bucket_for,
    copy_inbox_to,
    is_inbox_image,
    delete_patient_asset,
    download_r2_object_bytes,
    upload_inbox_file,
)

router = APIRouter()
page_router = APIRouter()
logger = logging.getLogger("app.api.scan_inbox")

_TABLE = "scan_inbox"
_PAGE = Path(__file__).resolve().parents[1] / "static" / "scan_upload.html"


_MAX_PATIENT_PHOTOS = 12  # same cap as the camera upload (patients_gdpr)


class InboxItemOut(BaseModel):
    id: str
    kind: str  # "scan" | "photo"
    file_name: str
    format: str
    byte_size: int
    created_at: datetime | None = None


class AssignIn(BaseModel):
    patient_id: str
    # Photos only: the Camera tab shows photos per angle.
    angle: Literal["frontal", "left", "right"] = "frontal"


def _out(row: dict) -> InboxItemOut:
    return InboxItemOut(
        id=str(row["id"]),
        kind="photo" if is_inbox_image(str(row.get("file_name") or "")) else "scan",
        file_name=str(row.get("file_name") or ""),
        format=str(row.get("format") or ""),
        byte_size=int(row.get("byte_size") or 0),
        created_at=row.get("created_at"),
    )


def _own_item(item_id: str, user: AuthUser) -> dict:
    row = pm.fetch_row(_TABLE, item_id)
    # 404 for someone else's item too, so ids can't be probed.
    if row is None or str(row.get("uploaded_by")) != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found")
    return row


@page_router.get("/scan-upload", include_in_schema=False)
def scan_upload_page():
    return FileResponse(
        _PAGE,
        media_type="text/html",
        headers={"Strict-Transport-Security": "max-age=31536000", "Cache-Control": "no-store"},
    )


@router.post("", response_model=InboxItemOut, status_code=status.HTTP_201_CREATED, summary="Upload a scan to your inbox")
def upload_to_inbox(file: UploadFile = File(...), user: AuthUser = Depends(get_current_user)):
    key, size, name = upload_inbox_file(file=file, user_id=user.id)
    try:
        row = pm.insert_row(
            _TABLE,
            {
                "uploaded_by": user.id,
                "file_key": key,
                "file_name": name,
                "format": Path(name).suffix.lower().lstrip("."),
                "byte_size": size,
            },
        )
    except Exception:
        delete_patient_asset(kind="inbox", file_key=key)
        raise
    logger.info("inbox upload user_id=%s item_id=%s size=%s", user.id, row["id"], size)
    return _out(row)


@router.get("", response_model=list[InboxItemOut], summary="List your incoming scans")
def list_inbox(user: AuthUser = Depends(get_current_user)):
    db = get_supabase_admin()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=INBOX_EXPIRY_DAYS)).isoformat()
    try:
        # The bucket's lifecycle rule removes the files; drop their rows here.
        db.table(_TABLE).delete().eq("uploaded_by", user.id).lt("created_at", cutoff).execute()
        rows = (
            db.table(_TABLE).select("*").eq("uploaded_by", user.id)
            .order("created_at", desc=True).execute().data or []
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    return [_out(r) for r in rows]


@router.get("/{item_id}/file", summary="Download an incoming scan (preview)")
def inbox_file(item_id: str, user: AuthUser = Depends(get_current_user)):
    row = _own_item(item_id, user)
    bucket = bucket_for("inbox")
    # ponytail: whole file in memory, like /api/files; stream if scans outgrow RAM.
    data = download_r2_object_bytes(bucket, str(row["file_key"]))
    return Response(
        content=data,
        media_type=mimetypes.guess_type(str(row["file_key"]))[0] or "application/octet-stream",
        headers={"Cache-Control": "private, no-store"},
    )


def _assign_scan(row: dict, item_id: str, patient_id: str, user_id: str, angle: str) -> str:
    # Inbox objects expire after 30 days, so the patient gets their own copy
    # (named after the item id: assigning twice reuses the same key and record).
    key = f"patients/{patient_id}/scans/{item_id}{Path(str(row['file_key'])).suffix}"
    copy_inbox_to("scans", src_key=str(row["file_key"]), dst_key=key)
    existing = pm.find_row_by_key("patient_scans", patient_id, key)
    if existing is not None:
        return str(existing["id"])
    try:
        return str(pm.insert_row("patient_scans", {
            "patient_id": patient_id,
            "uploaded_by": user_id,
            "file_key": key,
            "file_url": key,
            "file_name": row.get("file_name") or "",
            "format": row.get("format") or "",
            "created_at": pm.utc_now_iso(),
        })["id"])
    except Exception:
        delete_patient_asset(kind="scans", file_key=key)  # inbox item stays
        raise


def _assign_photo(row: dict, item_id: str, patient_id: str, user_id: str, angle: str) -> str:
    db = get_supabase_admin()
    key = f"patients/{patient_id}/photos/{item_id}{Path(str(row['file_key'])).suffix}"
    try:
        found = db.table("patient_photos").select("id").eq("patient_id", patient_id).eq("file_url", key).execute().data
        if found:
            return str(found[0]["id"])
        count = len(db.table("patient_photos").select("id").eq("patient_id", patient_id).execute().data or [])
    except Exception as exc:
        raise pa.db_error(exc) from exc
    if count >= _MAX_PATIENT_PHOTOS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"This patient already has {_MAX_PATIENT_PHOTOS} photos. Delete one first.")
    copy_inbox_to("photos", src_key=str(row["file_key"]), dst_key=key)
    try:
        photo_id = str(pm.insert_row("patient_photos", {
            "patient_id": patient_id,
            "uploaded_by": user_id,
            "angle": angle,
            "filename": row.get("file_name") or "photo.jpg",
            "file_url": key,
            "byte_size": int(row.get("byte_size") or 0),
            "created_at": pm.utc_now_iso(),
        })["id"])
    except Exception:
        delete_patient_asset(kind="photos", file_key=key)  # inbox item stays
        raise
    pa.write_audit_log(actor_id=user_id, action="upload_patient_photo", patient_id=patient_id, details={"photo_id": photo_id, "source": "inbox"})
    return photo_id


@router.post("/{item_id}/assign", summary="Assign an incoming file to a patient")
def assign_inbox_item(item_id: str, body: AssignIn, user: AuthUser = Depends(get_current_user)):
    row = _own_item(item_id, user)
    pm.require_patient_access(body.patient_id, user.id)
    photo = is_inbox_image(str(row.get("file_name") or ""))
    assign = _assign_photo if photo else _assign_scan
    record_id = assign(row, item_id, body.patient_id, user.id, body.angle)
    # Past this point the file is safely on the record; cleanup failures are harmless.
    try:
        delete_patient_asset(kind="inbox", file_key=str(row["file_key"]))
        pm.delete_row(_TABLE, item_id)
    except Exception:
        logger.warning("inbox cleanup after assign failed item_id=%s", item_id, exc_info=True)
    logger.info("inbox assign user_id=%s item_id=%s patient_id=%s", user.id, item_id, body.patient_id)
    return {
        "assigned": True,
        "kind": "photo" if photo else "scan",
        "record_id": record_id,
        "scan_id": None if photo else record_id,
        "patient_id": body.patient_id,
    }


@router.delete("/{item_id}", response_model=DeleteOkOut, summary="Delete an incoming scan")
def delete_inbox_item(item_id: str, user: AuthUser = Depends(get_current_user)):
    row = _own_item(item_id, user)
    delete_patient_asset(kind="inbox", file_key=str(row["file_key"]))
    pm.delete_row(_TABLE, item_id)
    return DeleteOkOut(deleted=True, id=item_id)
