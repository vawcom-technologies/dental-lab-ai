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


class AccessRequestDecision(BaseModel):
    action: Literal["approve", "reject"]


class RevokeAccessRequest(BaseModel):
    target_user_id: str = Field(min_length=1)


class PendingAccessRequestOut(BaseModel):
    request_id: str
    patient_id: str
    patient_name: str
    target_user_id: str
    target_user_name: str
    requested_by_user_id: str
    requested_by_user_name: str
    status: Literal["pending", "approved", "rejected"]
    created_at: datetime | str | None = None


class PatientAccessEntryOut(BaseModel):
    access_id: str
    user_id: str
    full_name: str
    status: Literal["pending", "approved", "rejected"]
    requested_by_name: str | None = None
    created_at: datetime | str | None = None


class EligibleUserOut(BaseModel):
    user_id: str
    full_name: str
    email: str | None = None


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
    author_name: str = "Unknown Practitioner"
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
