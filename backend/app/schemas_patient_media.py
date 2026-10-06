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
    validation_result: str | None = None
    prompt_rescan: bool = False
    reasons: list[str] = Field(default_factory=list)
    issues: list[dict] = Field(default_factory=list)


class ShadeDetectionOut(BaseModel):
    id: str
    patient_id: str
    uploaded_by: str
    file_key: str
    file_url: str
    file_name: str
    created_at: datetime | str | None = None
    analysis: dict | None = None


class SmilePreviewOut(BaseModel):
    id: str
    patient_id: str
    uploaded_by: str
    file_key: str
    file_url: str
    file_name: str
    created_at: datetime | str | None = None
    # Photo without overlays + shape placements, for reopening (migration 014).
    base_file_url: str | None = None
    overlay: dict | None = None


class DeleteOkOut(BaseModel):
    deleted: bool = True
    id: str = Field(description="Deleted record id")
