"""Patient 3D scans — list/upload under patients, delete under /api/scans."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, UploadFile, status

from app.core.security import AuthUser, get_current_user
from app.schemas_patient_media import DeleteOkOut, PatientScanOut
from app.services import patient_media as pm

patients_router = APIRouter()
scans_router = APIRouter()
logger = logging.getLogger("app.api.patient_scans")

_TABLE = "patient_scans"
_KIND = "scans"


def _serialize(row: dict) -> PatientScanOut:
    return PatientScanOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        uploaded_by=str(row["uploaded_by"]),
        file_key=str(row.get("file_key") or ""),
        file_url=str(row.get("file_url") or ""),
        file_name=str(row.get("file_name") or ""),
        format=str(row.get("format") or ""),
        created_at=row.get("created_at"),
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
    row = pm.upload_and_insert(
        table=_TABLE,
        kind=_KIND,
        patient_id=patient_id,
        user_id=user.id,
        file=file,
    )
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
