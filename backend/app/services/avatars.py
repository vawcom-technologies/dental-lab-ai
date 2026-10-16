"""Profile photos: private R2 objects served through /api/media/avatars/{name}.

Each upload gets a new random name, so `profiles.avatar_url` changes whenever
the photo does and the app never shows a stale cached image.
"""

from __future__ import annotations

import logging
import re
import secrets

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services.r2 import bucket_for, get_r2_client

logger = logging.getLogger("app.avatars")

MAX_BYTES = 5 * 1024 * 1024
URL_PREFIX = "/api/media/avatars/"
_MAGIC = {"image/jpeg": (b"\xff\xd8\xff", "jpg"), "image/png": (b"\x89PNG\r\n\x1a\n", "png")}
_NAME = re.compile(r"^[0-9a-f-]{36}-[0-9a-f]{12}\.(jpg|png)$")


def sniff(data: bytes, declared: str | None = None) -> str:
    """Content type from the file's own bytes (JPEG or PNG only). Raises 400/413."""
    if not data:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Profile photo is empty")
    if len(data) > MAX_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Profile photo must be 5 MB or smaller")
    found = next((ct for ct, (magic, _) in _MAGIC.items() if data.startswith(magic)), None)
    if found is None or (declared and declared != found):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Profile photo must be a JPEG or PNG image")
    return found


def _key(name: str) -> str:
    return f"avatars/{name}"


def delete(avatar_url: str | None) -> None:
    """Best effort: a leftover object is harmless, a failed account action is not."""
    name = (avatar_url or "").removeprefix(URL_PREFIX)
    if not _NAME.match(name):
        return
    try:
        get_r2_client().delete_object(Bucket=bucket_for("avatars"), Key=_key(name))
    except Exception as exc:
        logger.warning("avatar delete skipped name=%s detail=%s", name, exc)


def store(user_id: str, data: bytes, declared: str | None = None) -> str:
    """Upload a new photo; returns its avatar_url. Doesn't touch the profile."""
    content_type = sniff(data, declared)
    name = f"{user_id}-{secrets.token_hex(6)}.{_MAGIC[content_type][1]}"
    try:
        get_r2_client().put_object(
            Bucket=bucket_for("avatars"), Key=_key(name), Body=data, ContentType=content_type
        )
    except Exception as exc:
        logger.exception("avatar upload failed user_id=%s", user_id)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Could not store the profile photo") from exc
    return URL_PREFIX + name


def replace(profile: dict, data: bytes, declared: str | None = None) -> str:
    """Store a new photo on the profile, then remove the old one."""
    url = store(str(profile["id"]), data, declared)
    try:
        get_supabase_admin().table("profiles").update({"avatar_url": url}).eq("id", str(profile["id"])).execute()
    except Exception as exc:
        delete(url)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Could not save the profile photo") from exc
    delete(profile.get("avatar_url"))
    return url


def load(name: str) -> tuple[bytes, str]:
    if not _NAME.match(name):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
    try:
        obj = get_r2_client().get_object(Bucket=bucket_for("avatars"), Key=_key(name))
    except Exception as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found") from exc
    return obj["Body"].read(), "image/png" if name.endswith(".png") else "image/jpeg"
