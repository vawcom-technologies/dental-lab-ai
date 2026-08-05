"""1-to-1 real-time messaging — REST inbox + WebSocket transport."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)

from app.core.security import AuthUser, get_current_user, get_user_from_token
from app.core.supabase_client import get_supabase_admin
from app.schemas_chat import (
    ChatProfileOut,
    ConversationOut,
    GetOrCreateConversationRequest,
    MessageListOut,
    MessageOut,
    ReplyPreviewOut,
)
from app.services.chat_manager import chat_manager
from app.services.profiles import fetch_profile

router = APIRouter()
ws_router = APIRouter()
logger = logging.getLogger("app.api.chat")


def _db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _canonical_pair(user_id: str, other_id: str) -> tuple[str, str]:
    a, b = sorted([user_id, other_id])
    return a, b


def _partner_id(row: dict[str, Any], me: str) -> str:
    ua, ub = str(row["user_a"]), str(row["user_b"])
    return ub if ua == me else ua


def _is_participant(row: dict[str, Any], user_id: str) -> bool:
    return user_id in (str(row.get("user_a")), str(row.get("user_b")))


def _profile_out(row: dict[str, Any] | None) -> ChatProfileOut | None:
    if not row:
        return None
    return ChatProfileOut(
        id=str(row.get("id")),
        name=row.get("name"),
        email=row.get("email"),
        role=row.get("role"),
        clinic_name=row.get("clinic_name"),
        phone=row.get("phone"),
    )


def _message_out(
    row: dict[str, Any],
    reply: dict[str, Any] | None = None,
) -> MessageOut:
    reply_out = None
    if reply:
        reply_out = ReplyPreviewOut(
            id=str(reply.get("id")),
            sender_id=str(reply.get("sender_id")),
            content=reply.get("content") or "",
            media_url=reply.get("media_url"),
            created_at=reply.get("created_at"),
        )
    return MessageOut(
        id=str(row.get("id")),
        conversation_id=str(row.get("conversation_id")),
        sender_id=str(row.get("sender_id")),
        content=row.get("content") or "",
        media_url=row.get("media_url"),
        reply_to_message_id=(
            str(row["reply_to_message_id"])
            if row.get("reply_to_message_id")
            else None
        ),
        reply_to=reply_out,
        read_at=row.get("read_at"),
        created_at=row.get("created_at"),
    )


def _fetch_conversation(conversation_id: str) -> dict[str, Any] | None:
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
        raise _db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def _fetch_message(message_id: str) -> dict[str, Any] | None:
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
        raise _db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def _last_message(conversation_id: str) -> dict[str, Any] | None:
    try:
        result = (
            get_supabase_admin()
            .table("messages")
            .select("*")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise _db_error(exc) from exc
    rows = getattr(result, "data", None) or []
    return rows[0] if rows else None


def _unread_count(conversation_id: str, viewer_id: str) -> int:
    try:
        result = (
            get_supabase_admin()
            .table("messages")
            .select("id", count="exact")
            .eq("conversation_id", conversation_id)
            .neq("sender_id", viewer_id)
            .is_("read_at", "null")
            .execute()
        )
    except Exception as exc:
        raise _db_error(exc) from exc
    count = getattr(result, "count", None)
    if count is not None:
        return int(count)
    return len(getattr(result, "data", None) or [])


def _hydrate_message(row: dict[str, Any]) -> MessageOut:
    reply = None
    if row.get("reply_to_message_id"):
        reply = _fetch_message(str(row["reply_to_message_id"]))
    return _message_out(row, reply)


# ── REST ──────────────────────────────────────────────────────────────────────


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(user: AuthUser = Depends(get_current_user)):
    """Inbox: conversations for the current user, newest activity first."""
    logger.debug("list_conversations user_id=%s", user.id)
    try:
        as_a = (
            get_supabase_admin()
            .table("conversations")
            .select("*")
            .eq("user_a", user.id)
            .execute()
        )
        as_b = (
            get_supabase_admin()
            .table("conversations")
            .select("*")
            .eq("user_b", user.id)
            .execute()
        )
    except Exception as exc:
        raise _db_error(exc) from exc

    rows = (getattr(as_a, "data", None) or []) + (getattr(as_b, "data", None) or [])
    rows.sort(key=lambda r: r.get("updated_at") or "", reverse=True)

    out: list[ConversationOut] = []
    for row in rows:
        partner_id = _partner_id(row, user.id)
        partner = _profile_out(fetch_profile(partner_id))
        last = _last_message(str(row["id"]))
        unread = _unread_count(str(row["id"]), user.id)
        out.append(
            ConversationOut(
                id=str(row["id"]),
                user_a=str(row["user_a"]),
                user_b=str(row["user_b"]),
                partner=partner,
                last_message=_message_out(last) if last else None,
                unread_count=unread,
                created_at=row.get("created_at"),
                updated_at=row.get("updated_at"),
            )
        )
    return out


@router.post("/conversations/get-or-create", response_model=ConversationOut)
def get_or_create_conversation(
    payload: GetOrCreateConversationRequest,
    user: AuthUser = Depends(get_current_user),
):
    """Open (or create) the canonical 1-to-1 room with target_user_id."""
    target = payload.target_user_id.strip()
    try:
        UUID(target)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="target_user_id must be a valid UUID",
        ) from exc

    if target == user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot start a conversation with yourself",
        )

    if fetch_profile(target) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Target user not found",
        )

    user_a, user_b = _canonical_pair(user.id, target)
    logger.debug(
        "get_or_create user_id=%s target=%s pair=(%s,%s)",
        user.id,
        target,
        user_a,
        user_b,
    )

    try:
        existing = (
            get_supabase_admin()
            .table("conversations")
            .select("*")
            .eq("user_a", user_a)
            .eq("user_b", user_b)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise _db_error(exc) from exc

    rows = getattr(existing, "data", None) or []
    if rows:
        row = rows[0]
    else:
        try:
            created = (
                get_supabase_admin()
                .table("conversations")
                .insert(
                    {
                        "user_a": user_a,
                        "user_b": user_b,
                        "created_at": _utc_now_iso(),
                        "updated_at": _utc_now_iso(),
                    }
                )
                .execute()
            )
        except Exception as exc:
            # Race: unique constraint — re-fetch
            try:
                existing = (
                    get_supabase_admin()
                    .table("conversations")
                    .select("*")
                    .eq("user_a", user_a)
                    .eq("user_b", user_b)
                    .limit(1)
                    .execute()
                )
                rows = getattr(existing, "data", None) or []
                if rows:
                    row = rows[0]
                else:
                    raise _db_error(exc) from exc
            except HTTPException:
                raise
            except Exception as inner:
                raise _db_error(inner) from inner
        else:
            created_rows = getattr(created, "data", None) or []
            if not created_rows:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Failed to create conversation",
                )
            row = created_rows[0]

    partner_id = _partner_id(row, user.id)
    last = _last_message(str(row["id"]))
    return ConversationOut(
        id=str(row["id"]),
        user_a=str(row["user_a"]),
        user_b=str(row["user_b"]),
        partner=_profile_out(fetch_profile(partner_id)),
        last_message=_message_out(last) if last else None,
        unread_count=_unread_count(str(row["id"]), user.id),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=MessageListOut,
)
def list_messages(
    conversation_id: str,
    before: str | None = Query(
        default=None,
        description="ISO timestamp — return messages strictly older than this",
    ),
    limit: int = Query(default=50, ge=1, le=100),
    user: AuthUser = Depends(get_current_user),
):
    """Paginated history (newest-first page). Use `before` for infinite scroll."""
    conv = _fetch_conversation(conversation_id)
    if conv is None or not _is_participant(conv, user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    try:
        query = (
            get_supabase_admin()
            .table("messages")
            .select("*")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=True)
            .limit(limit + 1)
        )
        if before:
            query = query.lt("created_at", before)
        result = query.execute()
    except Exception as exc:
        raise _db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    has_more = len(rows) > limit
    rows = rows[:limit]

    # Batch-load reply parents
    reply_ids = {
        str(r["reply_to_message_id"])
        for r in rows
        if r.get("reply_to_message_id")
    }
    replies: dict[str, dict[str, Any]] = {}
    if reply_ids:
        try:
            reply_result = (
                get_supabase_admin()
                .table("messages")
                .select("*")
                .in_("id", list(reply_ids))
                .execute()
            )
            for r in getattr(reply_result, "data", None) or []:
                replies[str(r["id"])] = r
        except Exception as exc:
            raise _db_error(exc) from exc

    items = [
        _message_out(
            row,
            replies.get(str(row["reply_to_message_id"]))
            if row.get("reply_to_message_id")
            else None,
        )
        for row in rows
    ]
    return MessageListOut(items=items, has_more=has_more)


# ── WebSocket ─────────────────────────────────────────────────────────────────


async def _ws_send_message(user: AuthUser, data: dict[str, Any]) -> None:
    conversation_id = str(data.get("conversation_id") or "").strip()
    content = str(data.get("content") or "").strip()
    media_url = data.get("media_url")
    reply_to = data.get("reply_to_message_id")

    if not conversation_id:
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "conversation_id is required"},
        )
        return
    if not content and not media_url:
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "content or media_url is required"},
        )
        return

    conv = _fetch_conversation(conversation_id)
    if conv is None or not _is_participant(conv, user.id):
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "Conversation not found"},
        )
        return

    if reply_to:
        parent = _fetch_message(str(reply_to))
        if parent is None or str(parent.get("conversation_id")) != conversation_id:
            await chat_manager.send_json(
                user.id,
                {"type": "error", "detail": "Invalid reply_to_message_id"},
            )
            return

    insert_row: dict[str, Any] = {
        "conversation_id": conversation_id,
        "sender_id": user.id,
        "content": content,
        "created_at": _utc_now_iso(),
    }
    if media_url:
        insert_row["media_url"] = media_url
    if reply_to:
        insert_row["reply_to_message_id"] = str(reply_to)

    try:
        inserted = (
            get_supabase_admin()
            .table("messages")
            .insert(insert_row)
            .execute()
        )
        get_supabase_admin().table("conversations").update(
            {"updated_at": _utc_now_iso()}
        ).eq("id", conversation_id).execute()
    except Exception as exc:
        logger.warning("send_message db error user_id=%s detail=%s", user.id, exc)
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "Failed to save message"},
        )
        return

    rows = getattr(inserted, "data", None) or []
    if not rows:
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "Failed to save message"},
        )
        return

    message = _hydrate_message(rows[0])
    payload = {"type": "new_message", "message": message.model_dump(mode="json")}

    partner = _partner_id(conv, user.id)
    await chat_manager.send_json(user.id, payload)
    await chat_manager.send_json(partner, payload)


async def _ws_mark_as_read(user: AuthUser, data: dict[str, Any]) -> None:
    conversation_id = str(data.get("conversation_id") or "").strip()
    if not conversation_id:
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "conversation_id is required"},
        )
        return

    conv = _fetch_conversation(conversation_id)
    if conv is None or not _is_participant(conv, user.id):
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "Conversation not found"},
        )
        return

    now = _utc_now_iso()
    try:
        updated = (
            get_supabase_admin()
            .table("messages")
            .update({"read_at": now})
            .eq("conversation_id", conversation_id)
            .neq("sender_id", user.id)
            .is_("read_at", "null")
            .execute()
        )
    except Exception as exc:
        logger.warning("mark_as_read db error user_id=%s detail=%s", user.id, exc)
        await chat_manager.send_json(
            user.id,
            {"type": "error", "detail": "Failed to mark messages as read"},
        )
        return

    rows = getattr(updated, "data", None) or []
    message_ids = [str(r["id"]) for r in rows]
    partner = _partner_id(conv, user.id)
    event = {
        "type": "messages_read",
        "conversation_id": conversation_id,
        "reader_id": user.id,
        "message_ids": message_ids,
        "read_at": now,
    }
    await chat_manager.send_json(user.id, event)
    await chat_manager.send_json(partner, event)


@ws_router.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket, token: str = Query(...)):
    """
    Real-time chat channel.

    Connect: `ws://host/ws/chat?token=<access_token>`

    Client → server events:
      { "type": "send_message", "conversation_id": "...", "content": "...",
        "reply_to_message_id": null, "media_url": null }
      { "type": "mark_as_read", "conversation_id": "..." }

    Server → client events:
      { "type": "new_message", "message": { ... } }
      { "type": "messages_read", "conversation_id": "...", "reader_id": "...",
        "message_ids": [...], "read_at": "..." }
      { "type": "error", "detail": "..." }
    """
    try:
        user = get_user_from_token(token)
    except HTTPException:
        await websocket.close(code=4401)
        return

    await chat_manager.connect(user.id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            if not isinstance(data, dict):
                await chat_manager.send_json(
                    user.id, {"type": "error", "detail": "Invalid payload"}
                )
                continue

            event_type = str(
                data.get("type") or data.get("action") or ""
            ).strip()
            logger.debug("ws event user_id=%s type=%s", user.id, event_type)

            if event_type == "send_message":
                await _ws_send_message(user, data)
            elif event_type == "mark_as_read":
                await _ws_mark_as_read(user, data)
            else:
                await chat_manager.send_json(
                    user.id,
                    {"type": "error", "detail": f"Unknown event type: {event_type}"},
                )
    except WebSocketDisconnect:
        logger.debug("ws client disconnect user_id=%s", user.id)
    except Exception as exc:
        logger.warning("ws loop error user_id=%s detail=%s", user.id, exc)
    finally:
        chat_manager.disconnect(user.id)
