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
)
from app.core.database import Base, engine, SessionLocal
from app.core.security import hash_password
from app.models import User, Patient, Case, Message
import app.models  # noqa: F401 — register all tables


def seed_demo_users() -> None:
    db = SessionLocal()
    try:
        if not db.query(User).filter(User.email == "dentist@elitedent.demo").first():
            db.add(
                User(
                    email="dentist@elitedent.demo",
                    name="Demo Dentist",
                    role="dentist",
                    password_hash=hash_password("demo1234"),
                )
            )
        if not db.query(User).filter(User.email == "lab@elitedent.demo").first():
            db.add(
                User(
                    email="lab@elitedent.demo",
                    name="Elite Dent Lab",
                    role="lab",
                    password_hash=hash_password("demo1234"),
                )
            )
        db.commit()
    finally:
        db.close()


def seed_demo_chat() -> None:
    """Ensure at least one patient/case and a short lab↔dentist conversation."""
    db = SessionLocal()
    try:
        dentist = db.query(User).filter(User.email == "dentist@elitedent.demo").first()
        lab = db.query(User).filter(User.email == "lab@elitedent.demo").first()
        if not dentist or not lab:
            return

        patient = (
            db.query(Patient)
            .filter(Patient.dentist_id == dentist.id)
            .order_by(Patient.id.asc())
            .first()
        )
        if not patient:
            patient = Patient(
                dentist_id=dentist.id,
                first_name="Marcus",
                last_name="Webb",
                notes="Demo patient for chat",
            )
            db.add(patient)
            db.flush()

        case = (
            db.query(Case)
            .filter(Case.patient_id == patient.id)
            .order_by(Case.id.asc())
            .first()
        )
        if not case:
            case = Case(patient_id=patient.id, status="in_review")
            db.add(case)
            db.flush()

        existing = db.query(Message).filter(Message.case_id == case.id).count()
        if existing == 0:
            db.add_all(
                [
                    Message(
                        case_id=case.id,
                        sender_id=dentist.id,
                        type="text",
                        body="Uploaded intraoral scan for #14. Prefer shade A2 if AI disagrees.",
                    ),
                    Message(
                        case_id=case.id,
                        sender_id=lab.id,
                        type="text",
                        body="Received, thank you. Reviewing margins now.",
                    ),
                    Message(
                        case_id=case.id,
                        sender_id=lab.id,
                        type="text",
                        body="Note: distal margin looks slightly underprepared — confirm before fabrication.",
                    ),
                ]
            )
        db.commit()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    seed_demo_users()
    seed_demo_chat()
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
app.include_router(clinical.router, prefix="/api/cases", tags=["clinical"])
app.include_router(exports.router, prefix="/api/exports", tags=["exports"])

try:
    from app.api import ai_poc

    app.include_router(ai_poc.router, prefix="/api/ai", tags=["ai-poc"])
except Exception as exc:  # pragma: no cover
    print(f"AI POC routes not loaded: {exc}")
