"""Pydantic models for GDPR patient management."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field


class PatientCreateRequest(BaseModel):
    first_name: str = Field(min_length=1, max_length=120)
    last_name: str = Field(min_length=1, max_length=120)
    date_of_birth: date
    address: str = Field(min_length=1)
    phone: str = Field(min_length=1, max_length=64)
    health_insurance: str = Field(min_length=1, max_length=255)


class PatientUpdateRequest(BaseModel):
    fields_to_update: dict[str, Any] = Field(
        ...,
        description="Subset of: first_name, last_name, date_of_birth, address, phone, health_insurance",
    )


class PatientDeleteRequest(BaseModel):
    delete_type: Literal["soft", "hard"] = "soft"


class GrantAccessRequest(BaseModel):
    target_user_id: str = Field(min_length=1)


class RevokeAccessRequest(BaseModel):
    target_user_id: str = Field(min_length=1)


class UploadNoteRequest(BaseModel):
    note_content: str = Field(min_length=1)


class EditNoteRequest(BaseModel):
    new_note_content: str = Field(min_length=1)


class PatientOut(BaseModel):
    id: str
    created_by: str
    first_name: str
    last_name: str
    date_of_birth: date | str
    address: str
    phone: str
    health_insurance: str
    deleted: bool = False
    deleted_at: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class PatientNoteOut(BaseModel):
    id: str
    patient_id: str
    author_id: str
    note_content: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


class AgentError(BaseModel):
    code: str | None = None
    message: str | None = None


class AgentResponse(BaseModel):
    """Canonical agent/API envelope for patient management actions."""

    status: Literal["SUCCESS", "ERROR"]
    http_code: int
    action: str
    authenticated_user_id: str
    target_patient_id: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    error: AgentError | None = None
