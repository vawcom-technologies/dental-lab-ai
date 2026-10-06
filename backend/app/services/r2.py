"""Cloudflare R2 (S3-compatible) storage: chat media and patient files."""

from __future__ import annotations

import hashlib
import logging
import mimetypes
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Literal

import boto3
from botocore.client import BaseClient
from botocore.exceptions import ClientError
from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

logger = logging.getLogger("app.r2")

ALLOWED_MEDIA_TYPES = frozenset({"voice", "image", "document", "video"})
MEDIA_TYPE_HELP = "voice, image, document, video"
CHAT_VIDEO_MAX_BYTES = 200 * 1024 * 1024
_VIDEO_EXTENSIONS = frozenset(
    {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv", ".3gp", ".mpeg", ".mpg", ".qt"}
)


# kind -> (bucket setting, public URL setting); env vars are the upper-case names.
_BUCKETS = {
    "voice": ("r2_voice_bucket", "r2_voice_public_url"),
    "video": ("r2_videos_bucket", "r2_videos_public_url"),
    "image": ("r2_documents_bucket", "r2_documents_public_url"),  # chat images share documents
    "document": ("r2_documents_bucket", "r2_documents_public_url"),
    "photos": ("r2_patient_images_bucket", "r2_patient_images_public_url"),
    "scans": ("r2_scans_bucket", "r2_scans_public_url"),
    "shades": ("r2_shades_bucket", "r2_shades_public_url"),
    "smiles": ("r2_smiles_bucket", "r2_smiles_public_url"),
}


def bucket_for(kind: str) -> tuple[str, str]:
    """(bucket, public base URL) for a media kind; 503 if no bucket is set.

    Buckets are private, so the public URL is optional (empty = none).
    """
    names = _BUCKETS[kind]
    bucket, public = (str(getattr(settings, n) or "").strip().rstrip("/") for n in names)
    if not bucket:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Missing {names[0].upper()} in environment",
        )
    return bucket, public


def _stored_url(public_base: str, key: str) -> str:
    return f"{public_base}/{key}" if public_base else key


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
    # Buckets created with a jurisdiction (e.g. "eu") only answer on that endpoint.
    jur = (settings.r2_jurisdiction or "").strip().strip(".")
    host = f"{account}.{jur}.r2" if jur else f"{account}.r2"
    return boto3.client(
        "s3",
        endpoint_url=f"https://{host}.cloudflarestorage.com",
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name="auto",
    )


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
        elif media_type == "video":
            ext = ".mp4"
        else:
            ext = ".bin"
    safe_name = f"{uuid.uuid4().hex}{ext}"
    return f"chat/{conversation_id}/{media_type}/{safe_name}"


def chat_media_kind(media_type: str | None) -> str:
    media = (media_type or "").strip().lower() or "document"
    return media if media in ALLOWED_MEDIA_TYPES else "document"


def chat_key_from_url(media_url: str, public_base: str = "") -> str:
    """Object key of a chat media value: a bare key, or a (legacy) public URL."""
    url = (media_url or "").strip()
    if public_base and url.startswith(f"{public_base}/"):
        return url[len(public_base) + 1 :]
    if url.startswith(("http://", "https://")):
        from urllib.parse import urlparse

        return (urlparse(url).path or "").lstrip("/")
    return url.lstrip("/")


CHAT_LINK_TTL_SECONDS = 3600  # long enough for a video to play and seek


def presign_chat_media(*, media_type: str, media_url: str) -> str:
    """Short-lived signed GET link for a chat attachment (caller checks access)."""
    bucket, public_base = bucket_for(chat_media_kind(media_type))
    key = chat_key_from_url(media_url, public_base)
    if not key.startswith("chat/"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    return get_r2_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=CHAT_LINK_TTL_SECONDS,
    )


def delete_chat_media_object(*, media_type: str, file_url: str) -> None:
    """Best-effort delete of a chat media object."""
    if not (file_url or "").strip():
        return
    try:
        bucket, public_base = bucket_for(chat_media_kind(media_type))
    except HTTPException:
        logger.warning("chat R2 delete skipped — bucket not configured media_type=%s", media_type)
        return
    key = chat_key_from_url(file_url, public_base)
    if not key:
        logger.warning("chat R2 delete skipped — no key from url=%s", file_url)
        return
    try:
        get_r2_client().delete_object(Bucket=bucket, Key=key)
    except Exception as exc:
        # Account deletion should not abort solely on orphaned media.
        logger.warning("chat R2 delete failed key=%s detail=%s", key, exc)


