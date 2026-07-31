"""Create in-app notifications for dentists / lab users."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from app.models import User, Case, Patient, Notification


def patient_display_name(patient: Patient | None) -> str:
    if not patient:
        return "Patient"
    name = f"{patient.first_name or ''} {patient.last_name or ''}".strip()
    return name or "Patient"


def notify(
    db: Session,
    *,
    user_id: int,
    type: str,
    message: str,
    case_id: int | None = None,
    read: bool = False,
    created_at: datetime | None = None,
) -> Notification:
    row = Notification(
        user_id=user_id,
        case_id=case_id,
        type=type,
        message=message,
        read=read,
    )
    if created_at is not None:
        row.created_at = created_at
    db.add(row)
    return row


def notify_case_dentist(
    db: Session,
    case: Case,
    *,
    type: str,
    message: str,
    exclude_user_id: int | None = None,
    read: bool = False,
    created_at: datetime | None = None,
) -> Notification | None:
    """Notify the owning dentist for a case (skip actor when provided)."""
    patient = case.patient
    if patient is None:
        patient = db.query(Patient).filter(Patient.id == case.patient_id).first()
    if not patient:
        return None
    if exclude_user_id is not None and patient.dentist_id == exclude_user_id:
        return None
    return notify(
        db,
        user_id=patient.dentist_id,
        type=type,
        message=message,
        case_id=case.id,
        read=read,
        created_at=created_at,
    )


def notify_lab_users(
    db: Session,
    *,
    type: str,
    message: str,
    case_id: int | None = None,
    exclude_user_id: int | None = None,
) -> list[Notification]:
    labs = db.query(User).filter(User.role == "lab").all()
    out: list[Notification] = []
    for lab in labs:
        if exclude_user_id is not None and lab.id == exclude_user_id:
            continue
        out.append(
            notify(
                db,
                user_id=lab.id,
                type=type,
                message=message,
                case_id=case_id,
            )
        )
    return out


def message_for_status(patient_name: str, status: str, notes: str | None = None) -> tuple[str, str]:
    """Return (notification_type, message) for a case status."""
    note = (notes or "").strip()
    short = note if len(note) <= 90 else f"{note[:87]}…"

    if status == "pending":
        return (
            "case_status",
            f"{patient_name} needs an intraoral scan before the lab can start.",
        )
    if status == "rejected":
        detail = f" {short}" if short else " Rescan required before remake."
        return (
            "scan_quality",
            f"Scan rejected for {patient_name}.{detail}",
        )
    if status == "in_review":
        return (
            "case_status",
            f"{patient_name}'s case is in lab review — check messages if a reply is needed.",
        )
    if status == "in_progress":
        return (
            "case_status",
            f"{patient_name}'s case is in progress at the lab.",
        )
    if status == "completed":
        return (
            "case_status",
            f"Case completed for {patient_name}.",
        )
    return ("case_status", f"Case updated for {patient_name} → {status}.")


def notify_status_change(
    db: Session,
    case: Case,
    *,
    old_status: str | None,
    new_status: str,
    actor: User,
) -> Notification | None:
    if not new_status or new_status == old_status:
        return None

    patient = case.patient
    if patient is None:
        patient = db.query(Patient).filter(Patient.id == case.patient_id).first()
    name = patient_display_name(patient)
    ntype, message = message_for_status(name, new_status, patient.notes if patient else None)

    # Dentist changing their own chip shouldn't spam their inbox — except
    # rejected / pending which are action-critical if somehow set.
    if actor.role == "dentist" and new_status not in ("rejected", "pending"):
        # Still tell the lab something moved
        notify_lab_users(
            db,
            type=ntype,
            message=f"{actor.name or 'Dentist'}: {message}",
            case_id=case.id,
            exclude_user_id=actor.id,
        )
        return None

    return notify_case_dentist(
        db,
        case,
        type=ntype,
        message=message,
        exclude_user_id=actor.id if actor.role == "dentist" else None,
    )
