"""Clinic reports / analytics summary for the dentist dashboard."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import (
    User,
    Patient,
    Case,
    Scan,
    Photo,
    ShadeSelection,
    ShapeSelection,
    ScanBodySelection,
    Message,
    Notification,
)

router = APIRouter()

_STATUSES = ("pending", "in_progress", "in_review", "completed", "rejected")


def _normalize_status(raw: str | None) -> str:
    s = (raw or "pending").strip().lower()
    if s == "awaiting_scan":
        return "pending"
    if s == "complete":
        return "completed"
    if s in _STATUSES:
        return s
    return "pending"


def _dentist_patient_ids(db: Session, user: User) -> set[int] | None:
    if user.role == "lab":
        return None
    rows = db.query(Patient.id).filter(Patient.dentist_id == user.id).all()
    return {r[0] for r in rows}


def _week_start(dt: datetime) -> datetime:
    local = dt.replace(hour=0, minute=0, second=0, microsecond=0)
    return local - timedelta(days=local.weekday())


@router.get("/summary")
def clinic_summary(
    days: int = Query(
        default=30,
        ge=0,
        le=3650,
        description="Lookback window in days. Pass 0 for all-time.",
    ),
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    """Aggregate clinic KPIs, pipeline, clinical AI coverage, and weekly throughput."""
    # days=0 means all-time (handy for Flutter "All" chip)
    all_time = days == 0
    now = datetime.utcnow()
    since = None if all_time else now - timedelta(days=days)

    allowed = _dentist_patient_ids(db, user)
    patients_q = db.query(Patient)
    cases_q = db.query(Case)
    if allowed is not None:
        patients_q = patients_q.filter(Patient.id.in_(allowed or {-1}))
        cases_q = cases_q.filter(Case.patient_id.in_(allowed or {-1}))

    patients = patients_q.all()
    cases = cases_q.all()
    case_ids = {c.id for c in cases}

    patients_new = 0
    if since is not None:
        patients_new = sum(1 for p in patients if p.created_at and p.created_at >= since)

    by_status = {s: 0 for s in _STATUSES}
    created_in_period = 0
    completed_in_period = 0
    processing_hours: list[float] = []
    week_created: dict[str, int] = defaultdict(int)
    week_completed: dict[str, int] = defaultdict(int)

    for c in cases:
        status = _normalize_status(c.status)
        by_status[status] = by_status.get(status, 0) + 1

        if c.created_at:
            if since is None or c.created_at >= since:
                created_in_period += 1
            wk = _week_start(c.created_at).date().isoformat()
            if since is None or c.created_at >= since:
                week_created[wk] += 1

        if status == "completed" and c.created_at and c.updated_at:
            hours = (c.updated_at - c.created_at).total_seconds() / 3600.0
            if hours >= 0:
                processing_hours.append(hours)
            if since is None or c.updated_at >= since:
                completed_in_period += 1
                wk = _week_start(c.updated_at).date().isoformat()
                week_completed[wk] += 1

    total_cases = len(cases)
    rejected = by_status.get("rejected", 0)
    rejection_rate = (rejected / total_cases) if total_cases else 0.0
    avg_hours = (
        sum(processing_hours) / len(processing_hours) if processing_hours else None
    )

    # Clinical coverage (distinct cases with at least one artifact)
    def _case_ids_with(model) -> set[int]:
        if not case_ids:
            return set()
        rows = (
            db.query(model.case_id)
            .filter(model.case_id.in_(case_ids))
            .distinct()
            .all()
        )
        return {r[0] for r in rows}

    cases_with_scans = _case_ids_with(Scan)
    cases_with_photos = _case_ids_with(Photo)
    cases_with_shade = _case_ids_with(ShadeSelection)
    cases_with_shape = _case_ids_with(ShapeSelection)
    cases_with_scan_body = _case_ids_with(ScanBodySelection)

    total_scans = 0
    total_photos = 0
    total_shades = 0
    if case_ids:
        total_scans = (
            db.query(func.count(Scan.id)).filter(Scan.case_id.in_(case_ids)).scalar()
            or 0
        )
        total_photos = (
            db.query(func.count(Photo.id)).filter(Photo.case_id.in_(case_ids)).scalar()
            or 0
        )
        total_shades = (
            db.query(func.count(ShadeSelection.id))
            .filter(ShadeSelection.case_id.in_(case_ids))
            .scalar()
            or 0
        )

    # Messages / notifications
    unread_messages = 0
    threads_with_messages = 0
    if case_ids:
        msg_rows = (
            db.query(Message.case_id, Message.read_at, Message.sender_id)
            .filter(Message.case_id.in_(case_ids))
            .all()
        )
        by_case: dict[int, list] = defaultdict(list)
        for row in msg_rows:
            by_case[row.case_id].append(row)
        threads_with_messages = len(by_case)
        for rows in by_case.values():
            for m in rows:
                if m.read_at is None and m.sender_id != user.id:
                    unread_messages += 1

    notif_q = db.query(Notification).filter(Notification.user_id == user.id)
    notifications_total = notif_q.count()
    notifications_unread = notif_q.filter(Notification.read.is_(False)).count()

    # Weekly throughput buckets (last 8 weeks intersecting the window)
    weeks: list[dict] = []
    if all_time:
        # Use up to last 8 calendar weeks that have any activity, else last 8 weeks
        keys = sorted(set(week_created) | set(week_completed))
        if len(keys) > 8:
            keys = keys[-8:]
        if not keys:
            start = _week_start(now) - timedelta(weeks=7)
            keys = [
                (start + timedelta(weeks=i)).date().isoformat() for i in range(8)
            ]
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

    # Attention queue — open / rejected cases newest first
    attention_statuses = {"pending", "in_progress", "in_review", "rejected"}
    patients_by_id = {p.id: p for p in patients}
    attention = []
    for c in sorted(
        cases,
        key=lambda x: x.updated_at or datetime(1970, 1, 1),
        reverse=True,
    ):
        st = _normalize_status(c.status)
        if st not in attention_statuses:
            continue
        p = patients_by_id.get(c.patient_id)
        name = (
            f"{p.first_name} {p.last_name}".strip()
            if p
            else f"Patient #{c.patient_id}"
        )
        attention.append(
            {
                "case_id": c.id,
                "patient_id": c.patient_id,
                "patient_name": name,
                "status": st,
                "updated_at": c.updated_at.isoformat() if c.updated_at else None,
                "created_at": c.created_at.isoformat() if c.created_at else None,
                "has_scan": c.id in cases_with_scans,
                "has_shade": c.id in cases_with_shade,
                "has_shape": c.id in cases_with_shape,
                "has_scan_body": c.id in cases_with_scan_body,
            }
        )
        if len(attention) >= 12:
            break

    # Top patients by case volume
    case_count_by_patient: dict[int, int] = defaultdict(int)
    for c in cases:
        case_count_by_patient[c.patient_id] += 1
    top_patients = []
    for pid, count in sorted(
        case_count_by_patient.items(), key=lambda x: x[1], reverse=True
    )[:8]:
        p = patients_by_id.get(pid)
        if not p:
            continue
        top_patients.append(
            {
                "patient_id": pid,
                "name": f"{p.first_name} {p.last_name}".strip(),
                "cases": count,
                "health_insurance": p.health_insurance,
            }
        )

    active = (
        by_status["pending"]
        + by_status["in_progress"]
        + by_status["in_review"]
        + by_status["rejected"]
    )

    return {
        "generated_at": now.isoformat() + "Z",
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
            "avg_processing_hours": round(avg_hours, 1) if avg_hours is not None else None,
            "rejection_rate": round(rejection_rate, 4),
        },
        "clinical": {
            "cases_with_scans": len(cases_with_scans),
            "cases_with_photos": len(cases_with_photos),
            "cases_with_shade": len(cases_with_shade),
            "cases_with_shape": len(cases_with_shape),
            "cases_with_scan_body": len(cases_with_scan_body),
            "total_scans": int(total_scans),
            "total_photos": int(total_photos),
            "total_shade_saves": int(total_shades),
            "coverage_pct": round(
                (
                    len(
                        cases_with_scans
                        | cases_with_shade
                        | cases_with_shape
                        | cases_with_scan_body
                    )
                    / total_cases
                    * 100
                )
                if total_cases
                else 0.0,
                1,
            ),
        },
        "messages": {
            "threads_with_messages": threads_with_messages,
            "unread": unread_messages,
        },
        "notifications": {
            "total": notifications_total,
            "unread": notifications_unread,
        },
        "throughput": weeks,
        "attention": attention,
        "top_patients": top_patients,
    }
