"""Create in-app notifications for clinic / lab users (Supabase).

Never raises to callers — a missed inbox row must not fail the clinical action.
"""

from __future__ import annotations

import logging
from typing import Any

from app.core.supabase_client import get_supabase_admin
from app.services.patient_access import patient_display_name as _patient_name
from app.services.profiles import fetch_profile

logger = logging.getLogger("app.notify")

ALLOWED_TYPES = {
    "case_status",
    "scan_quality",
    "shade",
    "scan_body",
    "sync",
    "export",
    "appointment",
}


def patient_display_name(patient: Any | None) -> str:
    """Name from a Supabase patient dict or a legacy SQLAlchemy Patient."""
    if patient is None:
        return "Patient"
    if isinstance(patient, dict):
        return _patient_name(patient)
    name = f"{getattr(patient, 'first_name', '') or ''} {getattr(patient, 'last_name', '') or ''}".strip()
    return name or "Patient"


def actor_label(user_id: str | None, *, fallback: str = "A colleague") -> str:
    if not user_id:
        return fallback
    profile = fetch_profile(user_id)
    if not profile:
        return fallback
    name = str(profile.get("name") or "").strip()
    if name:
        return name
    email = str(profile.get("email") or "").strip()
    return email or fallback


def notify(
    *,
    user_id: str | None,
    type: str,
    message: str,
    patient_id: str | None = None,
    actor_id: str | None = None,
    allow_self: bool = False,
) -> dict[str, Any] | None:
    """Insert one inbox row. Skips self-notify unless [allow_self]. Returns the row or None."""
    uid = str(user_id or "").strip()
    if not uid:
        return None
    if not allow_self and actor_id and str(actor_id) == uid:
        return None
    # Chat already has its own inbox — never write message rows here.
    if (type or "").strip().lower() == "message":
        return None
    ntype = type if type in ALLOWED_TYPES else "case_status"
    text = (message or "").strip()
    if not text:
        return None
    row: dict[str, Any] = {
        "user_id": uid,
        "type": ntype,
        "message": text[:512],
        "read": False,
    }
    pid = str(patient_id or "").strip()
    if pid:
        row["patient_id"] = pid
    try:
        result = get_supabase_admin().table("notifications").insert(row).execute()
    except Exception as exc:
        logger.warning(
            "notify failed user_id=%s type=%s detail=%s",
            uid,
            ntype,
            exc,
        )
        return None
    rows = getattr(result, "data", None) or []
    if not rows:
        logger.warning("notify insert returned no row user_id=%s type=%s", uid, ntype)
        return None
    logger.info("notify ok user_id=%s type=%s", uid, ntype)
    return rows[0]


def notify_pair(
    *,
    counterpart_id: str | None,
    actor_id: str,
    type: str,
    counterpart_message: str,
    actor_message: str,
    patient_id: str | None = None,
) -> None:
    """Inbox row for the other party, plus an activity row for the actor."""
    notify(
        user_id=counterpart_id,
        type=type,
        message=counterpart_message,
        patient_id=patient_id,
        actor_id=actor_id,
    )
    notify(
        user_id=actor_id,
        type=type,
        message=actor_message,
        patient_id=patient_id,
        actor_id=actor_id,
        allow_self=True,
    )


def notify_patient_owner(
    patient: dict[str, Any] | None,
    *,
    actor_id: str,
    type: str,
    message: str,
) -> dict[str, Any] | None:
    """Tell the record owner unless they performed the action themselves."""
    if not patient:
        return None
    owner = str(patient.get("created_by") or "").strip()
    pid = str(patient.get("id") or "").strip() or None
    return notify(
        user_id=owner,
        type=type,
        message=message,
        patient_id=pid,
        actor_id=actor_id,
    )


def notify_clinical_upload(
    patient: dict[str, Any] | None,
    *,
    actor_id: str,
    kind: str,
) -> dict[str, Any] | None:
    """Shared-user upload of scan / shade / smile → owner inbox."""
    name = patient_display_name(patient)
    who = actor_label(actor_id)
    if kind == "scans":
        ntype, msg = "scan_quality", f"{who} uploaded a 3D scan for {name}."
    elif kind == "shades":
        ntype, msg = "shade", f"{who} saved a shade photo for {name}."
    elif kind == "smiles":
        ntype, msg = "shade", f"{who} saved a smile preview for {name}."
    else:
        ntype, msg = "case_status", f"{who} added a file for {name}."
    return notify_patient_owner(
        patient,
        actor_id=actor_id,
        type=ntype,
        message=msg,
    )


# Legacy case-based helpers — kept so unmounted routers still import.
def notify_case_dentist(*_a: Any, **_k: Any) -> None:
    logger.debug("notify_case_dentist skipped (legacy cases API)")
    return None


def notify_lab_users(*_a: Any, **_k: Any) -> list:
    logger.debug("notify_lab_users skipped (legacy cases API)")
    return []


def notify_status_change(*_a: Any, **_k: Any) -> None:
    logger.debug("notify_status_change skipped (legacy cases API)")
    return None
