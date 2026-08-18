"""Chat media uploads to Cloudflare R2 + message insert + live broadcast."""

from __future__ import annotations

import logging
import mimetypes
from typing import Literal

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse

from app.core.security import AuthUser, get_current_user
from app.schemas_chat import MessageResponse
from app.services import chat_messages as cm
from app.services import patient_access as pa
from app.services.r2 import (
    ALLOWED_MEDIA_TYPES,
    MEDIA_TYPE_HELP,
    local_patient_photo_path,
    upload_chat_file,
)
from app.services.video_meta import probe_video_duration_seconds

router = APIRouter()
logger = logging.getLogger("app.api.media")

MediaType = Literal["voice", "image", "document", "video"]


@router.post(
    "/chat-upload",
    response_model=MessageResponse,
    summary="Upload chat media and broadcast message",
    status_code=status.HTTP_201_CREATED,
)
async def chat_media_upload(
    file: UploadFile = File(...),
    conversation_id: str = Form(...),
    media_type: str = Form(...),
    duration_seconds: float | None = Form(None),
    content: str | None = Form(None),
    reply_to_message_id: str | None = Form(None),
    user: AuthUser = Depends(get_current_user),
):
    """
    Stream a voice/image/document/video file to Cloudflare R2, insert a `messages` row,
    and push a `new_message` WebSocket event to both participants.
    Videos are stored at original quality (no transcode), max 200 MB.
    """
    conversation_id = conversation_id.strip()
    media_type = media_type.strip().lower()
    content_clean = (content or "").strip() or None
    reply_to = (reply_to_message_id or "").strip() or None

    if media_type not in ALLOWED_MEDIA_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"media_type must be one of: {MEDIA_TYPE_HELP}",
        )
    if media_type in ("voice", "video") and duration_seconds is not None and duration_seconds < 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="duration_seconds cannot be negative",
        )

    conv = cm.fetch_conversation(conversation_id)
    if conv is None or not cm.is_participant(conv, user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    if reply_to:
        parent = cm.fetch_message(reply_to)
        if parent is None or str(parent.get("conversation_id")) != conversation_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid reply_to_message_id",
            )

    logger.debug(
        "chat-upload start user_id=%s conversation_id=%s media_type=%s filename=%s",
        user.id,
        conversation_id,
        media_type,
        file.filename,
    )

    if media_type == "video" and (duration_seconds is None or duration_seconds <= 0):
        duration_seconds = probe_video_duration_seconds(file)

    public_url = upload_chat_file(
        file=file,
        conversation_id=conversation_id,
        media_type=media_type,
    )

    message = await cm.insert_message_and_broadcast(
        conversation=conv,
        sender_id=user.id,
        content=content_clean,
        media_url=public_url,
        media_type=media_type,
        duration_seconds=duration_seconds,
        reply_to_message_id=reply_to,
    )

    logger.debug(
        "chat-upload ok message_id=%s url=%s",
        message.id,
        public_url,
    )
    return message


@router.get(
    "/patient-photos/{patient_id}/{filename}",
    summary="Serve a locally stored clinical camera photo",
)
def serve_local_patient_photo(
    patient_id: str,
    filename: str,
    user: AuthUser = Depends(get_current_user),
):
    pa.require_patient_access(patient_id, user.id)
    path = local_patient_photo_path(patient_id, filename)
    if path is None or not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Photo file not found",
        )
    media_type = mimetypes.guess_type(filename)[0] or "image/jpeg"
    return FileResponse(path, media_type=media_type, filename=filename)
