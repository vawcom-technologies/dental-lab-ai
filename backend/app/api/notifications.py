"""Notifications inbox API — dentist/lab in-app alerts (Supabase)."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.security import AuthUser, require_dentist
from app.core.supabase_client import get_supabase_admin
from app.services.patient_access import db_error, fetch_patient, patient_display_name

router = APIRouter()
logger = logging.getLogger("app.api.notifications")


def _missing_table(exc: Exception) -> bool:
    text = str(exc)
    return "PGRST205" in text or "public.notifications" in text


def _serialize(row: dict[str, Any]) -> dict[str, Any]:
    patient_id = str(row.get("patient_id") or "").strip() or None
    patient_name = None
    if patient_id:
        patient = fetch_patient(patient_id)
        if patient:
            patient_name = patient_display_name(patient)
    return {
        "id": str(row.get("id") or ""),
        "type": row.get("type") or "case_status",
        "message": row.get("message") or "",
        "read": bool(row.get("read")),
        "patient_id": patient_id,
        "patient_name": patient_name,
        "case_id": None,
        "case_status": None,
        "created_at": row.get("created_at"),
    }


@router.get("")
def list_notifications(
    unread_only: bool = Query(False),
    type: str | None = Query(None, description="message|case_status|scan_quality|…"),
    limit: int = Query(100, ge=1, le=200),
    user: AuthUser = Depends(require_dentist),
):
    try:
        q = (
            get_supabase_admin()
            .table("notifications")
            .select("*")
            .eq("user_id", user.id)
            .neq("type", "message")
            .order("created_at", desc=True)
            .limit(limit)
        )
        if unread_only:
            q = q.eq("read", False)
        if type:
            if type.strip().lower() == "message":
                return []
            q = q.eq("type", type)
        result = q.execute()
    except Exception as exc:
        if _missing_table(exc):
            logger.warning("notifications table missing — run migrations/010_notifications.sql")
            return []
        raise db_error(exc) from exc
    rows = list(getattr(result, "data", None) or [])
    return [_serialize(r) for r in rows]


@router.get("/unread-count")
def unread_count(user: AuthUser = Depends(require_dentist)):
    try:
        result = (
            get_supabase_admin()
            .table("notifications")
            .select("id", count="exact")
            .eq("user_id", user.id)
            .eq("read", False)
            .neq("type", "message")
            .execute()
        )
    except Exception as exc:
        if _missing_table(exc):
            logger.warning("notifications table missing — run migrations/010_notifications.sql")
            return {"count": 0}
        raise db_error(exc) from exc
    count = getattr(result, "count", None)
    if count is None:
        count = len(getattr(result, "data", None) or [])
    return {"count": int(count)}


@router.post("/{notification_id}/read")
def mark_read(
    notification_id: str,
    user: AuthUser = Depends(require_dentist),
):
    try:
        result = (
            get_supabase_admin()
            .table("notifications")
            .update({"read": True})
            .eq("id", notification_id)
            .eq("user_id", user.id)
            .select("id")
            .execute()
        )
    except Exception as exc:
        if _missing_table(exc):
            raise HTTPException(
                status_code=503,
                detail="Notifications are not set up yet. Run migrations/010_notifications.sql in Supabase.",
            ) from exc
        raise db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    if not rows:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"ok": True, "id": notification_id}


@router.post("/read-all")
def mark_all_read(user: AuthUser = Depends(require_dentist)):
    try:
        result = (
            get_supabase_admin()
            .table("notifications")
            .update({"read": True})
            .eq("user_id", user.id)
            .eq("read", False)
            .select("id")
            .execute()
        )
    except Exception as exc:
        if _missing_table(exc):
            return {"ok": True, "updated": 0}
        raise db_error(exc) from exc
    updated = len(getattr(result, "data", None) or [])
    return {"ok": True, "updated": updated}
