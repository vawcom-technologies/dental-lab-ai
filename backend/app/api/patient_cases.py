"""Case status endpoints: state, "Submit to lab", and the lab's review."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.core.security import AuthUser, get_current_user
from app.services import case_flow
from app.services import patient_access as pa

router = APIRouter()


class SubmitIn(BaseModel):
    confirm_incomplete: bool = False


class ItemFeedbackIn(BaseModel):
    item: Literal["scan", "shade", "smile"]
    status: Literal["ok", "needs_work"]
    note: str | None = Field(default=None, max_length=2000)


class ReviewIn(BaseModel):
    decision: Literal["approve", "reject"]
    remarks: str | None = Field(default=None, max_length=4000)
    items: list[ItemFeedbackIn] | None = None


def _patient(patient_id: str, user: AuthUser) -> dict:
    return pa.require_patient_access(patient_id, user.id)  # 404 / 403


@router.get("/{patient_id}/case", summary="Case status, what's missing, allowed actions, history")
def get_case(patient_id: str, user: AuthUser = Depends(get_current_user)):
    return case_flow.summary(_patient(patient_id, user), user)


@router.post("/{patient_id}/submit", summary="Submit to lab (409 INCOMPLETE lists missing items)")
def submit_case(patient_id: str, body: SubmitIn, user: AuthUser = Depends(get_current_user)):
    patient = case_flow.submit(_patient(patient_id, user), user, confirm_incomplete=body.confirm_incomplete)
    return case_flow.summary(patient, user)


@router.post("/{patient_id}/review", summary="Lab approves, or rejects with remarks / per-item feedback")
def review_case(patient_id: str, body: ReviewIn, user: AuthUser = Depends(get_current_user)):
    items = [i.model_dump() for i in body.items] if body.items else None
    patient = case_flow.review(
        _patient(patient_id, user),
        user,
        approve=body.decision == "approve",
        remarks=body.remarks,
        items=items,
    )
    return case_flow.summary(patient, user)


class FeedbackDraftIn(ItemFeedbackIn):
    status: Literal["ok", "needs_work"] | None = None  # None clears it


@router.put("/{patient_id}/review-draft", summary="Lab: save its draft verdict for one item while reviewing")
def save_review_draft(patient_id: str, body: FeedbackDraftIn, user: AuthUser = Depends(get_current_user)):
    patient = _patient(patient_id, user)
    case_flow.set_feedback(patient, user, body.item, body.status, body.note)
    return case_flow.summary(pa.fetch_patient(patient_id) or patient, user)


@router.post(
    "/{patient_id}/suggestions/{item}/{action}",
    summary="Owning dentist: accept or dismiss the lab's suggestion for one item",
)
def resolve_suggestion(
    patient_id: str,
    item: Literal["scan", "shade", "smile"],
    action: Literal["accept", "dismiss"],
    user: AuthUser = Depends(get_current_user),
):
    patient = case_flow.resolve_suggestion(_patient(patient_id, user), user, item, accept=action == "accept")
    return case_flow.summary(pa.fetch_patient(patient_id) or patient, user)
