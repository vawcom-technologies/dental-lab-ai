"""Notifications inbox API — dentist/lab in-app alerts."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Notification, Case, Patient

router = APIRouter()


def _serialize(n: Notification) -> dict:
    case = n.case
    patient = case.patient if case else None
    patient_name = None
    if patient:
        patient_name = f"{patient.first_name} {patient.last_name}".strip()
    return {
        "id": n.id,
        "type": n.type,
        "message": n.message,
        "read": n.read,
        "case_id": n.case_id,
        "patient_name": patient_name,
        "case_status": case.status if case else None,
        "created_at": n.created_at.isoformat() if n.created_at else None,
    }


@router.get("")
def list_notifications(
    unread_only: bool = Query(False),
    type: str | None = Query(None, description="message|case_status|scan_quality|…"),
    limit: int = Query(100, ge=1, le=200),
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    q = (
        db.query(Notification)
        .options(joinedload(Notification.case).joinedload(Case.patient))
        .filter(Notification.user_id == user.id)
    )
    if unread_only:
        q = q.filter(Notification.read.is_(False))
    if type:
        q = q.filter(Notification.type == type)
    rows = q.order_by(Notification.created_at.desc()).limit(limit).all()
    return [_serialize(n) for n in rows]


@router.get("/unread-count")
def unread_count(
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    n = (
        db.query(Notification)
        .filter(Notification.user_id == user.id, Notification.read.is_(False))
        .count()
    )
    return {"count": n}


@router.post("/{notification_id}/read")
def mark_read(
    notification_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == user.id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Notification not found")
    row.read = True
    db.commit()
    return {"ok": True, "id": notification_id}


@router.post("/read-all")
def mark_all_read(
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    updated = (
        db.query(Notification)
        .filter(Notification.user_id == user.id, Notification.read.is_(False))
        .update({"read": True}, synchronize_session=False)
    )
    db.commit()
    return {"ok": True, "updated": updated}
