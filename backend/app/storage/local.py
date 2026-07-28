"""Local encrypted file storage (dev). Swap for EU S3/Supabase in prod."""

from pathlib import Path

from app.core.encryption import encrypt_bytes, decrypt_bytes

STORAGE_ROOT = Path(__file__).resolve().parents[2] / "data" / "uploads"


def save_case_file(case_id: int, kind: str, filename: str, data: bytes) -> Path:
    """Encrypt at rest, store with .enc suffix."""
    safe_name = Path(filename).name.replace("..", "_")
    dest_dir = STORAGE_ROOT / f"case_{case_id}" / kind
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{safe_name}.enc"
    dest.write_bytes(encrypt_bytes(data))
    return dest


def read_case_file(path: Path | str) -> bytes:
    return decrypt_bytes(Path(path).read_bytes())
