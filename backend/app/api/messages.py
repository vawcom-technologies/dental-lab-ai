"""Messages API — per-case chat + thread inbox."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session, joinedload

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, Patient, Message, ActivityLog, Notification

router = APIRouter()
inbox_router = APIRouter()


class MessageCreate(BaseModel):
    type: str = "text"  # text | voice | image | file
    body: str | None = Field(default=None, max_length=4000)
    content_path: str | None = None


def _allowed_patient_ids(db: Session, user: User) -> set[int] | None:
    """None = lab sees all; otherwise dentist's patients only."""
    if user.role == "lab":
        return None
    rows = db.query(Patient.id).filter(Patient.dentist_id == user.id).all()
    return {r[0] for r in rows}


def _get_accessible_case(db: Session, user: User, case_id: int) -> Case:
    case = (
        db.query(Case)
        .options(joinedload(Case.patient))
        .filter(Case.id == case_id)
        .first()
    )
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    allowed = _allowed_patient_ids(db, user)
    if allowed is not None and case.patient_id not in allowed:
        raise HTTPException(status_code=403, detail="Forbidden")
    return case


def _serialize_message(m: Message, current_user_id: int) -> dict:
    sender = m.sender
    return {
        "id": m.id,
        "case_id": m.case_id,
        "sender_id": m.sender_id,
        "sender_name": sender.name if sender else "Unknown",
        "sender_role": sender.role if sender else "unknown",
        "mine": m.sender_id == current_user_id,
        "type": m.type,
        "body": m.body,
        "content_path": m.content_path,
        "sent_at": m.sent_at,
        "read_at": m.read_at,
    }


@inbox_router.get("/threads")
def list_threads(
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    """Inbox: one row per case with latest message + unread count."""
    q = db.query(Case).options(joinedload(Case.patient))
    allowed = _allowed_patient_ids(db, user)
    if allowed is not None:
        q = q.filter(Case.patient_id.in_(allowed or {-1}))
    cases = q.order_by(Case.updated_at.desc()).all()

    threads: list[dict] = []
    for case in cases:
        msgs = (
            db.query(Message)
            .options(joinedload(Message.sender))
            .filter(Message.case_id == case.id)
            .order_by(Message.sent_at.desc())
            .all()
        )
        last = msgs[0] if msgs else None
        unread = sum(
            1
            for m in msgs
            if m.read_at is None and m.sender_id != user.id
        )
        patient = case.patient
        name = (
            f"{patient.first_name} {patient.last_name}".strip()
            if patient
            else f"Case #{case.id}"
        )
        threads.append(
            {
                "case_id": case.id,
                "patient_id": case.patient_id,
                "patient_name": name,
                "case_status": case.status,
                "meta": f"CASE-{case.id:04d} · Elite Dent Lab",
                "preview": (last.body if last and last.body else "No messages yet"),
                "last_sent_at": last.sent_at if last else case.updated_at,
                "unread": unread,
                "has_messages": last is not None,
            }
        )

    # Cases with activity first, then by last_sent_at
    threads.sort(
        key=lambda t: (
            0 if t["has_messages"] else 1,
            -(t["last_sent_at"].timestamp() if t["last_sent_at"] else 0),
        )
    )
    return threads


@router.get("/{case_id}/messages")
def list_messages(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    _get_accessible_case(db, user, case_id)
    msgs = (
        db.query(Message)
        .options(joinedload(Message.sender))
        .filter(Message.case_id == case_id)
        .order_by(Message.sent_at.asc())
        .all()
    )
    return [_serialize_message(m, user.id) for m in msgs]


@router.post("/{case_id}/messages")
def send_message(
    case_id: int,
    payload: MessageCreate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = _get_accessible_case(db, user, case_id)
    if payload.type not in ("text", "voice", "image", "file"):
        raise HTTPException(status_code=400, detail="Invalid message type")
    body = (payload.body or "").strip()
    if payload.type == "text" and not body:
        raise HTTPException(status_code=400, detail="Message body required")

    msg = Message(
        case_id=case_id,
        sender_id=user.id,
        type=payload.type,
        body=body or None,
        content_path=payload.content_path,
    )
    db.add(msg)
    db.flush()

    # Notify the other role
    recipients = (
        db.query(User)
        .filter(User.role == ("lab" if user.role == "dentist" else "dentist"))
        .all()
    )
    preview = body[:80] if body else f"[{payload.type}]"
    for recipient in recipients:
        # For dentist recipients, only notify the patient's dentist
        if recipient.role == "dentist" and case.patient:
            if case.patient.dentist_id != recipient.id:
                continue
        db.add(
            Notification(
                user_id=recipient.id,
                case_id=case_id,
                type="message",
                message=f"{user.name}: {preview}",
            )
        )

    db.add(
        ActivityLog(
            user_id=user.id,
            action="message.send",
            target_type="message",
            target_id=msg.id,
        )
    )
    case.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(msg)
    # Reload sender relationship
    msg = (
        db.query(Message)
        .options(joinedload(Message.sender))
        .filter(Message.id == msg.id)
        .first()
    )
    return _serialize_message(msg, user.id)


@router.post("/{case_id}/messages/read")
def mark_thread_read(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    """Mark all inbound messages on this case as read."""
    _get_accessible_case(db, user, case_id)
    now = datetime.utcnow()
    updated = 0
    msgs = (
        db.query(Message)
        .filter(
            Message.case_id == case_id,
            Message.sender_id != user.id,
            Message.read_at.is_(None),
        )
        .all()
    )
    for msg in msgs:
        msg.read_at = now
        updated += 1
    db.commit()
    return {"case_id": case_id, "marked": updated}


@router.post("/{case_id}/messages/{message_id}/read")
def mark_read(
    case_id: int,
    message_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    _get_accessible_case(db, user, case_id)
    msg = (
        db.query(Message)
        .filter(Message.id == message_id, Message.case_id == case_id)
        .first()
    )
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    msg.read_at = datetime.utcnow()
    db.commit()
    return {"id": msg.id, "read_at": msg.read_at}