def _video_content_type(filename: str | None) -> str:
    guessed = mimetypes.guess_type(filename or "")[0]
    if guessed and guessed.startswith("video/"):
        return guessed
    name = (filename or "").lower()
    if name.endswith(".mov") or name.endswith(".qt"):
        return "video/quicktime"
    if name.endswith(".webm"):
        return "video/webm"
    if name.endswith(".avi"):
        return "video/x-msvideo"
    if name.endswith(".mkv"):
        return "video/x-matroska"
    if name.endswith(".3gp"):
        return "video/3gpp"
    if name.endswith(".mpeg") or name.endswith(".mpg"):
        return "video/mpeg"
    return "video/mp4"


def _validate_chat_video(file: UploadFile) -> None:
    name = (file.filename or "").strip()
    ext = Path(name).suffix.lower()
    ctype = (file.content_type or "").strip().lower()
    if ext and ext not in _VIDEO_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Video must be mp4, mov, m4v, webm, avi, mkv, 3gp, or mpeg",
        )
    if not ext and ctype and not ctype.startswith("video/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File is not a video",
        )


class _SizeLimitedReader:
    """Abort an upload stream once it exceeds max_bytes (original bytes, no transcode)."""

    def __init__(self, stream, *, max_bytes: int, label: str):
        self._stream = stream
        self._max_bytes = max_bytes
        self._label = label
        self._seen = 0

    def read(self, amt: int = -1) -> bytes:
        data = self._stream.read(amt)
        if not data:
            return data
        self._seen += len(data)
        if self._seen > self._max_bytes:
            mb = self._max_bytes // (1024 * 1024)
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail=f"{self._label} must be {mb} MB or smaller",
            )
        return data

    def seek(self, offset: int, whence: int = 0) -> int:
        pos = self._stream.seek(offset, whence)
        try:
            self._seen = int(self._stream.tell())
        except Exception:
            self._seen = 0 if offset == 0 and whence == 0 else self._seen
        return pos

    def tell(self) -> int:
        return self._stream.tell()


def _upload_size(file: UploadFile) -> int | None:
    size = getattr(file, "size", None)
    if size is not None:
        try:
            return int(size)
        except (TypeError, ValueError):
            pass
    stream = file.file
    try:
        pos = stream.tell()
        stream.seek(0, 2)
        measured = stream.tell()
        stream.seek(pos)
        return int(measured)
    except Exception:
        return None


def _sized_upload_stream(file: UploadFile, *, max_bytes: int, label: str):
    size = _upload_size(file)
    if size is not None:
        if size <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Empty {label.lower()} file",
            )
        if size > max_bytes:
            mb = max_bytes // (1024 * 1024)
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail=f"{label} must be {mb} MB or smaller",
            )
        return file.file
    return _SizeLimitedReader(file.file, max_bytes=max_bytes, label=label)


