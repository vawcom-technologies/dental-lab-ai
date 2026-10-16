"""Lab membership: a dentist joining, leaving or moving between labs."""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services import case_status
from app.services import patient_access as pa


def _execute(query: Any) -> list[dict[str, Any]]:
    try:
        return list(getattr(query.execute(), "data", None) or [])
    except Exception as exc:
        raise pa.db_error(exc) from exc


def require_lab(lab_id: str) -> dict[str, Any]:
    rows = _execute(
        get_supabase_admin().table("profiles").select("*").eq("id", lab_id).limit(1)
    )
    lab = rows[0] if rows else None
    if (
        lab is None
        or lab.get("role") != "laboratory"
        or lab.get("anonymized_at")
        or lab.get("deleted")
        or lab.get("verified") is not True
    ):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lab not found")
    return lab


def _leave_lab(dentist_id: str, lab_id: str, actor_id: str | None) -> None:
    """Old lab loses open cases (under review → in progress); completed stay view-only."""
    patients = _execute(
        get_supabase_admin()
        .table("patients")
        .select("id,status")
        .eq("created_by", dentist_id)
        .eq("deleted", False)
    )
    open_ids = []
    for p in patients:
        if p.get("status") == "completed":
            continue
        open_ids.append(str(p["id"]))
        if p.get("status") == "in_review":
            case_status.set_status(p, "in_progress", actor_id=actor_id, type="lab_left")
    if open_ids:
        _execute(
            get_supabase_admin()
            .table("patient_access")
            .delete()
            .eq("user_id", lab_id)
            .in_("patient_id", open_ids)
        )


def set_lab(
    dentist: dict[str, Any],
    lab_id: str | None,
    *,
    actor_id: str | None,
    reason: str = "removed",
) -> dict[str, Any]:
    """Move a dentist to `lab_id`, or out of their lab (None) with `reason`:
    no_lab | removed | lab_deleted."""
    old = dentist.get("lab_id")
    if old == lab_id:
        return dentist
    if old:
        _leave_lab(str(dentist["id"]), str(old), actor_id)
    now = pa.utc_now_iso()
    patch = {
        "lab_id": lab_id,
        "unassigned_reason": None if lab_id else reason,
        "unassigned_at": None if lab_id else now,
        "updated_at": now,
    }
    rows = _execute(
        get_supabase_admin().table("profiles").update(patch).eq("id", str(dentist["id"]))
    )
    return rows[0] if rows else {**dentist, **patch}
