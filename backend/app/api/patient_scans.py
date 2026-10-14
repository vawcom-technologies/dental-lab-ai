"""Patient 3D scans — list/upload under patients, delete under /api/scans."""

from __future__ import annotations

import asyncio
import logging
import re

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.services.file_urls import client_file_url
from app.ai.scan_quality import QUALITY_VERSION, validate_scan_bytes
from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, PatientScanOut
from app.services import patient_media as pm
from app.services.shade_media import load_media_bytes

patients_router = APIRouter()
scans_router = APIRouter()
logger = logging.getLogger("app.api.patient_scans")

_TABLE = "patient_scans"
_KIND = "scans"


def _stored_quality(row: dict) -> dict | None:
    """The saved result, unless it predates the current checks."""
    q = row.get("quality")
    return q if isinstance(q, dict) and q.get("v") == QUALITY_VERSION else None


def _save_quality(scan_id: str, quality: dict) -> None:
    """Best effort: a failed save only means the scan is re-checked next time."""
    try:
        pm.update_row(_TABLE, scan_id, {"quality": quality})
    except Exception:
        logger.exception("could not store scan quality scan_id=%s", scan_id)


_JAW = re.compile(r"^(?P<case>.*?)[ _-]*(?P<jaw>maxillary|mandibular|upper|lower)\b", re.I)


def _is_upper(m: re.Match) -> bool:
    return m["jaw"].lower() in ("maxillary", "upper")


def _opposing_scan(row: dict) -> tuple[bytes, str] | None:
    """The other arch from the same export, for the bite-overlap check.

    Pairs by a shared case prefix ("WA943_Maxillary…" ↔ "WA943_Mandibular…"),
    so scans from different visits are never compared. Best effort: any
    failure just skips the check.
    ponytail: a scan validated before its opposite arch arrived keeps its
    cached result without the bite check until QUALITY_VERSION changes.
    """
    m = _JAW.match(str(row.get("file_name") or ""))
    if not m or not m["case"]:
        return None
    try:
        for other in pm.list_rows(_TABLE, str(row["patient_id"])):
            o = _JAW.match(str(other.get("file_name") or ""))
            if o and other["id"] != row.get("id") and o["case"] == m["case"] and _is_upper(o) != _is_upper(m):
                return load_media_bytes("scans", other), str(other["file_name"])
    except Exception:
        logger.exception("could not load the opposing arch for scan_id=%s", row.get("id"))
    return None


def _validate(data: bytes, row: dict) -> dict:
    name = str(row.get("file_name") or row.get("file_key") or "scan.ply")
    return validate_scan_bytes(data, name, opposing=_opposing_scan(row))


def _serialize(row: dict, validation: dict | None = None) -> PatientScanOut:
    extra = validation or _stored_quality(row) or {}
    return PatientScanOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=client_file_url("scans", row),
        file_name=str(row.get("file_name") or ""),
        format=str(row.get("format") or ""),
        created_at=row.get("created_at"),
        validation_result=extra.get("result") or extra.get("validation_result"),
        prompt_rescan=bool(extra.get("prompt_rescan", False)),
        reasons=list(extra.get("reasons") or []),
        issues=list(extra.get("issues") or []),
        note=extra.get("note"),
        rough_points=list(extra.get("rough_points") or []),
        rough_radius=float(extra.get("rough_radius") or 0.0),
    )


@patients_router.get(
    "/{patient_id}/scans",
    response_model=list[PatientScanOut],
    summary="List patient 3D scans",
)
def list_patient_scans(
    patient_id: str,
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    rows = pm.list_rows(_TABLE, patient_id)
    return [_serialize(r) for r in rows]


@patients_router.post(
    "/{patient_id}/scans",
    response_model=PatientScanOut,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a 3D scan (.ply / .stl / .obj)",
)
async def upload_patient_scan(
    patient_id: str,
    file: UploadFile = File(...),
    user: AuthUser = Depends(get_current_user),
):
    pm.require_patient_access(patient_id, user.id)
    logger.debug(
        "upload scan patient_id=%s user_id=%s filename=%s",
        patient_id,
        user.id,
        file.filename,
    )
    # ponytail: whole scan in memory (validation needs it anyway); stream if scans outgrow RAM.
    data = await file.read()
    validation = await asyncio.to_thread(
        _validate, data, {"file_name": file.filename or "scan.ply", "patient_id": patient_id}
    )
    row = pm.upload_and_insert(
        table=_TABLE,
        kind=_KIND,
        patient_id=patient_id,
        user_id=user.id,
        data=data,
        filename=file.filename,
        content_type=file.content_type,
    )
    await asyncio.to_thread(_save_quality, str(row["id"]), validation)
    return _serialize(row, validation)


@scans_router.post(
    "/{scan_id}/validate",
    response_model=PatientScanOut,
    summary="Check a stored scan's quality (cached on the row)",
)
async def validate_patient_scan(
    scan_id: str,
    user: AuthUser = Depends(get_current_user),
):
    """For scans with no current result (older uploads, inbox assignments,
    or after QUALITY_VERSION changed). Reads the file server-side, so the
    iPad never re-uploads the scan just to have it checked."""
    row = pm.fetch_row(_TABLE, scan_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Scan not found")
    pm.require_patient_access(str(row.get("patient_id") or ""), user.id)
    if _stored_quality(row) is None:
        data = await asyncio.to_thread(load_media_bytes, "scans", row)
        validation = await asyncio.to_thread(_validate, data, row)
        await asyncio.to_thread(_save_quality, scan_id, validation)
        return _serialize(row, validation)
    return _serialize(row)


@scans_router.delete(
    "/{scan_id}",
    response_model=DeleteOkOut,
    summary="Delete a 3D scan (R2 + DB)",
)
def delete_patient_scan(
    scan_id: str,
    user: AuthUser = Depends(get_current_user),
):
    row = pm.delete_record_and_file(
        table=_TABLE,
        kind=_KIND,
        row_id=scan_id,
        user_id=user.id,
    )
    return DeleteOkOut(deleted=True, id=str(row["id"]))
