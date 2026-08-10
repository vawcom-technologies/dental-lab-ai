"""Shared helpers for patient clinical media CRUD (scans / shades / smiles)."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from fastapi import HTTPException, UploadFile, status

from app.core.supabase_client import get_supabase_admin
from app.services import patient_access as pa
from app.services.r2 import PatientAssetKind, delete_patient_asset, upload_patient_asset

logger = logging.getLogger("app.patient_media")


def utc_now_iso() -> str:
    return pa.utc_now_iso()


def require_patient_access(patient_id: str, user_id: str) -> dict[str, Any]:
    return pa.require_patient_access(patient_id, user_id)


def list_rows(table: str, patient_id: str) -> list[dict[str, Any]]:
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .select("*")
            .eq("patient_id", patient_id)
            .order("created_at", desc=True)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    return list(getattr(result, "data", None) or [])


def fetch_row(table: str, row_id: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .select("*")
            .eq("id", row_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def insert_row(table: str, row: dict[str, Any]) -> dict[str, Any]:
    try:
        result = get_supabase_admin().table(table).insert(row).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Insert returned no row",
        )
    return rows[0]


def delete_row(table: str, row_id: str) -> None:
    try:
        get_supabase_admin().table(table).delete().eq("id", row_id).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc


def upload_and_insert(
    *,
    table: str,
    kind: PatientAssetKind,
    patient_id: str,
    user_id: str,
    file: UploadFile,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Upload to R2 then insert DB row. Rolls back R2 object if insert fails."""
    file_key, file_url, file_name = upload_patient_asset(
        file=file,
        kind=kind,
        patient_id=patient_id,
    )
    row: dict[str, Any] = {
        "patient_id": patient_id,
        "uploaded_by": user_id,
        "file_key": file_key,
        "file_url": file_url,
        "file_name": file_name,
        "created_at": utc_now_iso(),
    }
    if kind == "scans":
        row["format"] = Path(file_name).suffix.lower().lstrip(".")
    if extra:
        row.update(extra)

    try:
        return insert_row(table, row)
    except Exception:
        try:
            delete_patient_asset(kind=kind, file_key=file_key)
        except Exception:
            logger.exception(
                "R2 rollback failed after DB insert error kind=%s key=%s",
                kind,
                file_key,
            )
        raise


def delete_record_and_file(
    *,
    table: str,
    kind: PatientAssetKind,
    row_id: str,
    user_id: str,
) -> dict[str, Any]:
    """
    Authorize via patient access, delete R2 object, then delete DB row.
    Returns the deleted row (pre-delete snapshot).
    """
    row = fetch_row(table, row_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Record not found",
        )
    patient_id = str(row.get("patient_id") or "")
    require_patient_access(patient_id, user_id)

    file_key = str(row.get("file_key") or "")
    if file_key:
        delete_patient_asset(kind=kind, file_key=file_key)
    delete_row(table, row_id)
    return row
