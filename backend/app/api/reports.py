"""Clinic reports summary — Supabase-backed analytics for the Reports page.

Returns the same JSON shape the Flutter Reports UI already expects.
Case pipeline fields are derived from appointments (current work queue);
clinical coverage is patient-media based (scans / photos / shade / smile).
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Query

from app.core.security import AuthUser, require_dentist
from app.core.supabase_client import get_supabase_admin
from app.services import patient_access as pa

logger = logging.getLogger("app.api.reports")

router = APIRouter()

_CASE_STATUSES = ("pending", "in_progress", "in_review", "completed", "rejected")

# Appointment status → Reports pipeline status (legacy UI labels).
_APPT_TO_CASE = {
    "scheduled": "pending",
    "confirmed": "in_progress",
    "completed": "completed",
    "cancelled": "rejected",
    "no_show": "rejected",
}


def _parse_dt(raw: Any) -> datetime | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        dt = raw
    else:
        text = str(raw).strip()
        if not text:
            return None
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _week_start(dt: datetime) -> datetime:
    local = dt.astimezone(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return local - timedelta(days=local.weekday())


def _accessible_patients(user_id: str) -> list[dict[str, Any]]:
    try:
        owned = (
            get_supabase_admin()
            .table("patients")
            .select("*")
            .eq("created_by", user_id)
            .eq("deleted", False)
            .execute()
        )
        shared_ids_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("patient_id")
            .eq("user_id", user_id)
            .eq("status", "approved")
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc

    rows = list(getattr(owned, "data", None) or [])
    seen = {str(r.get("id")) for r in rows}
    shared_ids = [
        str(r["patient_id"])
        for r in (getattr(shared_ids_res, "data", None) or [])
        if str(r.get("patient_id")) not in seen
    ]
    if shared_ids:
        try:
            shared = (
                get_supabase_admin()
                .table("patients")
                .select("*")
                .in_("id", shared_ids)
                .eq("deleted", False)
                .execute()
            )
            rows.extend(getattr(shared, "data", None) or [])
        except Exception as exc:
            raise pa.db_error(exc) from exc
    return rows


def _fetch_rows_for_patients(
    table: str, patient_ids: list[str], columns: str = "*"
) -> list[dict[str, Any]]:
    if not patient_ids:
        return []
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .select(columns)
            .in_("patient_id", patient_ids)
            .execute()
        )
    except Exception as exc:
        logger.warning("reports: %s query failed: %s", table, exc)
        return []
    return list(getattr(result, "data", None) or [])


def _patient_name(row: dict[str, Any]) -> str:
    name = f"{row.get('first_name') or ''} {row.get('last_name') or ''}".strip()
    return name or f"Patient #{row.get('id')}"


def _message_stats(user_id: str) -> tuple[int, int]:
    """Return (threads_with_messages, unread)."""
    try:
        as_a = (
            get_supabase_admin()
            .table("conversations")
            .select("id")
            .eq("user_a", user_id)
            .execute()
        )
        as_b = (
            get_supabase_admin()
            .table("conversations")
            .select("id")
            .eq("user_b", user_id)
            .execute()
        )
    except Exception as exc:
        logger.warning("reports: conversations query failed: %s", exc)
        return 0, 0

    conv_ids = [
        str(r["id"])
        for r in (getattr(as_a, "data", None) or [])
        + (getattr(as_b, "data", None) or [])
    ]
    if not conv_ids:
        return 0, 0

    unread = 0
    threads = 0
    for cid in conv_ids:
        try:
            msgs = (
                get_supabase_admin()
                .table("messages")
                .select("id,sender_id,read_at")
                .eq("conversation_id", cid)
                .limit(200)
                .execute()
            )
        except Exception:
            continue
        rows = getattr(msgs, "data", None) or []
        if not rows:
            continue
        threads += 1
        for m in rows:
            if str(m.get("sender_id")) != user_id and not m.get("read_at"):
                unread += 1
    return threads, unread


@router.get("/summary")
def clinic_summary(
    days: int = Query(
        default=30,
        ge=0,
        le=3650,
        description="Lookback window in days. Pass 0 for all-time.",
    ),
    user: AuthUser = Depends(require_dentist),
):
    """Aggregate clinic KPIs for the Reports page."""
    all_time = days == 0
    now = datetime.now(timezone.utc)
    since = None if all_time else now - timedelta(days=days)

    patients = _accessible_patients(user.id)
    patient_ids = [str(p["id"]) for p in patients if p.get("id")]
    patients_by_id = {str(p["id"]): p for p in patients}

    patients_new = 0
    if since is not None:
        for p in patients:
            created = _parse_dt(p.get("created_at"))
            if created and created >= since:
                patients_new += 1

    appointments = _fetch_rows_for_patients("appointments", patient_ids)
    scans = _fetch_rows_for_patients(
        "patient_scans", patient_ids, "id,patient_id,created_at"
    )
    photos = _fetch_rows_for_patients(
        "patient_photos", patient_ids, "id,patient_id,created_at"
    )
    shades = _fetch_rows_for_patients(
        "shade_detections", patient_ids, "id,patient_id,created_at"
    )
    smiles = _fetch_rows_for_patients(
        "smile_previews", patient_ids, "id,patient_id,created_at"
    )

    by_status = {s: 0 for s in _CASE_STATUSES}
    created_in_period = 0
    completed_in_period = 0
    processing_hours: list[float] = []
    week_created: dict[str, int] = defaultdict(int)
    week_completed: dict[str, int] = defaultdict(int)

    for appt in appointments:
        status = _APPT_TO_CASE.get(
            str(appt.get("status") or "").strip().lower(), "pending"
        )
        by_status[status] = by_status.get(status, 0) + 1

        created = _parse_dt(appt.get("created_at")) or _parse_dt(appt.get("start_time"))
        updated = _parse_dt(appt.get("updated_at")) or _parse_dt(appt.get("end_time"))

        if created is not None:
            if since is None or created >= since:
                created_in_period += 1
            wk = _week_start(created).date().isoformat()
            if since is None or created >= since:
                week_created[wk] += 1

        if status == "completed" and created is not None and updated is not None:
            hours = (updated - created).total_seconds() / 3600.0
            if hours >= 0:
                processing_hours.append(hours)
            if since is None or updated >= since:
                completed_in_period += 1
                week_completed[_week_start(updated).date().isoformat()] += 1

    total_cases = len(appointments)
    rejected = by_status.get("rejected", 0)
    rejection_rate = (rejected / total_cases) if total_cases else 0.0
    avg_hours = (
        sum(processing_hours) / len(processing_hours) if processing_hours else None
    )

    patients_with_scans = {str(r["patient_id"]) for r in scans if r.get("patient_id")}
    patients_with_photos = {str(r["patient_id"]) for r in photos if r.get("patient_id")}
    patients_with_shade = {str(r["patient_id"]) for r in shades if r.get("patient_id")}
    patients_with_shape = {str(r["patient_id"]) for r in smiles if r.get("patient_id")}

    covered = (
        patients_with_scans
        | patients_with_shade
        | patients_with_shape
        | patients_with_photos
    )
    coverage_pct = (
        round(len(covered) / len(patient_ids) * 100, 1) if patient_ids else 0.0
    )

    # Weekly throughput buckets
    weeks: list[dict[str, Any]] = []
    if all_time:
        keys = sorted(set(week_created) | set(week_completed))
        if len(keys) > 8:
            keys = keys[-8:]
        if not keys:
            start = _week_start(now) - timedelta(weeks=7)
            keys = [(start + timedelta(weeks=i)).date().isoformat() for i in range(8)]
        for k in keys:
            weeks.append(
                {
                    "week_start": k,
                    "created": week_created.get(k, 0),
                    "completed": week_completed.get(k, 0),
                }
            )
    else:
        start = _week_start(since or now)
        end = _week_start(now)
        cur = start
        while cur <= end:
            k = cur.date().isoformat()
            weeks.append(
                {
                    "week_start": k,
                    "created": week_created.get(k, 0),
                    "completed": week_completed.get(k, 0),
                }
            )
            cur += timedelta(weeks=1)
        if len(weeks) > 12:
            weeks = weeks[-12:]

    # Attention queue — open appointments + patients missing clinical work
    attention: list[dict[str, Any]] = []
    open_statuses = {"pending", "in_progress", "in_review"}
    for appt in sorted(
        appointments,
        key=lambda a: _parse_dt(a.get("updated_at"))
        or _parse_dt(a.get("start_time"))
        or datetime(1970, 1, 1, tzinfo=timezone.utc),
        reverse=True,
    ):
        status = _APPT_TO_CASE.get(
            str(appt.get("status") or "").strip().lower(), "pending"
        )
        if status not in open_statuses and status != "rejected":
            continue
        pid = str(appt.get("patient_id") or "")
        p = patients_by_id.get(pid) or {}
        attention.append(
            {
                "case_id": str(appt.get("id") or ""),
                "patient_id": pid,
                "patient_name": _patient_name(p) if p else f"Patient #{pid}",
                "status": status,
                "updated_at": appt.get("updated_at") or appt.get("start_time"),
                "created_at": appt.get("created_at") or appt.get("start_time"),
                "has_scan": pid in patients_with_scans,
                "has_shade": pid in patients_with_shade,
                "has_shape": pid in patients_with_shape,
                "has_scan_body": False,
            }
        )
        if len(attention) >= 12:
            break

    # Top patients by appointment volume (fallback: clinical asset count)
    appt_count: dict[str, int] = defaultdict(int)
    for appt in appointments:
        pid = str(appt.get("patient_id") or "")
        if pid:
            appt_count[pid] += 1
    if not appt_count:
        for pid in patient_ids:
            score = (
                (1 if pid in patients_with_scans else 0)
                + (1 if pid in patients_with_photos else 0)
                + (1 if pid in patients_with_shade else 0)
                + (1 if pid in patients_with_shape else 0)
            )
            if score:
                appt_count[pid] = score

    top_patients: list[dict[str, Any]] = []
    for pid, count in sorted(appt_count.items(), key=lambda x: x[1], reverse=True)[:8]:
        p = patients_by_id.get(pid)
        if not p:
            continue
        top_patients.append(
            {
                "patient_id": pid,
                "name": _patient_name(p),
                "cases": count,
                "health_insurance": p.get("health_insurance"),
            }
        )

    threads, unread = _message_stats(user.id)
    active = (
        by_status["pending"]
        + by_status["in_progress"]
        + by_status["in_review"]
        + by_status["rejected"]
    )

    return {
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "period_days": None if all_time else (days or 30),
        "clinic_name": user.clinic_name,
        "dentist_name": user.name,
        "patients": {
            "total": len(patients),
            "new_in_period": patients_new,
        },
        "cases": {
            "total": total_cases,
            "active": active,
            "created_in_period": created_in_period,
            "completed_in_period": completed_in_period,
            "by_status": by_status,
            "avg_processing_hours": round(avg_hours, 1)
            if avg_hours is not None
            else None,
            "rejection_rate": round(rejection_rate, 4),
        },
        "clinical": {
            # Keys keep legacy names; values are patient coverage counts.
            "cases_with_scans": len(patients_with_scans),
            "cases_with_photos": len(patients_with_photos),
            "cases_with_shade": len(patients_with_shade),
            "cases_with_shape": len(patients_with_shape),
            "cases_with_scan_body": 0,
            "total_scans": len(scans),
            "total_photos": len(photos),
            "total_shade_saves": len(shades),
            "coverage_pct": coverage_pct,
        },
        "messages": {
            "threads_with_messages": threads,
            "unread": unread,
        },
        "notifications": {
            "total": 0,
            "unread": 0,
        },
        "throughput": weeks,
        "attention": attention,
        "top_patients": top_patients,
    }
