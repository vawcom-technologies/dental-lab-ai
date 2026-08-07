"""Fernet encryption for patient clinical notes (never store/log plaintext)."""

from __future__ import annotations

import base64
import hashlib
import logging

from cryptography.fernet import Fernet, InvalidToken
from fastapi import HTTPException, status

from app.core.config import settings

logger = logging.getLogger("app.patient_crypto")


def _fernet() -> Fernet:
    raw = (settings.patient_notes_encryption_key or "").strip()
    if not raw:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PATIENT_NOTES_ENCRYPTION_KEY is not configured",
        )
    digest = hashlib.sha256(raw.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_note(plaintext: str) -> str:
    """Encrypt clinical note text → URL-safe ciphertext string for DB storage."""
    if plaintext is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="note_content is required",
        )
    token = _fernet().encrypt(plaintext.encode("utf-8"))
    return token.decode("ascii")


def decrypt_note(ciphertext: str) -> str:
    """Decrypt note ciphertext for authorized readers only."""
    if not ciphertext:
        return ""
    try:
        return _fernet().decrypt(ciphertext.encode("ascii")).decode("utf-8")
    except (InvalidToken, ValueError) as exc:
        logger.warning("note decrypt failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to decrypt clinical note",
        ) from exc
