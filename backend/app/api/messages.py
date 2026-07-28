"""Messages API — per-case chat (text/voice/image). Week 4 scaffold."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, Message, ActivityLog

router = APIRouter()


class MessageCreate(BaseModel):
    type: str = "text"  # text | voice | image | file
    body: str | None = None
    content_path: str | None = None


@router.get("/{case_id}/messages")
def list_messages(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    msgs = (
        db.query(Message)
        .filter(Message.case_id == case_id)
        .order_by(Message.sent_at.asc())
        .all()
    )
    return [
        {
            "id": m.id,
            "sender_id": m.sender_id,
            "type": m.type,
            "body": m.body,
            "content_path": m.content_path,
            "sent_at": m.sent_at,
            "read_at": m.read_at,
        }
        for m in msgs
    ]


@router.post("/{case_id}/messages")
def send_message(
    case_id: int,
    payload: MessageCreate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    if payload.type not in ("text", "voice", "image", "file"):
        raise HTTPException(status_code=400, detail="Invalid message type")

    msg = Message(
        case_id=case_id,
        sender_id=user.id,
        type=payload.type,
        body=payload.body,
        content_path=payload.content_path,
    )
    db.add(msg)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="message.send",
            target_type="message",
            target_id=msg.id,
        )
    )
    db.commit()
    db.refresh(msg)
    return {"id": msg.id, "sent_at": msg.sent_at}


@router.post("/{case_id}/messages/{message_id}/read")
def mark_read(
    case_id: int,
    message_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
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
