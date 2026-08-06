"""Pydantic models for 1-to-1 chat."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class GetOrCreateConversationRequest(BaseModel):
    target_user_id: str = Field(min_length=1)


class ChatProfileOut(BaseModel):
    id: str
    name: str | None = None
    email: str | None = None
    role: str | None = None
    clinic_name: str | None = None
    phone: str | None = None


class ReplyPreviewOut(BaseModel):
    id: str
    sender_id: str
    content: str
    media_url: str | None = None
    created_at: datetime | None = None


class MessageOut(BaseModel):
    id: str
    conversation_id: str
    sender_id: str
    content: str
    media_url: str | None = None
    reply_to_message_id: str | None = None
    reply_to: ReplyPreviewOut | None = None
    read_at: datetime | None = None
    created_at: datetime | None = None


class ConversationOut(BaseModel):
    id: str
    user_a: str
    user_b: str
    partner: ChatProfileOut | None = None
    last_message: MessageOut | None = None
    unread_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class MessageListOut(BaseModel):
    items: list[MessageOut]
    has_more: bool = False


# ── WebSocket payloads (documented in /docs OpenAPI Schemas) ─────────────────

class WSMessageSend(BaseModel):
    """Client → server: send a chat message over the WebSocket."""

    type: str = Field(
        default="send_message",
        description='Event discriminator. Use "send_message" (alias: "action").',
        examples=["send_message"],
    )
    conversation_id: str = Field(
        ...,
        description="UUID of the conversation room",
        examples=["3fa85f64-5717-4562-b3fc-2c963f66afa6"],
    )
    content: str = Field(
        ...,
        description="Message text body",
        examples=["Hello — can you confirm the shade?"],
    )
    reply_to_message_id: str | None = Field(
        default=None,
        description="Optional UUID of the message being replied to",
    )
    media_url: str | None = Field(
        default=None,
        description="Optional media URL attachment",
    )


class WSMarkAsRead(BaseModel):
    """Client → server: mark all unread incoming messages in a room as read."""

    type: str = Field(
        default="mark_as_read",
        description='Event discriminator. Use "mark_as_read" (alias: "action").',
        examples=["mark_as_read"],
    )
    conversation_id: str = Field(
        ...,
        description="UUID of the conversation room",
        examples=["3fa85f64-5717-4562-b3fc-2c963f66afa6"],
    )


class WSErrorEvent(BaseModel):
    """Server → client: error notification."""

    type: str = Field(default="error", examples=["error"])
    detail: str = Field(..., examples=["conversation_id is required"])


class WSNewMessageEvent(BaseModel):
    """Server → client: a new message was saved and delivered."""

    type: str = Field(default="new_message", examples=["new_message"])
    message: MessageOut


class WSMessagesReadEvent(BaseModel):
    """Server → client: partner (or self) marked messages as read."""

    type: str = Field(default="messages_read", examples=["messages_read"])
    conversation_id: str
    reader_id: str
    message_ids: list[str] = Field(default_factory=list)
    read_at: datetime | None = None
