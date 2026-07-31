"""Dental Lab AI — FastAPI application entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import (
    auth,
    patients,
    health,
    exports,
    cases,
    scans,
    photos,
    messages,
    clinical,
    notifications,
    reports,
)
from app.core.database import Base, engine, SessionLocal
from app.core.config import settings
from app.core.security import hash_password
from datetime import date, datetime, timedelta

from app.models import User, Patient, Case, Message, ShadeSelection, Notification
import app.models  # noqa: F401 — register all tables


def migrate_user_profile_columns() -> None:
    """SQLite create_all won't alter existing tables — add profile columns if missing."""
    if not settings.database_url.startswith("sqlite"):
        return
    from sqlalchemy import text

    with engine.begin() as conn:
        cols = {
            row[1]
            for row in conn.execute(text("PRAGMA table_info(users)")).fetchall()
        }
        if "clinic_name" not in cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN clinic_name VARCHAR(255)"))
        if "phone" not in cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN phone VARCHAR(64)"))


def seed_demo_users() -> None:
    db = SessionLocal()
    try:
        if not db.query(User).filter(User.email == "dentist@elitedent.demo").first():
            db.add(
                User(
                    email="dentist@elitedent.demo",
                    name="Elena Hartmann",
                    role="dentist",
                    clinic_name="Elite Dent Praxis München",
                    phone="+49 89 4521 880",
                    password_hash=hash_password("demo1234"),
                )
            )
        if not db.query(User).filter(User.email == "lab@elitedent.demo").first():
            db.add(
                User(
                    email="lab@elitedent.demo",
                    name="Elite Dent Lab",
                    role="lab",
                    clinic_name="Elite Dent Laboratory",
                    phone="+49 89 111111",
                    password_hash=hash_password("demo1234"),
                )
            )
        # Backfill clinic on existing demo rows if empty
        dentist = db.query(User).filter(User.email == "dentist@elitedent.demo").first()
        if dentist:
            if dentist.name in (None, "", "Demo Dentist"):
                dentist.name = "Elena Hartmann"
            if not dentist.clinic_name or dentist.clinic_name == "Elite Dent Practice":
                dentist.clinic_name = "Elite Dent Praxis München"
            if not dentist.phone or dentist.phone in ("+49 89 000000",):
                dentist.phone = "+49 89 4521 880"
        lab = db.query(User).filter(User.email == "lab@elitedent.demo").first()
        if lab and not lab.clinic_name:
            lab.clinic_name = "Elite Dent Laboratory"
            lab.phone = lab.phone or "+49 89 111111"
        db.commit()
    finally:
        db.close()


def _ensure_case(
    db,
    *,
    patient_id: int,
    status: str,
    created_at: datetime,
    updated_at: datetime,
) -> Case:
    case = (
        db.query(Case)
        .filter(Case.patient_id == patient_id)
        .order_by(Case.id.asc())
        .first()
    )
    if case:
        case.status = status
        case.created_at = created_at
        case.updated_at = updated_at
        return case
    case = Case(
        patient_id=patient_id,
        status=status,
        created_at=created_at,
        updated_at=updated_at,
    )
    db.add(case)
    db.flush()
    return case


