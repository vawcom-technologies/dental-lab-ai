"""Pydantic models for patient appointments."""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

AppointmentStatus = Literal[
    "scheduled", "completed", "cancelled", "no_show"
]


class AppointmentCreate(BaseModel):
    patient_id: UUID
    description: str | None = None
    start_time: datetime
    end_time: datetime

    @model_validator(mode="after")
    def _end_after_start(self) -> AppointmentCreate:
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time")
        return self


class AppointmentUpdate(BaseModel):
    description: str | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    status: AppointmentStatus | None = None

    @field_validator("status")
    @classmethod
    def _status_ok(cls, v: str | None) -> str | None:
        return v

    @model_validator(mode="after")
    def _end_after_start_if_both(self) -> AppointmentUpdate:
        if (
            self.start_time is not None
            and self.end_time is not None
            and self.end_time <= self.start_time
        ):
            raise ValueError("end_time must be after start_time")
        return self


class AppointmentResponse(BaseModel):
    id: str
    patient_id: str
    created_by: str
    description: str = ""
    start_time: datetime | str
    end_time: datetime | str
    status: AppointmentStatus | str
    reminder_sent: bool = False
    created_at: datetime | str | None = None
    updated_at: datetime | str | None = None
    patient_name: str
    patient_email: str = Field(min_length=1)
