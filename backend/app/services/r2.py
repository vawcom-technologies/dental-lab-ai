"""Cloudflare R2 (S3-compatible) uploads for chat media."""

from __future__ import annotations

import logging
import mimetypes
import uuid
from functools import lru_cache
from pathlib import Path

import boto3
from botocore.client import BaseClient
from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

logger = logging.getLogger("app.r2")

ALLOWED_MEDIA_TYPES = frozenset({"voice", "image", "document"})


@lru_cache
def get_r2_client() -> BaseClient:
    account = (settings.r2_account_id or "").strip()
    access = (settings.r2_access_key_id or "").strip()
    secret = (settings.r2_secret_access_key or "").strip()
    if not account or not access or not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="R2 storage is not configured — set R2_* env vars",
        )
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name="auto",
    )


def _require_bucket_and_public_url(media_type: str) -> tuple[str, str]:
    """Pick bucket + matching public CDN base from media_type."""
    if media_type == "voice":
        bucket = (settings.r2_voice_bucket or "").strip()
        public = (settings.r2_voice_public_url or "").strip().rstrip("/")
        bucket_env, url_env = "R2_VOICE_BUCKET", "R2_VOICE_PUBLIC_URL"
    else:
        # image + document share the documents bucket/CDN
        bucket = (settings.r2_documents_bucket or "").strip()
        public = (settings.r2_documents_public_url or "").strip().rstrip("/")
        bucket_env, url_env = "R2_DOCUMENTS_BUCKET", "R2_DOCUMENTS_PUBLIC_URL"

    if not bucket:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Missing {bucket_env} in environment",
        )
    if not public:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Missing {url_env} in environment",
        )
    return bucket, public


def build_object_key(
    *,
    conversation_id: str,
    media_type: str,
    filename: str | None,
) -> str:
    ext = Path(filename or "").suffix.lower()
    if not ext:
        if media_type == "voice":
            ext = ".webm"
        elif media_type == "image":
            ext = ".jpg"
        else:
            ext = ".bin"
    safe_name = f"{uuid.uuid4().hex}{ext}"
    return f"chat/{conversation_id}/{media_type}/{safe_name}"


def upload_chat_file(
    *,
    file: UploadFile,
    conversation_id: str,
    media_type: str,
) -> str:
    """
    Stream UploadFile to R2 and return the public CDN URL.
    No file-size enforcement (per product requirement).
    """
    if media_type not in ALLOWED_MEDIA_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="media_type must be one of: voice, image, document",
        )

    bucket, public_base = _require_bucket_and_public_url(media_type)
    key = build_object_key(
        conversation_id=conversation_id,
        media_type=media_type,
        filename=file.filename,
    )
    content_type = file.content_type or mimetypes.guess_type(file.filename or "")[0] or (
        "application/octet-stream"
    )
    # Browsers often send application/octet-stream; force sensible types for CDN.
    if content_type in ("application/octet-stream", "binary/octet-stream", ""):
        guessed = mimetypes.guess_type(file.filename or "")[0]
        if guessed:
            content_type = guessed
        elif media_type == "image":
            content_type = "image/jpeg"
        elif media_type == "voice":
            name = (file.filename or "").lower()
            if name.endswith(".wav"):
                content_type = "audio/wav"
            elif name.endswith(".webm"):
                content_type = "audio/webm"
            elif name.endswith(".ogg") or name.endswith(".opus"):
                content_type = "audio/ogg"
            else:
                content_type = "audio/mp4"
        else:
            content_type = "application/octet-stream"
    elif media_type == "image" and not content_type.startswith("image/"):
        content_type = mimetypes.guess_type(file.filename or "")[0] or "image/jpeg"

    client = get_r2_client()
    try:
        # Ensure stream is at start
        try:
            file.file.seek(0)
        except Exception:
            pass
        client.upload_fileobj(
            file.file,
            bucket,
            key,
            ExtraArgs={"ContentType": content_type},
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("R2 upload failed conversation_id=%s", conversation_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    public_url = f"{public_base}/{key}"
    logger.debug(
        "R2 upload ok bucket=%s key=%s url=%s",
        bucket,
        key,
        public_url,
    )
    return public_url


def _patient_images_bucket_and_url() -> tuple[str, str]:
    bucket = (settings.r2_patient_images_bucket or "").strip()
    public = (settings.r2_patient_images_public_url or "").strip().rstrip("/")
    if not bucket:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Missing R2_PATIENT_IMAGES_BUCKET in environment",
        )
    if not public:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Missing R2_PATIENT_IMAGES_PUBLIC_URL in environment",
        )
    return bucket, public


def upload_patient_photo_bytes(
    *,
    patient_id: str,
    filename: str,
    data: bytes,
    content_type: str = "image/jpeg",
) -> str:
    """Upload clinical photo bytes to the patient-images bucket; return public URL."""
    from io import BytesIO

    bucket, public_base = _patient_images_bucket_and_url()
    ext = Path(filename or "").suffix.lower() or ".jpg"
    key = f"patients/{patient_id}/photos/{uuid.uuid4().hex}{ext}"
    client = get_r2_client()
    try:
        client.upload_fileobj(
            BytesIO(data),
            bucket,
            key,
            ExtraArgs={"ContentType": content_type or "image/jpeg"},
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("R2 patient photo upload failed patient_id=%s", patient_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc
    return f"{public_base}/{key}"


def delete_patient_photo_object(file_url: str) -> None:
    """Delete a clinical photo object from the patient-images bucket."""
    url = (file_url or "").strip()
    if not url:
        return

    bucket, public_base = _patient_images_bucket_and_url()
    key = ""
    if url.startswith(public_base + "/"):
        key = url[len(public_base) + 1 :]
    else:
        # Fallback: keep path after /patients/ so older or alternate CDN hosts still work.
        marker = "/patients/"
        idx = url.find(marker)
        if idx >= 0:
            key = url[idx + 1 :]  # patients/...

    key = key.lstrip("/")
    if not key.startswith("patients/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Photo URL is not a patient-images object",
        )

    client = get_r2_client()
    try:
        client.delete_object(Bucket=bucket, Key=key)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("R2 patient photo delete failed key=%s", key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 delete failed: {str(exc).strip() or 'unknown error'}",
        ) from exc