def seed_demo_clinic_data() -> None:
    """Seed original Elite Dent patients, cases, shades, and lab chat for the demo dentist."""
    db = SessionLocal()
    try:
        dentist = db.query(User).filter(User.email == "dentist@elitedent.demo").first()
        lab = db.query(User).filter(User.email == "lab@elitedent.demo").first()
        if not dentist or not lab:
            return

        now = datetime.utcnow()
        # Idempotent: keyed by last_name + first_name for this dentist
        roster = [
            {
                "first_name": "Marcus",
                "last_name": "Webb",
                "dob": date(1979, 4, 18),
                "address": "Leopoldstraße 42, 80802 München",
                "phone": "+49 171 884 2201",
                "health_insurance": "Techniker Krankenkasse",
                "notes": "FDI #14 zirconia crown. Distal margin underprepared — lab flagged for confirmation.",
                "status": "in_review",
                "created_offset_h": 52,
                "updated_offset_h": 2,
                "shade": ("A2", "A2", False, 0.91),
                "chat": True,
            },
            {
                "first_name": "Anika",
                "last_name": "Vogt",
                "dob": date(1987, 3, 14),
                "address": "Türkenstraße 19, 80333 München",
                "phone": "+49 89 3341 772",
                "health_insurance": "AOK Bayern",
                "notes": "Single-unit #16 lithium disilicate. Intraoral scan received; shade confirmation pending.",
                "status": "in_review",
                "created_offset_h": 30,
                "updated_offset_h": 4,
                "shade": ("A3", "A3.5", True, 0.78),
                "chat": False,
            },
            {
                "first_name": "Jonas",
                "last_name": "Richter",
                "dob": date(1962, 11, 2),
                "address": "Occamstraße 8, 80802 München",
                "phone": "+49 172 550 9188",
                "health_insurance": "Barmer",
                "notes": "Implant #36 — scan body diameter check before custom abutment design.",
                "status": "in_progress",
                "created_offset_h": 18,
                "updated_offset_h": 6,
                "shade": None,
                "chat": False,
            },
            {
                "first_name": "Lena",
                "last_name": "Hofmann",
                "dob": date(1995, 7, 21),
                "address": "Ismaninger Straße 55, 81675 München",
                "phone": "+49 176 402 1190",
                "health_insurance": "DKV",
                "notes": "Porcelain veneers #11–#21 delivered. Patient approved B1 shade match.",
                "status": "completed",
                "created_offset_h": 120,
                "updated_offset_h": 28,
                "shade": ("B1", "B1", False, 0.94),
                "chat": False,
            },
            {
                "first_name": "Marek",
                "last_name": "Novak",
                "dob": date(1978, 9, 9),
                "address": "Rosenheimer Straße 112, 81669 München",
                "phone": "+49 89 4412 903",
                "health_insurance": "IKK classic",
                "notes": "3-unit bridge #24–#26 rejected — occlusal holes and incomplete distal finish line on #26.",
                "status": "rejected",
                "created_offset_h": 96,
                "updated_offset_h": 36,
                "shade": ("A3", "A3", False, 0.86),
                "chat": False,
            },
            {
                "first_name": "Sophie",
                "last_name": "Keller",
                "dob": date(1991, 1, 28),
                "address": "Ainmillerstraße 27, 80801 München",
                "phone": "+49 151 720 6644",
                "health_insurance": "Techniker Krankenkasse",
                "notes": "New patient intake. Planned #21 e.max crown after endo consult next week.",
                "status": "pending",
                "created_offset_h": 8,
                "updated_offset_h": 8,
                "shade": None,
                "chat": False,
            },
            {
                "first_name": "Tobias",
                "last_name": "Brandt",
                "dob": date(1984, 6, 5),
                "address": "Georgenstraße 14, 80799 München",
                "phone": "+49 89 2781 440",
                "health_insurance": "BKK VBU",
                "notes": "Full-contour zirconia #46. Lab milling queue; occlusion check scheduled.",
                "status": "completed",
                "created_offset_h": 200,
                "updated_offset_h": 72,
                "shade": ("A2", "A2", False, 0.89),
                "chat": False,
            },
            {
                "first_name": "Clara",
                "last_name": "Meier",
                "dob": date(2001, 12, 12),
                "address": "Schellingstraße 33, 80799 München",
                "phone": "+49 178 991 3340",
                "health_insurance": "AOK Bayern",
                "notes": "Sports trauma #11. Temporary acrylic in place; final shade photo uploaded this morning.",
                "status": "in_progress",
                "created_offset_h": 14,
                "updated_offset_h": 1,
                "shade": ("A1", "A1", False, 0.88),
                "chat": False,
            },
        ]

        marcus_case: Case | None = None

        for row in roster:
            patient = (
                db.query(Patient)
                .filter(
                    Patient.dentist_id == dentist.id,
                    Patient.first_name == row["first_name"],
                    Patient.last_name == row["last_name"],
                )
                .first()
            )
            if not patient:
                patient = Patient(dentist_id=dentist.id, first_name=row["first_name"], last_name=row["last_name"])
                db.add(patient)
                db.flush()

            patient.dob = row["dob"]
            patient.address = row["address"]
            patient.phone = row["phone"]
            patient.health_insurance = row["health_insurance"]
            patient.notes = row["notes"]
            patient.updated_at = now - timedelta(hours=row["updated_offset_h"])

            created = now - timedelta(hours=row["created_offset_h"])
            updated = now - timedelta(hours=row["updated_offset_h"])
            case = _ensure_case(
                db,
                patient_id=patient.id,
                status=row["status"],
                created_at=created,
                updated_at=updated,
            )

            if row["shade"]:
                ai, final, overridden, conf = row["shade"]
                existing_shade = (
                    db.query(ShadeSelection)
                    .filter(ShadeSelection.case_id == case.id)
                    .order_by(ShadeSelection.id.desc())
                    .first()
                )
                if not existing_shade:
                    db.add(
                        ShadeSelection(
                            case_id=case.id,
                            ai_suggested_shade=ai,
                            confidence_score=conf,
                            final_shade=final,
                            overridden_by_dentist=overridden,
                            created_at=updated,
                        )
                    )

            if row["chat"]:
                marcus_case = case

        if marcus_case is not None:
            existing = db.query(Message).filter(Message.case_id == marcus_case.id).count()
            if existing == 0:
                t0 = now - timedelta(hours=3)
                db.add_all(
                    [
                        Message(
                            case_id=marcus_case.id,
                            sender_id=dentist.id,
                            type="text",
                            body="Uploaded intraoral scan for #14. Prefer shade A2 if AI disagrees.",
                            sent_at=t0,
                        ),
                        Message(
                            case_id=marcus_case.id,
                            sender_id=lab.id,
                            type="text",
                            body="Received — reviewing margins on the distal finish line now.",
                            sent_at=t0 + timedelta(minutes=18),
                        ),
                        Message(
                            case_id=marcus_case.id,
                            sender_id=lab.id,
                            type="text",
                            body="Note: distal margin looks slightly underprepared — please confirm before we mill.",
                            sent_at=t0 + timedelta(minutes=41),
                        ),
                    ]
                )

            # Extra activity for Anika Vogt
            anika = (
                db.query(Patient)
                .filter(
                    Patient.dentist_id == dentist.id,
                    Patient.first_name == "Anika",
                    Patient.last_name == "Vogt",
                )
                .first()
            )
            if anika:
                anika_case = (
                    db.query(Case)
                    .filter(Case.patient_id == anika.id)
                    .order_by(Case.id.asc())
                    .first()
                )
                if anika_case and db.query(Message).filter(Message.case_id == anika_case.id).count() == 0:
                    t1 = now - timedelta(hours=5)
                    db.add_all(
                        [
                            Message(
                                case_id=anika_case.id,
                                sender_id=dentist.id,
                                type="text",
                                body="Shade photo for #16 attached. AI suggested A3 — I lean A3.5 at the cervical.",
                                sent_at=t1,
                            ),
                            Message(
                                case_id=anika_case.id,
                                sender_id=lab.id,
                                type="text",
                                body="Noted. We'll fabricate to A3.5 cervical with A3 body blend.",
                                sent_at=t1 + timedelta(minutes=27),
                            ),
                        ]
                    )

        db.commit()
    finally:
        db.close()


