"""Persistence tests: save analysis, override immutability, summary shade."""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models import Case, Patient, User  # noqa: F401 — register tables
from app.models.clinical import ShadeZoneResult
from app.services import shade_analysis as shade_svc


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    user = User(
        email="t@test.com",
        name="Test",
        role="dentist",
        password_hash="x",
    )
    session.add(user)
    session.flush()
    patient = Patient(
        dentist_id=user.id,
        first_name="Ada",
        last_name="Lovelace",
    )
    session.add(patient)
    session.flush()
    case = Case(patient_id=patient.id, status="pending")
    session.add(case)
    session.commit()
    yield session, case.id
    session.close()


def _tooth_payload(*, tooth_index: int = 0, middle: str = "A2", cervical: str = "A3") -> dict:
    return {
        "tooth_index": tooth_index,
        "confidence": 0.9,
        "rejected": False,
        "reject_reason": None,
        "zones": {
            "cervical": {
                "detected_shade": cervical,
                "delta_e_2000": 1.5,
                "override_shade": None,
            },
            "middle": {
                "detected_shade": middle,
                "delta_e_2000": 1.1,
                "override_shade": None,
            },
            "incisal": {
                "detected_shade": "A1",
                "delta_e_2000": 2.0,
                "override_shade": None,
            },
        },
    }


class TestShadeAnalysisPersist:
    def test_create_sets_summary_from_middle_zone(self, db):
        session, case_id = db
        analysis = shade_svc.create_analysis(
            session,
            case_id=case_id,
            teeth_payload=[_tooth_payload(middle="A3.5")],
            selected_tooth_index=0,
        )
        session.commit()
        assert analysis.summary_shade == "A3.5"
        out = shade_svc.serialize_analysis(analysis)
        assert out["summary_shade"] == "A3.5"
        assert out["teeth"][0]["zones"]["middle"]["override_shade"] is None
        assert out["teeth"][0]["zones"]["middle"]["effective_shade"] == "A3.5"

    def test_override_does_not_clobber_detected(self, db):
        session, case_id = db
        analysis = shade_svc.create_analysis(
            session,
            case_id=case_id,
            teeth_payload=[_tooth_payload(middle="A2")],
        )
        session.commit()
        middle = next(
            z
            for t in analysis.teeth
            for z in t.zones
            if z.zone == "middle"
        )
        detected_before = middle.detected_shade
        delta_before = middle.delta_e_2000

        shade_svc.set_zone_override(session, middle, "C1")
        session.commit()

        refreshed = session.get(ShadeZoneResult, middle.id)
        assert refreshed is not None
        assert refreshed.detected_shade == detected_before == "A2"
        assert refreshed.delta_e_2000 == delta_before
        assert refreshed.override_shade == "C1"
        assert shade_svc.effective_shade(refreshed.detected_shade, refreshed.override_shade) == "C1"

        analysis = shade_svc.get_analysis_for_case(session, case_id, analysis.id)
        assert analysis is not None
        assert analysis.summary_shade == "C1"
        assert shade_svc.analysis_has_any_override(analysis) is True

    def test_clear_override_restores_detected_effective(self, db):
        session, case_id = db
        analysis = shade_svc.create_analysis(
            session,
            case_id=case_id,
            teeth_payload=[_tooth_payload(middle="B2")],
        )
        session.commit()
        middle = next(z for t in analysis.teeth for z in t.zones if z.zone == "middle")
        shade_svc.set_zone_override(session, middle, "A4")
        shade_svc.set_zone_override(session, middle, None)
        session.commit()
        refreshed = session.get(ShadeZoneResult, middle.id)
        assert refreshed is not None
        assert refreshed.detected_shade == "B2"
        assert refreshed.override_shade is None
        analysis = shade_svc.get_analysis_for_case(session, case_id, analysis.id)
        assert analysis is not None
        assert analysis.summary_shade == "B2"

    def test_rerun_style_new_analysis_does_not_mutate_prior_overrides(self, db):
        session, case_id = db
        first = shade_svc.create_analysis(
            session,
            case_id=case_id,
            teeth_payload=[_tooth_payload(middle="A2")],
        )
        session.commit()
        middle = next(z for t in first.teeth for z in t.zones if z.zone == "middle")
        shade_svc.set_zone_override(session, middle, "A3.5")
        session.commit()

        second = shade_svc.create_analysis(
            session,
            case_id=case_id,
            teeth_payload=[_tooth_payload(middle="B1")],
        )
        session.commit()

        # Prior analysis override untouched
        prior = shade_svc.get_analysis_for_case(session, case_id, first.id)
        assert prior is not None
        prior_middle = next(z for t in prior.teeth for z in t.zones if z.zone == "middle")
        assert prior_middle.detected_shade == "A2"
        assert prior_middle.override_shade == "A3.5"

        # New analysis starts clean
        new_middle = next(z for t in second.teeth for z in t.zones if z.zone == "middle")
        assert new_middle.detected_shade == "B1"
        assert new_middle.override_shade is None
        assert second.summary_shade == "B1"

    def test_rejects_unknown_vita_shade(self, db):
        session, case_id = db
        bad = _tooth_payload()
        bad["zones"]["middle"]["detected_shade"] = "Z9"
        with pytest.raises(ValueError, match="Unknown shade"):
            shade_svc.create_analysis(session, case_id=case_id, teeth_payload=[bad])
