"""Shared chat message persistence + WebSocket broadcast helpers."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.schemas_chat import MessageOut, ReplyPreviewOut
from app.services.chat_manager import chat_manager

logger = logging.getLogger("app.chat.messages")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


def partner_id(conversation: dict[str, Any], me: str) -> str:
    ua, ub = str(conversation["user_a"]), str(conversation["user_b"])
    return ub if ua == me else ua


def is_participant(conversation: dict[str, Any], user_id: str) -> bool:
    return user_id in (
        str(conversation.get("user_a")),
        str(conversation.get("user_b")),
    )


def fetch_conversation(conversation_id: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table("conversations")
            .select("*")
            .eq("id", conversation_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def fetch_message(message_id: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table("messages")
            .select("*")
            .eq("id", message_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def message_out(
    row: dict[str, Any],
    reply: dict[str, Any] | None = None,
) -> MessageOut:
    reply_out = None
    if reply:
        reply_out = ReplyPreviewOut(
            id=str(reply.get("id")),
            sender_id=str(reply.get("sender_id")),
            content=reply.get("content"),
            media_url=reply.get("media_url"),
            media_type=reply.get("media_type"),
            duration_seconds=(
                float(reply["duration_seconds"])
                if reply.get("duration_seconds") is not None
                else None
            ),
            created_at=reply.get("created_at"),
        )

    duration = row.get("duration_seconds")
    return MessageOut(
        id=str(row.get("id")),
        conversation_id=str(row.get("conversation_id")),
        sender_id=str(row.get("sender_id")),
        content=row.get("content"),
        media_url=row.get("media_url"),
        media_type=row.get("media_type"),
        duration_seconds=float(duration) if duration is not None else None,
        reply_to_message_id=(
            str(row["reply_to_message_id"])
            if row.get("reply_to_message_id")
            else None
        ),
        reply_to=reply_out,
        read_at=row.get("read_at"),
        created_at=row.get("created_at"),
    )


def hydrate_message(row: dict[str, Any]) -> MessageOut:
    reply = None
    if row.get("reply_to_message_id"):
        reply = fetch_message(str(row["reply_to_message_id"]))
    return message_out(row, reply)


async def insert_message_and_broadcast(
    *,
    conversation: dict[str, Any],
    sender_id: str,
    content: str | None = None,
    media_url: str | None = None,
    media_type: str | None = None,
    duration_seconds: float | None = None,
    reply_to_message_id: str | None = None,
) -> MessageOut:
    """Persist a message, bump conversation.updated_at, broadcast new_message."""
    conversation_id = str(conversation["id"])
    insert_row: dict[str, Any] = {
        "conversation_id": conversation_id,
        "sender_id": sender_id,
        "content": content or "",
        "created_at": utc_now_iso(),
    }
    if media_url:
        insert_row["media_url"] = media_url
    if media_type:
        insert_row["media_type"] = media_type
    if duration_seconds is not None:
        insert_row["duration_seconds"] = duration_seconds
    if reply_to_message_id:
        insert_row["reply_to_message_id"] = reply_to_message_id

    try:
        inserted = (
            get_supabase_admin()
            .table("messages")
            .insert(insert_row)
            .execute()
        )
        get_supabase_admin().table("conversations").update(
            {"updated_at": utc_now_iso()}
        ).eq("id", conversation_id).execute()
    except Exception as exc:
        logger.warning(
            "insert_message failed conversation_id=%s detail=%s",
            conversation_id,
            exc,
        )
        raise db_error(exc) from exc

    rows = getattr(inserted, "data", None) or []
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to save message",
        )

    message = hydrate_message(rows[0])
    payload = {"type": "new_message", "message": message.model_dump(mode="json")}
    recipient = partner_id(conversation, sender_id)
    await chat_manager.send_json(sender_id, payload)
    await chat_manager.send_json(recipient, payload)
    return message
