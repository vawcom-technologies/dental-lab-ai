"""Pydantic models for patient clinical media (scans, shades, smiles)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class PatientScanOut(BaseModel):
    id: str
    patient_id: str
    uploaded_by: str
    file_key: str
    file_url: str
    file_name: str
    format: str = ""
    created_at: datetime | str | None = None


class ShadeDetectionOut(BaseModel):
    id: str
    patient_id: str
    uploaded_by: str
    file_key: str
    file_url: str
    file_name: str
    created_at: datetime | str | None = None


class SmilePreviewOut(BaseModel):
    id: str
    patient_id: str
    uploaded_by: str
    file_key: str
    file_url: str
    file_name: str
    created_at: datetime | str | None = None


class DeleteOkOut(BaseModel):
    deleted: bool = True
    id: str = Field(description="Deleted record id")
