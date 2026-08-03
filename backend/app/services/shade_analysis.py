"""Persist / serialize per-tooth shade analyses.

Detection writes detected_shade + delta_e_2000 only.
Overrides write override_shade only. effective_shade is computed.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session, joinedload

from app.ai.shade import VITA_SHADES
from app.ai.shade_zones import ZONES
from app.models.clinical import ShadeAnalysis, ShadeToothResult, ShadeZoneResult

SUMMARY_ZONE = "middle"  # ASSUMPTION: case summary uses body (middle) shade


def effective_shade(detected: str | None, override: str | None) -> str | None:
    if override is not None:
        return override
    return detected


def zone_has_override(zone: ShadeZoneResult) -> bool:
    return zone.override_shade is not None


def compute_summary_shade(
    analysis: ShadeAnalysis,
    *,
    selected_tooth_index: int | None = None,
) -> str | None:
    idx = (
        analysis.selected_tooth_index
        if selected_tooth_index is None
        else selected_tooth_index
    )
    for tooth in analysis.teeth:
        if tooth.tooth_index != idx or tooth.rejected:
            continue
        for zone in tooth.zones:
            if zone.zone == SUMMARY_ZONE:
                return effective_shade(zone.detected_shade, zone.override_shade)
    return None


def analysis_has_any_override(analysis: ShadeAnalysis) -> bool:
    return any(zone_has_override(z) for t in analysis.teeth for z in t.zones)


def serialize_zone(zone: ShadeZoneResult) -> dict[str, Any]:
    return {
        "id": zone.id,
        "zone": zone.zone,
        "detected_shade": zone.detected_shade,
        "delta_e_2000": zone.delta_e_2000,
        "override_shade": zone.override_shade,
        "effective_shade": effective_shade(zone.detected_shade, zone.override_shade),
        "is_overridden": zone_has_override(zone),
    }


def serialize_tooth(tooth: ShadeToothResult) -> dict[str, Any]:
    zones_by_name = {z.zone: serialize_zone(z) for z in tooth.zones}
    return {
        "id": tooth.id,
        "tooth_index": tooth.tooth_index,
        "confidence": tooth.confidence,
        "rejected": tooth.rejected,
        "reject_reason": tooth.reject_reason,
        "zones": {name: zones_by_name.get(name) for name in ZONES},
    }


def serialize_analysis(analysis: ShadeAnalysis) -> dict[str, Any]:
    teeth = [serialize_tooth(t) for t in sorted(analysis.teeth, key=lambda t: t.tooth_index)]
    return {
        "id": analysis.id,
        "case_id": analysis.case_id,
        "selected_tooth_index": analysis.selected_tooth_index,
        "summary_shade": analysis.summary_shade,
        "has_override": analysis_has_any_override(analysis),
        "accepted_count": sum(1 for t in analysis.teeth if not t.rejected),
        "tooth_count": len(analysis.teeth),
        "teeth": teeth,
        "created_at": analysis.created_at,
    }


def create_analysis(
    db: Session,
    *,
    case_id: int,
    teeth_payload: list[dict[str, Any]],
    selected_tooth_index: int = 0,
) -> ShadeAnalysis:
    """Insert a new analysis graph. Does not commit."""
    analysis = ShadeAnalysis(
        case_id=case_id,
        selected_tooth_index=selected_tooth_index,
    )
    db.add(analysis)
    db.flush()

    for tooth_in in teeth_payload:
        tooth = ShadeToothResult(
            analysis_id=analysis.id,
            tooth_index=int(tooth_in["tooth_index"]),
            confidence=tooth_in.get("confidence"),
            rejected=bool(tooth_in.get("rejected", False)),
            reject_reason=tooth_in.get("reject_reason"),
        )
        db.add(tooth)
        db.flush()
        zones_in = tooth_in.get("zones") or {}
        # Accept either dict keyed by zone name or list of zone dicts
        if isinstance(zones_in, list):
            by_name = {z["zone"]: z for z in zones_in if isinstance(z, dict) and "zone" in z}
        elif isinstance(zones_in, dict):
            by_name = zones_in
        else:
            by_name = {}

        # Always persist all three zones so session records stay complete.
        for zone_name in ZONES:
            zone_data = by_name.get(zone_name) or {}
            if not isinstance(zone_data, dict):
                zone_data = {}
            detected = zone_data.get("detected_shade")
            override = zone_data.get("override_shade")
            _validate_optional_vita(detected)
            _validate_optional_vita(override)
            db.add(
                ShadeZoneResult(
                    tooth_result_id=tooth.id,
                    zone=zone_name,
                    detected_shade=detected,
                    delta_e_2000=zone_data.get("delta_e_2000"),
                    override_shade=override,
                )
            )

    db.flush()
    db.refresh(analysis)
    # Load relationships for summary
    analysis = (
        db.query(ShadeAnalysis)
        .options(
            joinedload(ShadeAnalysis.teeth).joinedload(ShadeToothResult.zones)
        )
        .filter(ShadeAnalysis.id == analysis.id)
        .one()
    )
    analysis.summary_shade = compute_summary_shade(analysis)
    db.flush()
    return analysis


def set_zone_override(
    db: Session,
    zone: ShadeZoneResult,
    override_shade: str | None,
) -> ShadeZoneResult:
    """Write override_shade only — never touches detected_shade / delta_e_2000."""
    _validate_optional_vita(override_shade)
    zone.override_shade = override_shade
    db.flush()

    analysis = zone.tooth.analysis
    analysis.summary_shade = compute_summary_shade(analysis)
    db.flush()
    return zone


def get_latest_analysis(db: Session, case_id: int) -> ShadeAnalysis | None:
    return (
        db.query(ShadeAnalysis)
        .options(
            joinedload(ShadeAnalysis.teeth).joinedload(ShadeToothResult.zones)
        )
        .filter(ShadeAnalysis.case_id == case_id)
        .order_by(ShadeAnalysis.id.desc())
        .first()
    )


def get_analysis_for_case(
    db: Session, case_id: int, analysis_id: int
) -> ShadeAnalysis | None:
    return (
        db.query(ShadeAnalysis)
        .options(
            joinedload(ShadeAnalysis.teeth).joinedload(ShadeToothResult.zones)
        )
        .filter(ShadeAnalysis.id == analysis_id, ShadeAnalysis.case_id == case_id)
        .first()
    )


def get_zone_for_analysis(
    db: Session, case_id: int, analysis_id: int, zone_id: int
) -> ShadeZoneResult | None:
    return (
        db.query(ShadeZoneResult)
        .join(ShadeToothResult)
        .join(ShadeAnalysis)
        .options(
            joinedload(ShadeZoneResult.tooth)
            .joinedload(ShadeToothResult.analysis)
            .joinedload(ShadeAnalysis.teeth)
            .joinedload(ShadeToothResult.zones)
        )
        .filter(
            ShadeZoneResult.id == zone_id,
            ShadeAnalysis.id == analysis_id,
            ShadeAnalysis.case_id == case_id,
        )
        .first()
    )


def _validate_optional_vita(shade: str | None) -> None:
    if shade is None:
        return
    if shade not in VITA_SHADES:
        raise ValueError(f"Unknown VITA Classical shade: {shade}")
