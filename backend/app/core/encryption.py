"""AES-256 (Fernet) encryption for files at rest (GDPR)."""

from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


def _fernet(key: bytes | None = None) -> Fernet:
    raw = key or settings.secret_key.encode("utf-8")
    # Derive a 32-byte url-safe key from secret
    digest = hashlib.sha256(raw).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_bytes(plaintext: bytes, key: bytes | None = None) -> bytes:
    return _fernet(key).encrypt(plaintext)


def decrypt_bytes(ciphertext: bytes, key: bytes | None = None) -> bytes:
    try:
        return _fernet(key).decrypt(ciphertext)
    except InvalidToken as exc:
        raise ValueError("Unable to decrypt file — wrong key or corrupted data") from exc
