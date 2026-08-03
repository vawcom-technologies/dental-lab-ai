"""Shade / shape / scan-body selection persistence (Week 3)."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import (
    User,
    Case,
    ShadeSelection,
    ShadeAnalysis,
    ShapeSelection,
    ScanBodySelection,
    ActivityLog,
)
from app.services import shade_analysis as shade_svc

router = APIRouter()


class ShadeSave(BaseModel):
    ai_suggested_shade: str | None = None
    confidence_score: float | None = None
    final_shade: str
    overridden_by_dentist: bool = False


class ShadeZoneIn(BaseModel):
    detected_shade: str | None = None
    delta_e_2000: float | None = None
    override_shade: str | None = None


class ShadeToothIn(BaseModel):
    tooth_index: int
    confidence: float | None = None
    rejected: bool = False
    reject_reason: str | None = None
    zones: dict[str, ShadeZoneIn] = Field(default_factory=dict)


class ShadeAnalysisSave(BaseModel):
    teeth: list[ShadeToothIn]
    selected_tooth_index: int = 0


class ZoneOverridePatch(BaseModel):
    override_shade: str | None = None


class ShapeSave(BaseModel):
    shape_id: str
    position_x: float = 0.0
    position_y: float = 0.0
    rotation: float = 0.0
    scale: float = 1.0


class ScanBodySave(BaseModel):
    detected_diameter: float | None = None
    table_diameter_mm: float | None = None
    matched_tooth_position: str | None = None
    matched_manufacturer: str | None = None
    matched_platform: str | None = None
    confidence_score: float | None = None
    overridden_by_dentist: bool = False
    detection_method: str | None = None


@router.post("/{case_id}/shade")
def save_shade(
    case_id: int,
    payload: ShadeSave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    from sqlalchemy.orm import joinedload

    from app.services.notify import notify_lab_users, patient_display_name

    case = (
        db.query(Case)
        .options(joinedload(Case.patient))
        .filter(Case.id == case_id)
        .first()
    )
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    row = ShadeSelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.save",
            target_type="shade_selection",
            target_id=row.id,
        )
    )
    name = patient_display_name(case.patient)
    final = payload.final_shade
    ai = payload.ai_suggested_shade
    if payload.overridden_by_dentist and ai and final and ai != final:
        msg = f"Shade override for {name}: AI {ai} → final {final}."
    else:
        msg = f"Shade confirmed for {name}: {final}."
    notify_lab_users(
        db,
        type="shade",
        message=msg,
        case_id=case_id,
        exclude_user_id=user.id,
    )
    db.commit()
    return {"id": row.id, "final_shade": row.final_shade}


@router.get("/{case_id}/shade")
def latest_shade(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShadeSelection)
        .filter(ShadeSelection.case_id == case_id)
        .order_by(ShadeSelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "ai_suggested_shade": row.ai_suggested_shade,
        "confidence_score": row.confidence_score,
        "final_shade": row.final_shade,
        "overridden_by_dentist": row.overridden_by_dentist,
        "created_at": row.created_at,
    }


@router.delete("/{case_id}/shade/{shade_id}", status_code=204)
def delete_shade(
    case_id: int,
    shade_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShadeSelection)
        .filter(ShadeSelection.id == shade_id, ShadeSelection.case_id == case_id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Shade selection not found")
    db.delete(row)
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.delete",
            target_type="shade_selection",
            target_id=shade_id,
        )
    )
    db.commit()
    return None


@router.post("/{case_id}/shade/analysis")
def save_shade_analysis(
    case_id: int,
    payload: ShadeAnalysisSave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    from sqlalchemy.orm import joinedload

    from app.services.notify import notify_lab_users, patient_display_name

    case = (
        db.query(Case)
        .options(joinedload(Case.patient))
        .filter(Case.id == case_id)
        .first()
    )
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    try:
        analysis = shade_svc.create_analysis(
            db,
            case_id=case_id,
            teeth_payload=[t.model_dump() for t in payload.teeth],
            selected_tooth_index=payload.selected_tooth_index,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.analysis.save",
            target_type="shade_analysis",
            target_id=analysis.id,
        )
    )
    name = patient_display_name(case.patient)
    summary = analysis.summary_shade or "—"
    if shade_svc.analysis_has_any_override(analysis):
        msg = f"Shade analysis saved for {name}: {summary} (with zone override)."
    else:
        msg = f"Shade analysis saved for {name}: {summary}."
    notify_lab_users(
        db,
        type="shade",
        message=msg,
        case_id=case_id,
        exclude_user_id=user.id,
    )
    db.commit()
    saved = shade_svc.get_analysis_for_case(db, case_id, analysis.id)
    return shade_svc.serialize_analysis(saved)  # type: ignore[arg-type]


@router.get("/{case_id}/shade/analysis")
def latest_shade_analysis(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = shade_svc.get_latest_analysis(db, case_id)
    if not row:
        return None
    return shade_svc.serialize_analysis(row)


@router.patch("/{case_id}/shade/analysis/{analysis_id}/zones/{zone_id}")
def patch_shade_zone_override(
    case_id: int,
    analysis_id: int,
    zone_id: int,
    payload: ZoneOverridePatch,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    zone = shade_svc.get_zone_for_analysis(db, case_id, analysis_id, zone_id)
    if not zone:
        raise HTTPException(status_code=404, detail="Zone result not found")
    detected_before = zone.detected_shade
    delta_before = zone.delta_e_2000
    try:
        shade_svc.set_zone_override(db, zone, payload.override_shade)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if zone.detected_shade != detected_before or zone.delta_e_2000 != delta_before:
        raise HTTPException(
            status_code=500,
            detail="Invariant violated: detected shade must not change on override",
        )

    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.zone.override",
            target_type="shade_zone_result",
            target_id=zone.id,
        )
    )
    db.commit()
    analysis = shade_svc.get_analysis_for_case(db, case_id, analysis_id)
    return shade_svc.serialize_analysis(analysis)  # type: ignore[arg-type]


@router.delete("/{case_id}/shade/analysis/{analysis_id}", status_code=204)
def delete_shade_analysis(
    case_id: int,
    analysis_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShadeAnalysis)
        .filter(ShadeAnalysis.id == analysis_id, ShadeAnalysis.case_id == case_id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Shade analysis not found")
    db.delete(row)
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.analysis.delete",
            target_type="shade_analysis",
            target_id=analysis_id,
        )
    )
    db.commit()
    return None


@router.post("/{case_id}/shape")
def save_shape(
    case_id: int,
    payload: ShapeSave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    row = ShapeSelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shape.save",
            target_type="shape_selection",
            target_id=row.id,
        )
    )
    db.commit()
    return {"id": row.id, "shape_id": row.shape_id}


@router.get("/{case_id}/shape")
def latest_shape(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShapeSelection)
        .filter(ShapeSelection.case_id == case_id)
        .order_by(ShapeSelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "shape_id": row.shape_id,
        "position_x": row.position_x,
        "position_y": row.position_y,
        "rotation": row.rotation,
        "scale": row.scale,
        "created_at": row.created_at,
    }


@router.post("/{case_id}/scan-body")
def save_scan_body(
    case_id: int,
    payload: ScanBodySave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    row = ScanBodySelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="scan_body.save",
            target_type="scan_body_selection",
            target_id=row.id,
        )
    )
    db.commit()
    return {
        "id": row.id,
        "detected_diameter": row.detected_diameter,
        "matched_manufacturer": row.matched_manufacturer,
        "matched_tooth_position": row.matched_tooth_position,
    }


@router.get("/{case_id}/scan-body")
def latest_scan_body(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ScanBodySelection)
        .filter(ScanBodySelection.case_id == case_id)
        .order_by(ScanBodySelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "detected_diameter": row.detected_diameter,
        "table_diameter_mm": row.table_diameter_mm,
        "matched_tooth_position": row.matched_tooth_position,
        "matched_manufacturer": row.matched_manufacturer,
        "matched_platform": row.matched_platform,
        "confidence_score": row.confidence_score,
        "overridden_by_dentist": row.overridden_by_dentist,
        "detection_method": row.detection_method,
        "created_at": row.created_at,
    }
