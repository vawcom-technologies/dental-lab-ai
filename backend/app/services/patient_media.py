"""Shared helpers for patient clinical media CRUD (scans / shades / smiles)."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services import patient_access as pa
from app.services.r2 import (
    PatientAssetKind,
    delete_patient_asset,
    upload_patient_asset,
)

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


def find_row_by_key(table: str, patient_id: str, file_key: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .select("*")
            .eq("patient_id", patient_id)
            .eq("file_key", file_key)
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


def update_row(table: str, row_id: str, patch: dict[str, Any]) -> dict[str, Any]:
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .update(patch)
            .eq("id", row_id)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Record not found",
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
    data: bytes,
    filename: str | None,
    content_type: str | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Store in R2, then insert the DB row — or, when this patient already has a
    row for the same bytes, update that row with `extra` instead of adding a
    duplicate. Rolls back the R2 object if a fresh insert fails."""
    file_key, file_url, file_name = upload_patient_asset(
        data=data,
        filename=filename,
        content_type=content_type,
        kind=kind,
        patient_id=patient_id,
    )
    existing = find_row_by_key(table, patient_id, file_key)
    if existing is not None:
        return update_row(table, str(existing["id"]), extra) if extra else existing

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
        inserted = insert_row(table, row)
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
    try:
        from app.services.notify import notify_clinical_upload

        notify_clinical_upload(
            pa.fetch_patient(patient_id),
            actor_id=user_id,
            kind=kind,
        )
    except Exception:
        logger.debug("clinical upload notify skipped kind=%s", kind, exc_info=True)
    return inserted


def delete_file_if_unused(
    *,
    table: str,
    kind: PatientAssetKind,
    patient_id: str,
    file_key: str,
    ignore_row_id: str | None = None,
) -> None:
    """Delete a file from the kind's bucket once no other row of `table` uses it.

    Only files in this patient's own `patients/{id}/{kind}/` folder are ever
    deleted — older rows pointing at a camera photo (`.../photos/...`) leave it
    to the camera photo's own lifecycle.
    """
    if not file_key.startswith(f"patients/{patient_id}/{kind}/"):
        if file_key:
            logger.warning("R2 delete skipped, outside %s folder key=%s", kind, file_key)
        return
    for other in list_rows(table, patient_id):
        if str(other.get("id")) == str(ignore_row_id):
            continue
        if file_key in (other.get("file_key"), other.get("base_file_key")):
            return
    delete_patient_asset(kind=kind, file_key=file_key)


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

    delete_file_if_unused(
        table=table,
        kind=kind,
        patient_id=patient_id,
        file_key=str(row.get("file_key") or ""),
        ignore_row_id=row_id,
    )
    delete_row(table, row_id)
    return row
