"""One-file patient export (GDPR Art. 20): a zip of patient.xml plus the stored files."""

from __future__ import annotations

import re
import tempfile
import unicodedata
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import PurePosixPath
from typing import IO, Any
from xml.etree import ElementTree as ET

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services import patient_access as pa
from app.services.patient_crypto import decrypt_note
from app.services.profiles import fetch_profiles_by_ids
from app.services.shade_media import load_media_bytes

# (file kind, table, XML element per row)
_MEDIA = (
    ("photos", "patient_photos", "photo"),
    ("scans", "patient_scans", "scan"),
    ("shades", "shade_detections", "shade_detection"),
    ("smiles", "smile_previews", "smile_preview"),
)
_PARALLEL_DOWNLOADS = 8
# Storage internals; the export points at files inside the zip instead.
_HIDDEN = frozenset({"file_url", "file_key", "base_file_key", "note_ciphertext"})
_TAG = re.compile(r"^(?![Xx][Mm][Ll])[A-Za-z_][\w.-]*$")
# Characters XML 1.0 can't hold at all; one would make the whole file unreadable.
_XML_INVALID = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f￾￿]")


def _rows(table: str, patient_id: str, order: str = "created_at") -> list[dict[str, Any]]:
    try:
        result = (
            get_supabase_admin()
            .table(table)
            .select("*")
            .eq("patient_id", patient_id)
            .order(order)
            .execute()
        )
    except Exception as exc:
        raise pa.db_error(exc) from exc
    return list(getattr(result, "data", None) or [])


def safe_name(text: str, fallback: str = "file") -> str:
    """ASCII-only, path-free name (Müller → Muller) for zip entries and headers."""
    ascii_text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9.-]+", "_", ascii_text).strip("._") or fallback


def _add(parent: ET.Element, tag: str, value: Any) -> ET.Element:
    """Value as XML: dicts nest, lists repeat <item>, odd keys become <entry key=…>."""
    el = ET.SubElement(parent, tag) if _TAG.match(tag) else ET.SubElement(parent, "entry", key=tag)
    if isinstance(value, dict):
        for k, v in value.items():
            _add(el, str(k), v)
    elif isinstance(value, list):
        for v in value:
            _add(el, "item", v)
    elif value is None:
        el.set("nil", "true")
    elif isinstance(value, bool):
        el.text = "true" if value else "false"
    else:
        el.text = _XML_INVALID.sub("", str(value))
    return el


def _add_row(parent: ET.Element, tag: str, row: dict[str, Any]) -> ET.Element:
    el = ET.SubElement(parent, tag)
    for key, value in row.items():
        if key not in _HIDDEN:
            _add(el, key, value)
    return el


def _file_job(el: ET.Element, kind: str, row: dict[str, Any], tag: str = "file") -> tuple:
    """(element, kind, row, tag, zip path) for one stored file."""
    key = str(row.get("file_key") or row.get("file_url") or "")
    display = str(row.get("file_name") or row.get("filename") or kind)
    # Display names can lack an extension ("Upper smile"); the key never does.
    ext = PurePosixPath(key).suffix.lower()
    path = f"{kind}/{safe_name(PurePosixPath(display).stem, kind)}_{str(row['id'])[:8]}"
    path += "_base" if tag == "base_file" else ""
    path += ext
    return el, kind, row, tag, path


def _fetch(job: tuple) -> bytes | None:
    """The job's file bytes; None when the object is gone (noted, not fatal)."""
    _, kind, row, _, _ = job
    try:
        return load_media_bytes(kind, row)
    except HTTPException as exc:
        if exc.status_code != status.HTTP_404_NOT_FOUND:
            raise
        return None


def build_patient_export(patient: dict[str, Any]) -> tuple[IO[bytes], str, int]:
    """Zip (rewound), download filename, number of files included."""
    pid = str(patient["id"])
    now = datetime.now(timezone.utc)
    root = ET.Element("patient_export", version="1", exported_at=now.isoformat())
    _add_row(root, "patient", patient)

    notes = _rows("patient_notes", pid)
    authors = fetch_profiles_by_ids({str(n.get("author_id") or "") for n in notes})
    notes_el = ET.SubElement(root, "notes")
    for note in notes:
        el = _add_row(notes_el, "note", note)
        _add(el, "author_name", pa.profile_display_name(authors.get(str(note.get("author_id")))))
        _add(el, "content", decrypt_note(note.get("note_ciphertext") or ""))

    appts_el = ET.SubElement(root, "appointments")
    for appt in _rows("appointments", pid, order="start_time"):
        _add_row(appts_el, "appointment", appt)

    jobs = []
    for kind, table, tag in _MEDIA:
        group = ET.SubElement(root, table)
        for row in _rows(table, pid):
            el = _add_row(group, tag, row)
            jobs.append(_file_job(el, kind, row))
            if row.get("base_file_key"):
                jobs.append(_file_job(el, kind, {**row, "file_key": row["base_file_key"]}, "base_file"))

    out = tempfile.SpooledTemporaryFile(max_size=32 * 1024 * 1024)
    files = 0
    with zipfile.ZipFile(out, "w") as zf, ThreadPoolExecutor(_PARALLEL_DOWNLOADS) as pool:
        # Downloads dominate (one at a time: 133 s for 96 files; 8 at once: 8 s).
        # ponytail: map runs ahead of the writer, so a whole patient's files can
        # sit in memory at once; bound the window if exports outgrow RAM.
        for (el, kind, _, tag, path), data in zip(jobs, pool.map(_fetch, jobs)):
            if data is None:
                ET.SubElement(el, tag, missing="true")
                continue
            # Images are already compressed; only scans shrink (~40 %).
            if kind == "scans":
                zf.writestr(path, data, zipfile.ZIP_DEFLATED, compresslevel=1)
            else:
                zf.writestr(path, data, zipfile.ZIP_STORED)
            ET.SubElement(el, tag).text = path
            files += 1
        ET.indent(root)
        zf.writestr("patient.xml", ET.tostring(root, encoding="utf-8", xml_declaration=True),
                    zipfile.ZIP_DEFLATED)
    out.seek(0)

    name = safe_name(f"{patient.get('last_name') or ''}_{patient.get('first_name') or ''}", "patient")
    return out, f"patient_{name}_{now:%Y-%m-%d}.zip", files
