"""Patient appointments CRUD + Resend email notifications."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_appointments import (
    AppointmentCreate,
    AppointmentResponse,
    AppointmentUpdate,
)
from app.services import patient_access as pa
from app.services.email import send_appointment_confirmation, send_appointment_update

router = APIRouter()
logger = logging.getLogger("app.api.appointments")

_ACTIVE_STATUSES = ("scheduled", "confirmed")


def _patient_display_name(patient: dict[str, Any]) -> str:
    first = (patient.get("first_name") or "").strip()
    last = (patient.get("last_name") or "").strip()
    return f"{first} {last}".strip() or "Patient"


def _to_iso(value: datetime | str) -> str:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    return str(value)


def _serialize(row: dict[str, Any], patient: dict[str, Any]) -> AppointmentResponse:
    email = str(patient.get("email") or "").strip()
    if not email:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Patient email is required for appointment responses",
        )
    return AppointmentResponse(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        created_by=str(row["created_by"]),
        description=str(row.get("description") or ""),
        start_time=row.get("start_time"),
        end_time=row.get("end_time"),
        status=row.get("status") or "scheduled",
        reminder_sent=bool(row.get("reminder_sent") or False),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
        patient_name=_patient_display_name(patient),
        patient_email=email,
    )


def _accessible_patient_ids(user_id: str) -> list[str]:
    try:
        owned = (
            get_supabase_admin()
            .table("patients")
            .select("id")
            .eq("created_by", user_id)
            .eq("deleted", False)
            .execute()
        )
        shared = (
            get_supabase_admin()
            .table("patient_access")
            .select("patient_id")
            .eq("user_id", user_id)
            .eq("status", "approved")
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc

    ids = {str(r["id"]) for r in (getattr(owned, "data", None) or [])}
    ids.update(str(r["patient_id"]) for r in (getattr(shared, "data", None) or []))
    return list(ids)


def _fetch_appointment(appointment_id: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table("appointments")
            .select("*")
            .eq("id", appointment_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def _require_appointment_access(
    appointment: dict[str, Any], user_id: str
) -> dict[str, Any]:
    patient_id = str(appointment.get("patient_id") or "")
    return pa.require_patient_access(patient_id, user_id)


def _has_overlap(
    *,
    dentist_id: str,
    start_time: str,
    end_time: str,
    exclude_id: str | None = None,
) -> bool:
    """True if dentist already has an active appointment overlapping [start, end)."""
    try:
        result = (
            get_supabase_admin()
            .table("appointments")
            .select("id,start_time,end_time,status")
            .eq("created_by", dentist_id)
            .in_("status", list(_ACTIVE_STATUSES))
            .lt("start_time", end_time)
            .gt("end_time", start_time)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc

    for row in getattr(result, "data", None) or []:
        if exclude_id and str(row.get("id")) == exclude_id:
            continue
        return True
    return False


def _fetch_patients_map(patient_ids: list[str]) -> dict[str, dict[str, Any]]:
    if not patient_ids:
        return {}
    try:
        result = (
            get_supabase_admin()
            .table("patients")
            .select("id,first_name,last_name,email")
            .in_("id", patient_ids)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    return {str(r["id"]): r for r in (getattr(result, "data", None) or [])}


@router.get(
    "",
    response_model=list[AppointmentResponse],
    summary="List accessible appointments",
)
def list_appointments(
    status_filter: str | None = Query(default=None, alias="status"),
    patient_id: UUID | None = Query(default=None),
    upcoming_only: bool = Query(default=True),
    user: AuthUser = Depends(get_current_user),
):
    accessible = _accessible_patient_ids(user.id)
    if not accessible:
        return []

    if patient_id is not None:
        pid = str(patient_id)
        if pid not in accessible:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this patient",
            )
        patient_filter = [pid]
    else:
        patient_filter = accessible

    now_iso = datetime.now(timezone.utc).isoformat()
    try:
        query = (
            get_supabase_admin()
            .table("appointments")
            .select("*")
            .in_("patient_id", patient_filter)
        )
        if status_filter:
            query = query.eq("status", status_filter.strip().lower())
        if upcoming_only:
            query = query.gte("start_time", now_iso).order("start_time", desc=False)
        else:
            query = query.order("start_time", desc=True)
        result = query.execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    patients = _fetch_patients_map([str(r["patient_id"]) for r in rows])
    out: list[AppointmentResponse] = []
    for row in rows:
        patient = patients.get(str(row["patient_id"])) or {}
        if not str(patient.get("email") or "").strip():
            continue
        out.append(_serialize(row, patient))
    return out


@router.post(
    "",
    response_model=AppointmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create appointment and email confirmation",
)
def create_appointment(
    payload: AppointmentCreate,
    background_tasks: BackgroundTasks,
    user: AuthUser = Depends(get_current_user),
):
    patient_id = str(payload.patient_id)
    patient = pa.require_patient_access(patient_id, user.id)
    patient_email = str(patient.get("email") or "").strip()
    if not patient_email:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Patient email is required before scheduling an appointment",
        )

    start_iso = _to_iso(payload.start_time)
    end_iso = _to_iso(payload.end_time)
    if _has_overlap(dentist_id=user.id, start_time=start_iso, end_time=end_iso):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Overlapping active appointment exists for this time window",
        )

    description = (payload.description or "").strip()
    now = pa.utc_now_iso()
    row = {
        "patient_id": patient_id,
        "created_by": user.id,
        "description": description,
        "start_time": start_iso,
        "end_time": end_iso,
        "status": "scheduled",
        "reminder_sent": False,
        "created_at": now,
        "updated_at": now,
    }
    try:
        result = get_supabase_admin().table("appointments").insert(row).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc

    created = (getattr(result, "data", None) or [None])[0]
    if not created:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Appointment insert returned no row",
        )

    patient_name = _patient_display_name(patient)
    background_tasks.add_task(
        send_appointment_confirmation,
        patient_email,
        patient_name,
        created.get("start_time") or start_iso,
        created.get("end_time") or end_iso,
        description,
    )
    logger.debug(
        "appointment created id=%s patient_id=%s user_id=%s",
        created.get("id"),
        patient_id,
        user.id,
    )
    return _serialize(created, patient)


@router.patch(
    "/{appointment_id}",
    response_model=AppointmentResponse,
    summary="Update appointment and email patient",
)
def update_appointment(
    appointment_id: str,
    payload: AppointmentUpdate,
    background_tasks: BackgroundTasks,
    user: AuthUser = Depends(get_current_user),
):
    existing = _fetch_appointment(appointment_id)
    if existing is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Appointment not found",
        )
    patient = _require_appointment_access(existing, user.id)
    patient_email = str(patient.get("email") or "").strip()
    if not patient_email:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Patient email is required",
        )

    updates: dict[str, Any] = {}
    if payload.description is not None:
        updates["description"] = payload.description.strip()
    if payload.start_time is not None:
        updates["start_time"] = _to_iso(payload.start_time)
    if payload.end_time is not None:
        updates["end_time"] = _to_iso(payload.end_time)
    if payload.status is not None:
        updates["status"] = payload.status

    if not updates:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )

    new_start = updates.get("start_time") or existing.get("start_time")
    new_end = updates.get("end_time") or existing.get("end_time")
    try:
        start_dt = datetime.fromisoformat(str(new_start).replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(str(new_end).replace("Z", "+00:00"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid start_time or end_time",
        ) from exc
    if end_dt <= start_dt:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end_time must be after start_time",
        )

    # Overlap check only when still (or becoming) an active status
    new_status = updates.get("status") or existing.get("status") or "scheduled"
    if new_status in _ACTIVE_STATUSES and _has_overlap(
        dentist_id=user.id,
        start_time=_to_iso(start_dt),
        end_time=_to_iso(end_dt),
        exclude_id=appointment_id,
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Overlapping active appointment exists for this time window",
        )

    updates["updated_at"] = pa.utc_now_iso()
    try:
        result = (
            get_supabase_admin()
            .table("appointments")
            .update(updates)
            .eq("id", appointment_id)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    updated = rows[0] if rows else {**existing, **updates}

    background_tasks.add_task(
        send_appointment_update,
        patient_email,
        _patient_display_name(patient),
        updated.get("start_time"),
        updated.get("end_time"),
        updated.get("status") or "scheduled",
        updated.get("description") or "",
    )
    return _serialize(updated, patient)


@router.delete(
    "/{appointment_id}",
    status_code=status.HTTP_200_OK,
    summary="Delete appointment",
)
def delete_appointment(
    appointment_id: str,
    user: AuthUser = Depends(get_current_user),
):
    existing = _fetch_appointment(appointment_id)
    if existing is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Appointment not found",
        )
    _require_appointment_access(existing, user.id)
    try:
        get_supabase_admin().table("appointments").delete().eq(
            "id", appointment_id
        ).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc

    return {"deleted": True, "id": appointment_id}
