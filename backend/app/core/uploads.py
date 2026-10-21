"""Size-capped upload reads: never pull an unbounded request body into memory."""

from __future__ import annotations

from fastapi import HTTPException, UploadFile, status

IMAGE_MAX_BYTES = 25 * 1024 * 1024
AUDIO_MAX_BYTES = 25 * 1024 * 1024
SCAN_MAX_BYTES = 300 * 1024 * 1024  # same as the scan inbox


async def read_capped(file: UploadFile, max_bytes: int) -> bytes:
    """Read at most [max_bytes]; 413 when the file is bigger."""
    data = await file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            f"File is too large (max {max_bytes // (1024 * 1024)} MB)",
        )
    return data
