"""Patient export: one zip with patient.xml + files, owner only."""

import io
import zipfile
from xml.etree import ElementTree as ET

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api import patients_gdpr
from app.core.security import AuthUser, get_current_user
from app.services import patient_export as pe

PATIENT = {"id": "p1", "created_by": "u1", "first_name": "Anna", "last_name": "Müller", "deleted": False}
ROWS = {
    "patient_notes": [{"id": "n1", "patient_id": "p1", "author_id": "u1", "note_ciphertext": "CIPHER"}],
    "appointments": [{"id": "a1", "patient_id": "p1", "start_time": "2026-10-20T09:00:00Z"}],
    "patient_photos": [{"id": "ph1", "patient_id": "p1", "filename": "front.jpg", "file_url": "patients/p1/photos/x.jpg"}],
    "patient_scans": [{"id": "s1", "patient_id": "p1", "file_name": "Upper jaw", "file_key": "patients/p1/scans/k.stl"}],
    "shade_detections": [
        {"id": "sh1", "patient_id": "p1", "file_key": "patients/p1/shades/gone.jpg", "result": {"11": "A2", "zones": ["c", "m"]}}
    ],
    "smile_previews": [
        {"id": "sm1", "patient_id": "p1", "file_key": "patients/p1/smiles/o.png", "base_file_key": "patients/p1/smiles/b.png"}
    ],
}
FILES = {"patients/p1/photos/x.jpg": b"JPG", "patients/p1/scans/k.stl": b"MESH", "patients/p1/smiles/o.png": b"O", "patients/p1/smiles/b.png": b"B"}


@pytest.fixture
def client(monkeypatch):
    def load(kind, row):
        key = row.get("file_key") or row.get("file_url")
        if key not in FILES:
            raise HTTPException(404, "File not found")
        return FILES[key]

    monkeypatch.setattr(pe, "_rows", lambda table, pid, order="created_at": ROWS[table])
    monkeypatch.setattr(pe, "fetch_profiles_by_ids", lambda ids: {"u1": {"name": "Dr. Who"}})
    monkeypatch.setattr(pe, "decrypt_note", lambda c: "secret\x00 note")
    monkeypatch.setattr(pe, "load_media_bytes", load)
    monkeypatch.setattr(patients_gdpr.pa, "fetch_patient", lambda pid: PATIENT if pid == "p1" else None)
    audit = []
    monkeypatch.setattr(patients_gdpr.pa, "write_audit_log", lambda **kw: audit.append(kw))

    app = FastAPI()
    app.include_router(patients_gdpr.router, prefix="/api/patients")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    c = TestClient(app)
    c.audit = audit
    return c


def test_export_is_one_zip_with_xml_and_files(client):
    r = client.get("/api/patients/p1/export")
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/zip"
    assert 'filename="patient_Muller_Anna_' in r.headers["content-disposition"]

    zf = zipfile.ZipFile(io.BytesIO(r.content))
    root = ET.fromstring(zf.read("patient.xml"))
    assert root.findtext("patient/last_name") == "Müller"
    assert root.findtext("notes/note/content") == "secret note"  # control char stripped
    assert root.findtext("notes/note/author_name") == "Dr. Who"
    assert root.findtext("appointments/appointment/start_time") == "2026-10-20T09:00:00Z"
    assert root.find("shade_detections/shade_detection/result/entry[@key='11']").text == "A2"
    assert [i.text for i in root.findall("shade_detections/shade_detection/result/zones/item")] == ["c", "m"]

    # Storage keys and ciphertext never leave; files are referenced by zip path.
    xml = zf.read("patient.xml").decode()
    assert "CIPHER" not in xml and "patients/p1/" not in xml
    scan_path = root.findtext("patient_scans/scan/file")
    assert scan_path == "scans/Upper_jaw_s1.stl" and zf.read(scan_path) == b"MESH"
    assert zf.read(root.findtext("patient_photos/photo/file")) == b"JPG"
    assert zf.read(root.findtext("smile_previews/smile_preview/base_file")) == b"B"
    # A missing object is noted, not fatal.
    assert root.find("shade_detections/shade_detection/file").get("missing") == "true"

    assert client.audit == [{"actor_id": "u1", "action": "patient.export", "patient_id": "p1", "details": {"files": 4}}]


def test_only_owner_can_export(client):
    client.app.dependency_overrides[get_current_user] = lambda: AuthUser("u2", "b@b.c", "B", "dentist")
    assert client.get("/api/patients/p1/export").status_code == 403
    assert client.get("/api/patients/nope/export").status_code == 404
    assert client.audit == []
