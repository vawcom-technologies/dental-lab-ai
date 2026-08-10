"""Cloudflare R2 (S3-compatible) uploads for chat media."""

from __future__ import annotations

import logging
import mimetypes
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Literal

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


# ── Patient clinical media (scans / shades / smiles) ──────────────────────────

PatientAssetKind = Literal["scans", "shades", "smiles"]

_SCAN_EXTENSIONS = frozenset({".ply", ".stl", ".obj"})
_IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".webp", ".heic", ".tif", ".tiff"})


def _require_patient_bucket(kind: PatientAssetKind) -> tuple[str, str]:
    if kind == "scans":
        bucket = (settings.r2_scans_bucket or "").strip()
        public = (settings.r2_scans_public_url or "").strip().rstrip("/")
        bucket_env, url_env = "R2_SCANS_BUCKET", "R2_SCANS_PUBLIC_URL"
    elif kind == "shades":
        bucket = (settings.r2_shades_bucket or "").strip()
        public = (settings.r2_shades_public_url or "").strip().rstrip("/")
        bucket_env, url_env = "R2_SHADES_BUCKET", "R2_SHADES_PUBLIC_URL"
    else:
        bucket = (settings.r2_smiles_bucket or "").strip()
        public = (settings.r2_smiles_public_url or "").strip().rstrip("/")
        bucket_env, url_env = "R2_SMILES_BUCKET", "R2_SMILES_PUBLIC_URL"

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


def build_patient_asset_key(
    *,
    kind: PatientAssetKind,
    patient_id: str,
    filename: str | None,
) -> str:
    ext = Path(filename or "").suffix.lower()
    if kind == "scans" and ext not in _SCAN_EXTENSIONS:
        ext = ext if ext else ".ply"
    elif kind != "scans" and not ext:
        ext = ".jpg"
    safe_name = f"{uuid.uuid4().hex}{ext}"
    return f"patients/{patient_id}/{kind}/{safe_name}"


def validate_patient_upload_filename(
    *,
    kind: PatientAssetKind,
    filename: str | None,
) -> str:
    name = (filename or "").strip()
    if not name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Filename is required",
        )
    ext = Path(name).suffix.lower()
    if kind == "scans":
        if ext not in _SCAN_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Scan file must be .ply, .stl, or .obj",
            )
    else:
        if ext and ext not in _IMAGE_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Image must be .jpg, .jpeg, .png, .webp, .heic, .tif, or .tiff",
            )
    return name


def upload_patient_asset(
    *,
    file: UploadFile,
    kind: PatientAssetKind,
    patient_id: str,
) -> tuple[str, str, str]:
    """
    Upload a patient clinical file to R2.

    Returns (file_key, public_url, original_filename).
    """
    filename = validate_patient_upload_filename(kind=kind, filename=file.filename)
    bucket, public_base = _require_patient_bucket(kind)
    key = build_patient_asset_key(
        kind=kind, patient_id=patient_id, filename=filename
    )
    content_type = file.content_type or mimetypes.guess_type(filename)[0] or (
        "application/octet-stream"
    )
    if content_type in ("application/octet-stream", "binary/octet-stream", ""):
        guessed = mimetypes.guess_type(filename)[0]
        content_type = guessed or "application/octet-stream"
    if kind != "scans" and not content_type.startswith("image/"):
        content_type = mimetypes.guess_type(filename)[0] or "image/jpeg"

    client = get_r2_client()
    try:
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
        logger.exception("R2 patient upload failed kind=%s patient_id=%s", kind, patient_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    public_url = f"{public_base}/{key}"
    logger.debug(
        "R2 patient upload ok kind=%s bucket=%s key=%s",
        kind,
        bucket,
        key,
    )
    return key, public_url, filename


def delete_patient_asset(*, kind: PatientAssetKind, file_key: str) -> None:
    """Delete an object from the patient-asset R2 bucket. Missing keys are ignored."""
    if not (file_key or "").strip():
        return
    bucket, _ = _require_patient_bucket(kind)
    client = get_r2_client()
    try:
        client.delete_object(Bucket=bucket, Key=file_key)
    except Exception as exc:
        logger.exception(
            "R2 patient delete failed kind=%s key=%s detail=%s",
            kind,
            file_key,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 delete failed: {str(exc).strip() or 'unknown error'}",
        ) from exc


# ── Patient clinical camera photos ────────────────────────────────────────────


def _require_patient_images_bucket() -> tuple[str, str]:
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
    """Upload raw photo bytes to the patient-images R2 bucket; return public URL."""
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty photo file",
        )
    bucket, public_base = _require_patient_images_bucket()
    ext = Path(filename or "").suffix.lower() or ".jpg"
    if ext not in _IMAGE_EXTENSIONS:
        ext = ".jpg"
    key = f"patients/{patient_id}/photos/{uuid.uuid4().hex}{ext}"
    ctype = (content_type or "").strip() or mimetypes.guess_type(filename or "")[0] or (
        "image/jpeg"
    )
    if not ctype.startswith("image/"):
        ctype = "image/jpeg"

    client = get_r2_client()
    try:
        client.put_object(
            Bucket=bucket,
            Key=key,
            Body=data,
            ContentType=ctype,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("R2 photo upload failed patient_id=%s", patient_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    public_url = f"{public_base}/{key}"
    logger.debug("R2 photo upload ok bucket=%s key=%s", bucket, key)
    return public_url


def delete_patient_photo_object(file_url: str) -> None:
    """Delete a patient photo from R2 using its public URL (no-op if empty/unknown)."""
    url = (file_url or "").strip()
    if not url:
        return

    key = file_key_from_patient_photo_url(url)
    if not key:
        logger.warning("R2 photo delete skipped — could not derive key from url=%s", url)
        return

    bucket, _ = _require_patient_images_bucket()
    client = get_r2_client()
    try:
        client.delete_object(Bucket=bucket, Key=key)
    except Exception as exc:
        logger.exception("R2 photo delete failed key=%s detail=%s", key, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 delete failed: {str(exc).strip() or 'unknown error'}",
        ) from exc


def is_patient_images_url(file_url: str) -> bool:
    """True when URL points at the clinical camera photos CDN."""
    url = (file_url or "").strip()
    if not url:
        return False
    public = (settings.r2_patient_images_public_url or "").strip().rstrip("/")
    if public and url.startswith(f"{public}/"):
        return True
    # Path convention used by upload_patient_photo_bytes
    return "/patients/" in url and "/photos/" in url


def file_key_from_patient_photo_url(file_url: str) -> str:
    """Derive R2 object key from a patient photo public URL."""
    url = (file_url or "").strip()
    if not url:
        return ""
    public = (settings.r2_patient_images_public_url or "").strip().rstrip("/")
    if public and url.startswith(f"{public}/"):
        return url[len(public) + 1 :]
    try:
        from urllib.parse import urlparse

        return (urlparse(url).path or "").lstrip("/")
    except Exception:
        return ""
