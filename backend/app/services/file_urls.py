"""URL the app should use for a stored patient file."""

from __future__ import annotations

from typing import Any

from app.core.config import settings

KINDS = ("photos", "scans", "shades", "smiles")


def private_kinds() -> set[str]:
    return {k.strip() for k in settings.private_file_kinds.split(",") if k.strip()}


def client_file_url(kind: str, row: dict[str, Any]) -> str:
    """Backend path for private kinds (app resolves it and sends its auth
    header), otherwise the stored public URL."""
    if kind in private_kinds() and row.get("id"):
        return f"/api/files/{kind}/{row['id']}"
    return str(row.get("file_url") or "")


def client_base_file_url(kind: str, row: dict[str, Any]) -> str | None:
    """Same, for a smile preview's photo without overlays (`base_file_key`)."""
    key = str(row.get("base_file_key") or "")
    if not key:
        return None
    if kind in private_kinds():
        return f"/api/files/{kind}/{row['id']}?part=base"
    public = (settings.r2_smiles_public_url or "").rstrip("/")
    return f"{public}/{key}"
