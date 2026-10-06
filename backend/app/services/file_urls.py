"""URL the app should use for a stored patient file."""

from __future__ import annotations

from typing import Any

KINDS = ("photos", "scans", "shades", "smiles")


def client_file_url(kind: str, row: dict[str, Any]) -> str:
    """Backend path; the app resolves it and sends its auth header. Buckets are
    private, so a stored URL (old rows) is never handed out."""
    return f"/api/files/{kind}/{row['id']}" if row.get("id") else ""


def client_base_file_url(kind: str, row: dict[str, Any]) -> str | None:
    """Same, for a smile preview's photo without overlays (`base_file_key`)."""
    if not row.get("base_file_key"):
        return None
    return f"/api/files/{kind}/{row['id']}?part=base"
