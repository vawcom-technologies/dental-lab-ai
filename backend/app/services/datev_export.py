"""DATEV-like XML export (Week 1/2 skeleton).

Based on client sample in references/datev/datev_demo.xml.
Not yet validated against official DATEV XSD.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from datetime import date, datetime
from typing import Any
from xml.dom import minidom

DATEV_NS = "http://www.datev.de/schema"
NS = {"datev": DATEV_NS}


def _tag(name: str) -> str:
    return f"{{{DATEV_NS}}}{name}"


def build_patient_datev_xml(
    patient: dict[str, Any],
    *,
    invoice_number: str | None = None,
    amount_eur: str | None = None,
    creator: str = "EliteDent-LabAI",
) -> bytes:
    """Build a DATEV-like Document XML from a patient record."""
    ET.register_namespace("datev", DATEV_NS)

    root = ET.Element(_tag("Document"))

    header = ET.SubElement(root, _tag("Header"))
    ET.SubElement(header, _tag("Version")).text = "1.0"
    ET.SubElement(header, _tag("CreationDate")).text = str(date.today())
    ET.SubElement(header, _tag("Creator")).text = creator

    data = ET.SubElement(root, _tag("Data"))
    invoice = ET.SubElement(data, _tag("Invoice"))

    inv_no = invoice_number or f"CASE-{patient.get('id', '0')}-{date.today().strftime('%Y%m%d')}"
    ET.SubElement(invoice, _tag("InvoiceNumber")).text = inv_no
    ET.SubElement(invoice, _tag("InvoiceDate")).text = str(date.today())

    customer = ET.SubElement(invoice, _tag("Customer"))
    full_name = f"{patient.get('first_name', '')} {patient.get('last_name', '')}".strip()
    ET.SubElement(customer, _tag("Name")).text = full_name or "Unknown"
    ET.SubElement(customer, _tag("Address")).text = patient.get("address") or ""

    # Dental extensions (custom — outside strict invoice demo; keep under Invoice)
    dental = ET.SubElement(invoice, _tag("DentalCase"))
    if patient.get("dob"):
        dob = patient["dob"]
        ET.SubElement(dental, _tag("DateOfBirth")).text = (
            dob.isoformat() if hasattr(dob, "isoformat") else str(dob)
        )
    if patient.get("phone"):
        ET.SubElement(dental, _tag("Phone")).text = str(patient["phone"])
    if patient.get("health_insurance"):
        ET.SubElement(dental, _tag("HealthInsurance")).text = str(patient["health_insurance"])
    if patient.get("notes"):
        ET.SubElement(dental, _tag("Notes")).text = str(patient["notes"])
    ET.SubElement(dental, _tag("PatientId")).text = str(patient.get("id", ""))
    ET.SubElement(dental, _tag("DentistId")).text = str(patient.get("dentist_id", ""))
    ET.SubElement(dental, _tag("ExportedAt")).text = datetime.utcnow().isoformat() + "Z"

    if amount_eur is not None:
        amount = ET.SubElement(invoice, _tag("Amount"), currency="EUR")
        amount.text = amount_eur

    rough = ET.tostring(root, encoding="utf-8")
    pretty = minidom.parseString(rough).toprettyxml(indent="  ", encoding="utf-8")
    return pretty


def write_demo_xml(path: str) -> None:
    """Recreate the client demo sample."""
    xml = build_patient_datev_xml(
        {
            "id": 0,
            "dentist_id": 0,
            "first_name": "Max",
            "last_name": "Mustermann",
            "address": "Musterstraße 1, 12345 Musterstadt",
        },
        invoice_number="RE-2026-001",
        amount_eur="1500.00",
        creator="MeinProgramm",
    )
    # Align CreationDate/InvoiceDate with the provided sample when regenerating demo
    text = xml.decode("utf-8")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
