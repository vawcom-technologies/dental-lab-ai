"""Pydantic models for GDPR patient management."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, EmailStr, Field, field_validator


PatientStatus = Literal[
    "pending", "in_progress", "in_review", "completed", "rejected"
]

_PATIENT_STATUSES = frozenset(
    {"pending", "in_progress", "in_review", "completed", "rejected"}
)


def normalize_patient_status(raw: Any) -> PatientStatus:
    value = str(raw or "pending").strip().lower()
    if value == "awaiting_scan":
        return "pending"
    if value == "complete":
        return "completed"
    if value in _PATIENT_STATUSES:
        return value  # type: ignore[return-value]
    return "pending"


class PatientCreateRequest(BaseModel):
    first_name: str = Field(min_length=1, max_length=120)
    last_name: str = Field(min_length=1, max_length=120)
    date_of_birth: date
    email: EmailStr
    address: str = Field(min_length=1)
    phone: str = Field(min_length=1, max_length=64)
    health_insurance: str = Field(min_length=1, max_length=255)
    status: PatientStatus = "pending"

    @field_validator("email")
    @classmethod
    def _email_required(cls, v: EmailStr) -> str:
        email = str(v).strip()
        if not email:
            raise ValueError("email is required")
        return email.lower()

    @field_validator("status", mode="before")
    @classmethod
    def _normalize_status(cls, v: Any) -> PatientStatus:
        return normalize_patient_status(v)


class PatientUpdateRequest(BaseModel):
    fields_to_update: dict[str, Any] = Field(
        ...,
        description=(
            "Subset of: first_name, last_name, date_of_birth, email, "
            "address, phone, health_insurance, status"
        ),
    )

    @field_validator("fields_to_update")
    @classmethod
    def _validate_email_if_present(cls, fields: dict[str, Any]) -> dict[str, Any]:
        out = dict(fields)
        if "email" in out:
            raw = out.get("email")
            if raw is None:
                raise ValueError("email cannot be null")
            email = str(raw).strip()
            if not email:
                raise ValueError("email cannot be empty")
            from pydantic import TypeAdapter

            validated = TypeAdapter(EmailStr).validate_python(email)
            out["email"] = str(validated).strip().lower()
        if "status" in out:
            out["status"] = normalize_patient_status(out.get("status"))
        return out


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


class RenamePatientPhotoRequest(BaseModel):
    filename: str = Field(min_length=1, max_length=200)


class PatientOut(BaseModel):
    id: str
    created_by: str
    first_name: str
    last_name: str
    date_of_birth: date | str
    email: str
    address: str
    phone: str
    health_insurance: str
    status: PatientStatus = "pending"
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
