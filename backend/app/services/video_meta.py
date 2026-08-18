"""Read duration from MP4 / QuickTime without transcoding the file."""

from __future__ import annotations

import logging
from typing import BinaryIO

from fastapi import UploadFile

logger = logging.getLogger("app.video_meta")


def probe_video_duration_seconds(file: UploadFile) -> float | None:
    stream = getattr(file, "file", None)
    if stream is None:
        return None
    try:
        pos = stream.tell()
    except Exception:
        return None
    try:
        stream.seek(0)
        seconds = _duration_from_iso_bmff(stream)
        if seconds is not None and seconds > 0:
            return seconds
        return None
    except Exception:
        logger.debug("video duration probe failed filename=%s", file.filename)
        return None
    finally:
        try:
            stream.seek(pos)
        except Exception:
            try:
                stream.seek(0)
            except Exception:
                pass


def _read(stream: BinaryIO, n: int) -> bytes:
    data = stream.read(n)
    return data if len(data) == n else b""


def _u32(data: bytes, offset: int = 0) -> int:
    return int.from_bytes(data[offset : offset + 4], "big")


def _u64(data: bytes, offset: int = 0) -> int:
    return int.from_bytes(data[offset : offset + 8], "big")


def _duration_from_iso_bmff(stream: BinaryIO) -> float | None:
    """Walk top-level boxes looking for moov/mvhd (mp4, m4v, mov)."""
    limit = 0
    try:
        stream.seek(0, 2)
        limit = stream.tell()
        stream.seek(0)
    except Exception:
        limit = 0

    while True:
        header = _read(stream, 8)
        if len(header) < 8:
            return None
        size = _u32(header, 0)
        box_type = header[4:8]
        header_len = 8
        if size == 1:
            ext = _read(stream, 8)
            if len(ext) < 8:
                return None
            size = _u64(ext)
            header_len = 16
        if size == 0:
            return None
        payload = size - header_len
        if payload < 0:
            return None
        if box_type in (b"moov", b"trak", b"mdia"):
            nested = _read(stream, payload)
            if len(nested) < payload:
                return None
            found = _duration_in_buffer(nested)
            if found is not None:
                return found
            continue
        if box_type == b"mvhd":
            nested = _read(stream, payload)
            return _mvhd_seconds(nested)
        if limit and stream.tell() + payload > limit:
            return None
        try:
            stream.seek(payload, 1)
        except Exception:
            leftover = _read(stream, payload)
            if len(leftover) < payload:
                return None


def _duration_in_buffer(data: bytes) -> float | None:
    offset = 0
    end = len(data)
    while offset + 8 <= end:
        size = _u32(data, offset)
        box_type = data[offset + 4 : offset + 8]
        header_len = 8
        if size == 1:
            if offset + 16 > end:
                return None
            size = _u64(data, offset + 8)
            header_len = 16
        if size < header_len:
            return None
        payload_off = offset + header_len
        payload_end = offset + size
        if payload_end > end:
            return None
        payload = data[payload_off:payload_end]
        if box_type == b"mvhd":
            return _mvhd_seconds(payload)
        if box_type in (b"moov", b"trak", b"mdia"):
            found = _duration_in_buffer(payload)
            if found is not None:
                return found
        offset = payload_end
    return None


def _mvhd_seconds(payload: bytes) -> float | None:
    if len(payload) < 20:
        return None
    version = payload[0]
    if version == 1:
        if len(payload) < 32:
            return None
        timescale = _u32(payload, 20)
        duration = _u64(payload, 24)
    else:
        timescale = _u32(payload, 12)
        duration = _u32(payload, 16)
    if timescale <= 0 or duration <= 0:
        return None
    return duration / timescale
