"""Patient case status changes and the case history (public.case_events).

Every status change goes through set_status so it is always logged.
"""

from __future__ import annotations

from typing import Any

from app.core.supabase_client import get_supabase_admin
from app.services import patient_access as pa

STATUSES = ("pending", "in_progress", "in_review", "completed", "rejected")


def log_event(
    patient_id: str,
    *,
    actor_id: str | None,
    type: str,
    from_status: str | None = None,
    to_status: str | None = None,
    remarks: str | None = None,
) -> None:
    row = {
        "patient_id": patient_id,
        "actor_id": actor_id,
        "type": type,
        "from_status": from_status,
        "to_status": to_status,
        "remarks": remarks,
    }
    try:
        get_supabase_admin().table("case_events").insert(row).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc


def set_status(
    patient: dict[str, Any],
    to_status: str,
    *,
    actor_id: str | None,
    type: str,
    remarks: str | None = None,
    auto_submit: bool | None = None,
) -> dict[str, Any]:
    """Update patients.status (and optionally auto_submit), then log the event."""
    pid = str(patient["id"])
    patch: dict[str, Any] = {"status": to_status, "updated_at": pa.utc_now_iso()}
    if auto_submit is not None:
        patch["auto_submit"] = auto_submit
    try:
        result = get_supabase_admin().table("patients").update(patch).eq("id", pid).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc
    log_event(
        pid,
        actor_id=actor_id,
        type=type,
        from_status=patient.get("status"),
        to_status=to_status,
        remarks=remarks,
    )
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else {**patient, **patch}