def upload_chat_file(
    *,
    file: UploadFile,
    conversation_id: str,
    media_type: str,
) -> str:
    """
    Stream UploadFile to R2 and return the public CDN URL.

    Videos are stored as-is (no transcode) and capped at 200 MB.
    Other chat media has no file-size enforcement.
    """
    if media_type not in ALLOWED_MEDIA_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"media_type must be one of: {MEDIA_TYPE_HELP}",
        )

    if media_type == "video":
        _validate_chat_video(file)

    bucket, public_base = bucket_for(media_type)
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
        elif media_type == "video":
            content_type = _video_content_type(file.filename)
        else:
            content_type = "application/octet-stream"
    elif media_type == "image" and not content_type.startswith("image/"):
        content_type = mimetypes.guess_type(file.filename or "")[0] or "image/jpeg"
    elif media_type == "video" and not content_type.startswith("video/"):
        content_type = _video_content_type(file.filename)

    upload_stream = file.file
    if media_type == "video":
        upload_stream = _sized_upload_stream(
            file,
            max_bytes=CHAT_VIDEO_MAX_BYTES,
            label="Video",
        )

    client = get_r2_client()
    try:
        # Ensure stream is at start
        try:
            upload_stream.seek(0)
        except Exception:
            pass
        client.upload_fileobj(
            upload_stream,
            bucket,
            key,
            ExtraArgs={"ContentType": content_type},
        )
    except HTTPException:
        raise
    except Exception as exc:
        cause = exc.__cause__ or getattr(exc, "__context__", None)
        if isinstance(cause, HTTPException):
            raise cause from exc
        logger.exception("R2 upload failed conversation_id=%s", conversation_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    public_url = _stored_url(public_base, key)
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


def build_patient_asset_key(
    *,
    kind: PatientAssetKind,
    patient_id: str,
    filename: str | None,
    data: bytes,
) -> str:
    """Content-addressed key: the same bytes for the same patient map to one object."""
    ext = Path(filename or "").suffix.lower()
    if kind == "scans" and ext not in _SCAN_EXTENSIONS:
        ext = ext if ext else ".ply"
    elif kind != "scans" and not ext:
        ext = ".jpg"
    return f"patients/{patient_id}/{kind}/{hashlib.sha256(data).hexdigest()}{ext}"


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
    data: bytes,
    filename: str | None,
    content_type: str | None,
    kind: PatientAssetKind,
    patient_id: str,
) -> tuple[str, str, str]:
    """
    Store a patient clinical file in its kind's R2 bucket.

    Re-storing identical bytes overwrites the same object, so repeats never
    pile up. Returns (file_key, public_url, original_filename).
    """
    filename = validate_patient_upload_filename(kind=kind, filename=filename)
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty file",
        )
    bucket, public_base = bucket_for(kind)
    key = build_patient_asset_key(
        kind=kind, patient_id=patient_id, filename=filename, data=data
    )
    content_type = content_type or mimetypes.guess_type(filename)[0] or (
        "application/octet-stream"
    )
    if content_type in ("application/octet-stream", "binary/octet-stream", ""):
        guessed = mimetypes.guess_type(filename)[0]
        content_type = guessed or "application/octet-stream"
    if kind != "scans" and not content_type.startswith("image/"):
        content_type = mimetypes.guess_type(filename)[0] or "image/jpeg"

    client = get_r2_client()
    try:
        client.put_object(Bucket=bucket, Key=key, Body=data, ContentType=content_type)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("R2 patient upload failed kind=%s patient_id=%s", kind, patient_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    public_url = _stored_url(public_base, key)
    logger.debug(
        "R2 patient upload ok kind=%s bucket=%s key=%s",
        kind,
        bucket,
        key,
    )
    return key, public_url, filename


# ── Scan inbox (PC web upload, waiting for a patient) ─────────────────────────

INBOX_MAX_BYTES = 300 * 1024 * 1024
INBOX_EXPIRY_DAYS = 30  # mirror the Cloudflare lifecycle rule on inbox/


def upload_inbox_file(*, file: UploadFile, user_id: str) -> tuple[str, int, str]:
    """Stream a scan to the scans bucket under inbox/{user}/. Returns (key, size, filename)."""
    filename = validate_patient_upload_filename(kind="scans", filename=file.filename)
    stream = _sized_upload_stream(file, max_bytes=INBOX_MAX_BYTES, label="Scan")
    size = _upload_size(file) or 0
    key = f"inbox/{user_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"
    bucket, _ = bucket_for("scans")
    try:
        stream.seek(0)
        get_r2_client().upload_fileobj(stream, bucket, key)
    except HTTPException:
        raise
    except Exception as exc:
        cause = exc.__cause__ or getattr(exc, "__context__", None)
        if isinstance(cause, HTTPException):
            raise cause from exc
        logger.exception("R2 inbox upload failed user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 upload failed: {str(exc).strip() or 'unknown error'}",
        ) from exc
    return key, size, filename


def copy_scan_object(*, src_key: str, dst_key: str) -> None:
    """Server-side copy inside the scans bucket (no bytes through the backend)."""
    bucket, _ = bucket_for("scans")
    try:
        get_r2_client().copy_object(
            Bucket=bucket, Key=dst_key, CopySource={"Bucket": bucket, "Key": src_key}
        )
    except Exception as exc:
        logger.exception("R2 copy failed src=%s", src_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not move the scan to the patient record",
        ) from exc


def delete_patient_asset(*, kind: PatientAssetKind, file_key: str) -> None:
    """Delete an object from the patient-asset R2 bucket. Missing keys are ignored."""
    if not (file_key or "").strip():
        return
    bucket, _ = bucket_for(kind)
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

LOCAL_PHOTO_URL_PREFIX = "/api/media/patient-photos"
LOCAL_PHOTO_ROOT = (
    Path(__file__).resolve().parents[2] / "data" / "uploads" / "patient_photos"
)


def patient_images_r2_configured() -> bool:
    return bool(
        (settings.r2_account_id or "").strip()
        and (settings.r2_access_key_id or "").strip()
        and (settings.r2_secret_access_key or "").strip()
        and (settings.r2_patient_images_bucket or "").strip()
    )


def is_local_patient_photo_url(file_url: str) -> bool:
    return (file_url or "").strip().startswith(f"{LOCAL_PHOTO_URL_PREFIX}/")


def local_patient_photo_path(patient_id: str, filename: str) -> Path | None:
    """Resolve a local photo on disk; reject path traversal."""
    pid = (patient_id or "").strip()
    name = Path(filename or "").name
    if not pid or not name or pid != Path(pid).name:
        return None
    ext = Path(name).suffix.lower()
    if ext not in _IMAGE_EXTENSIONS:
        return None
    return LOCAL_PHOTO_ROOT / pid / name


def _save_local_patient_photo(
    *,
    patient_id: str,
    filename: str,
    data: bytes,
) -> str:
    ext = Path(filename or "").suffix.lower() or ".jpg"
    if ext not in _IMAGE_EXTENSIONS:
        ext = ".jpg"
    name = f"{uuid.uuid4().hex}{ext}"
    dest_dir = LOCAL_PHOTO_ROOT / patient_id
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / name).write_bytes(data)
    url = f"{LOCAL_PHOTO_URL_PREFIX}/{patient_id}/{name}"
    logger.info("local photo stored patient_id=%s file=%s", patient_id, name)
    return url


