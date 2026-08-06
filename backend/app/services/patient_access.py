"""Patient ownership, shared access checks, and GDPR audit logging."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin

logger = logging.getLogger("app.patient_access")

OWNER_EDIT_DENIED = (
    "ERROR_403_FORBIDDEN: Permission denied. Only the user who created this "
    "patient record is authorized to edit it."
)
OWNER_ONLY_DENIED = (
    "ERROR_403_FORBIDDEN: Permission denied. Only the patient record owner "
    "may perform this action."
)
ACCESS_DENIED = (
    "ERROR_403_FORBIDDEN: Permission denied. You do not have access to this patient."
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


def fetch_patient(patient_id: str, *, include_deleted: bool = False) -> dict[str, Any] | None:
    try:
        q = (
            get_supabase_admin()
            .table("patients")
            .select("*")
            .eq("id", patient_id)
            .limit(1)
        )
        if not include_deleted:
            q = q.eq("deleted", False)
        result = q.execute()
    except Exception as exc:
        raise db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def is_owner(patient: dict[str, Any], user_id: str) -> bool:
    return str(patient.get("created_by")) == str(user_id)


def has_shared_access(patient_id: str, user_id: str) -> bool:
    try:
        result = (
            get_supabase_admin()
            .table("patient_access")
            .select("id")
            .eq("patient_id", patient_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise db_error(exc) from exc
    return bool(getattr(result, "data", None))


def has_patient_access(patient_id: str, user_id: str) -> bool:
    patient = fetch_patient(patient_id)
    if patient is None:
        return False
    if is_owner(patient, user_id):
        return True
    return has_shared_access(patient_id, user_id)


def require_owner(patient: dict[str, Any], user_id: str, *, message: str = OWNER_ONLY_DENIED) -> None:
    if not is_owner(patient, user_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=message)


def require_patient_access(patient_id: str, user_id: str) -> dict[str, Any]:
    patient = fetch_patient(patient_id)
    if patient is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found",
        )
    if is_owner(patient, user_id) or has_shared_access(patient_id, user_id):
        return patient
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=ACCESS_DENIED)


def write_audit_log(
    *,
    actor_id: str,
    action: str,
    patient_id: str | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    """Append an immutable audit row. Never include plaintext clinical notes."""
    safe_details = dict(details or {})
    for banned in ("note_content", "new_note_content", "plaintext", "note_ciphertext"):
        safe_details.pop(banned, None)

    row: dict[str, Any] = {
        "actor_id": actor_id,
        "action": action,
        "details": safe_details,
        "created_at": utc_now_iso(),
    }
    if patient_id:
        row["patient_id"] = patient_id

    try:
        get_supabase_admin().table("patient_audit_logs").insert(row).execute()
    except Exception as exc:
        # Audit failure must not silently succeed a mutation — surface it
        logger.exception("audit log write failed action=%s", action)
        raise db_error(exc) from exc