def seed_demo_notifications() -> None:
    """Build the demo dentist inbox from real clinic cases / chat / shades.

    Replaces any previous demo notifications so the inbox stays clinically useful
    (needs scan, rejected rescan, lab review, shade confirm, unread lab chat).
    """
    from app.services.notify import message_for_status, patient_display_name

    db = SessionLocal()
    try:
        dentist = db.query(User).filter(User.email == "dentist@elitedent.demo").first()
        lab = db.query(User).filter(User.email == "lab@elitedent.demo").first()
        if not dentist:
            return

        # Refresh demo inbox from current clinic truth (not generic placeholders).
        db.query(Notification).filter(Notification.user_id == dentist.id).delete(
            synchronize_session=False
        )

        now = datetime.utcnow()
        cases = (
            db.query(Case)
            .join(Patient)
            .filter(Patient.dentist_id == dentist.id)
            .order_by(Case.updated_at.desc())
            .all()
        )

        # Stagger timestamps so the inbox reads as a real timeline.
        mins = 8
        for case in cases:
            patient = (
                db.query(Patient).filter(Patient.id == case.patient_id).first()
            )
            name = patient_display_name(patient)
            notes = patient.notes if patient else None
            status = (case.status or "pending").lower()

            if status == "pending":
                ntype, message = message_for_status(name, "pending", notes)
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type=ntype,
                        message=message,
                        read=False,
                        created_at=now - timedelta(minutes=mins),
                    )
                )
                mins += 25
            elif status == "rejected":
                ntype, message = message_for_status(name, "rejected", notes)
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type=ntype,
                        message=message,
                        read=False,
                        created_at=now - timedelta(minutes=mins),
                    )
                )
                mins += 35
            elif status == "in_review":
                ntype, message = message_for_status(name, "in_review", notes)
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type=ntype,
                        message=message,
                        read=False,
                        created_at=now - timedelta(minutes=mins),
                    )
                )
                mins += 40
            elif status == "in_progress":
                # Implant / scan-body work gets a specific prompt; others a soft status.
                if notes and "scan body" in notes.lower():
                    db.add(
                        Notification(
                            user_id=dentist.id,
                            case_id=case.id,
                            type="scan_body",
                            message=(
                                f"{name}: confirm scan body diameter / platform "
                                "before abutment design."
                            ),
                            read=False,
                            created_at=now - timedelta(minutes=mins),
                        )
                    )
                else:
                    db.add(
                        Notification(
                            user_id=dentist.id,
                            case_id=case.id,
                            type="case_status",
                            message=f"{name}'s case is in progress — shade or scan may still be needed.",
                            read=True,
                            created_at=now - timedelta(minutes=mins),
                        )
                    )
                mins += 45
            elif status == "completed":
                ntype, message = message_for_status(name, "completed", notes)
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type=ntype,
                        message=message,
                        read=True,
                        created_at=now - timedelta(minutes=mins + 200),
                    )
                )
                mins += 20

            # Shade confirmation when dentist overrode AI
            shade = (
                db.query(ShadeSelection)
                .filter(ShadeSelection.case_id == case.id)
                .order_by(ShadeSelection.id.desc())
                .first()
            )
            if shade and shade.overridden_by_dentist:
                ai = shade.ai_suggested_shade or "?"
                final = shade.final_shade or "?"
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type="shade",
                        message=(
                            f"Shade for {name}: AI suggested {ai} — you confirmed "
                            f"{final}. Lab will fabricate to the final shade."
                        ),
                        read=False,
                        created_at=now - timedelta(minutes=mins),
                    )
                )
                mins += 30
            elif shade and shade.confidence_score is not None and shade.confidence_score < 0.85:
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=case.id,
                        type="shade",
                        message=(
                            f"Low-confidence shade for {name} "
                            f"({shade.ai_suggested_shade or shade.final_shade}) — "
                            "re-check photos if the case is still open."
                        ),
                        read=status == "completed",
                        created_at=now - timedelta(minutes=mins),
                    )
                )
                mins += 30

        # Unread lab chat → message notifications (mirror real Message rows)
        if lab:
            lab_messages = (
                db.query(Message)
                .join(Case)
                .join(Patient)
                .filter(
                    Patient.dentist_id == dentist.id,
                    Message.sender_id == lab.id,
                    Message.read_at.is_(None),
                )
                .order_by(Message.sent_at.desc())
                .all()
            )
            # One notification per case from the latest unread lab message
            seen_cases: set[int] = set()
            for msg in lab_messages:
                if msg.case_id in seen_cases:
                    continue
                seen_cases.add(msg.case_id)
                patient = (
                    db.query(Patient)
                    .join(Case)
                    .filter(Case.id == msg.case_id)
                    .first()
                )
                name = patient_display_name(patient)
                preview = (msg.body or "[attachment]").strip()
                if len(preview) > 90:
                    preview = f"{preview[:87]}…"
                db.add(
                    Notification(
                        user_id=dentist.id,
                        case_id=msg.case_id,
                        type="message",
                        message=f"{lab.name} · {name}: {preview}",
                        read=False,
                        created_at=msg.sent_at or (now - timedelta(minutes=12)),
                    )
                )

        db.commit()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    migrate_user_profile_columns()
    seed_demo_users()
    seed_demo_clinic_data()
    seed_demo_notifications()
    yield


app = FastAPI(
    title="Dental Lab AI API",
    version="0.2.0",
    description="Elite Dent — dentist iPad + lab API (full schema scaffold)",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(patients.router, prefix="/api/patients", tags=["patients"])
app.include_router(cases.router, prefix="/api/cases", tags=["cases"])
app.include_router(scans.router, prefix="/api/cases", tags=["scans"])
app.include_router(photos.router, prefix="/api/cases", tags=["photos"])
app.include_router(messages.router, prefix="/api/cases", tags=["messages"])
app.include_router(messages.inbox_router, prefix="/api/messages", tags=["messages"])
app.include_router(notifications.router, prefix="/api/notifications", tags=["notifications"])
app.include_router(clinical.router, prefix="/api/cases", tags=["clinical"])
app.include_router(exports.router, prefix="/api/exports", tags=["exports"])
app.include_router(reports.router, prefix="/api/reports", tags=["reports"])

try:
    from app.api import ai_poc

    app.include_router(ai_poc.router, prefix="/api/ai", tags=["ai-poc"])
except Exception as exc:  # pragma: no cover
    print(f"AI POC routes not loaded: {exc}")