def _delete_local_patient_photo(file_url: str) -> None:
    url = (file_url or "").strip()
    rest = url[len(LOCAL_PHOTO_URL_PREFIX) + 1 :]
    parts = rest.split("/")
    if len(parts) != 2:
        logger.warning("local photo delete skipped — bad url=%s", url)
        return
    path = local_patient_photo_path(parts[0], parts[1])
    if path is None or not path.is_file():
        return
    try:
        path.unlink()
    except OSError as exc:
        logger.warning("local photo delete failed path=%s detail=%s", path, exc)


def upload_patient_photo_bytes(
    *,
    patient_id: str,
    filename: str,
    data: bytes,
    content_type: str = "image/jpeg",
) -> str:
    """Upload raw photo bytes; return a fetchable URL (R2 or local fallback)."""
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty photo file",
        )
    if not patient_images_r2_configured():
        return _save_local_patient_photo(
            patient_id=patient_id, filename=filename, data=data
        )

    bucket, public_base = bucket_for("photos")
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

    public_url = _stored_url(public_base, key)
    logger.debug("R2 photo upload ok bucket=%s key=%s", bucket, key)
    return public_url


def delete_patient_photo_object(file_url: str) -> None:
    """Delete a patient photo (R2 or local). No-op if empty/unknown."""
    url = (file_url or "").strip()
    if not url:
        return

    if is_local_patient_photo_url(url):
        _delete_local_patient_photo(url)
        return

    if not patient_images_r2_configured():
        logger.warning("R2 photo delete skipped — storage not configured url=%s", url)
        return

    key = file_key_from_patient_photo_url(url)
    if not key:
        logger.warning("R2 photo delete skipped — could not derive key from url=%s", url)
        return

    bucket, _ = bucket_for("photos")
    client = get_r2_client()
    try:
        client.delete_object(Bucket=bucket, Key=key)
    except Exception as exc:
        logger.exception("R2 photo delete failed key=%s detail=%s", key, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"R2 delete failed: {str(exc).strip() or 'unknown error'}",
        ) from exc


def download_r2_object_bytes(bucket: str, key: str) -> bytes:
    """Read an object from R2 into memory."""
    if not (bucket or "").strip() or not (key or "").strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing R2 bucket or object key",
        )
    client = get_r2_client()
    try:
        obj = client.get_object(Bucket=bucket, Key=key)
        body = obj.get("Body")
        data = body.read() if body is not None else b""
    except HTTPException:
        raise
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"File not found in {bucket}",
            ) from exc
        logger.exception("R2 get_object failed bucket=%s key=%s", bucket, key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not read stored file: {str(exc).strip() or 'unknown error'}",
        ) from exc
    except Exception as exc:
        logger.exception("R2 get_object failed bucket=%s key=%s", bucket, key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not read stored file: {str(exc).strip() or 'unknown error'}",
        ) from exc
    if not data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Stored photo is empty",
        )
    return data


def file_key_from_patient_photo_url(file_url: str) -> str:
    """Derive object key from a patient photo public URL."""
    url = (file_url or "").strip()
    if not url:
        return ""
    if is_local_patient_photo_url(url):
        return url[len(LOCAL_PHOTO_URL_PREFIX) + 1 :]
    public = (settings.r2_patient_images_public_url or "").strip().rstrip("/")
    if public and url.startswith(f"{public}/"):
        return url[len(public) + 1 :]
    try:
        from urllib.parse import urlparse

        return (urlparse(url).path or "").lstrip("/")
    except Exception:
        return ""
