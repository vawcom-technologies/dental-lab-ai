from datetime import datetime

from sqlalchemy import String, DateTime, ForeignKey, Float, Boolean, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ShadeSelection(Base):
    __tablename__ = "shade_selections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("cases.id"), index=True)
    ai_suggested_shade: Mapped[str | None] = mapped_column(String(16), nullable=True)
    confidence_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    final_shade: Mapped[str] = mapped_column(String(16))  # VITA Classical e.g. A2
    overridden_by_dentist: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    case: Mapped["Case"] = relationship(back_populates="shade_selections")  # noqa: F821


class ShadeAnalysis(Base):
    """One saved per-tooth / per-zone shade analysis for a case."""

    __tablename__ = "shade_analyses"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("cases.id"), index=True)
    # ASSUMPTION: summary = middle-zone effective shade of selected_tooth_index
    selected_tooth_index: Mapped[int] = mapped_column(Integer, default=0)
    summary_shade: Mapped[str | None] = mapped_column(String(16), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    case: Mapped["Case"] = relationship(back_populates="shade_analyses")  # noqa: F821
    teeth: Mapped[list["ShadeToothResult"]] = relationship(
        back_populates="analysis",
        cascade="all, delete-orphan",
        order_by="ShadeToothResult.tooth_index",
    )


class ShadeToothResult(Base):
    __tablename__ = "shade_tooth_results"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    analysis_id: Mapped[int] = mapped_column(ForeignKey("shade_analyses.id"), index=True)
    tooth_index: Mapped[int] = mapped_column(Integer)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    rejected: Mapped[bool] = mapped_column(Boolean, default=False)
    reject_reason: Mapped[str | None] = mapped_column(String(64), nullable=True)

    analysis: Mapped["ShadeAnalysis"] = relationship(back_populates="teeth")
    zones: Mapped[list["ShadeZoneResult"]] = relationship(
        back_populates="tooth",
        cascade="all, delete-orphan",
    )


class ShadeZoneResult(Base):
    __tablename__ = "shade_zone_results"
    __table_args__ = (UniqueConstraint("tooth_result_id", "zone", name="uq_tooth_zone"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    tooth_result_id: Mapped[int] = mapped_column(ForeignKey("shade_tooth_results.id"), index=True)
    zone: Mapped[str] = mapped_column(String(16))  # cervical | middle | incisal
    detected_shade: Mapped[str | None] = mapped_column(String(16), nullable=True)
    delta_e_2000: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Dentist override — never written by detection; nullable
    override_shade: Mapped[str | None] = mapped_column(String(16), nullable=True)

    tooth: Mapped["ShadeToothResult"] = relationship(back_populates="zones")


class ShapeSelection(Base):
    __tablename__ = "shape_selections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("cases.id"), index=True)
    shape_id: Mapped[str] = mapped_column(String(64))  # library asset id
    position_x: Mapped[float] = mapped_column(Float, default=0.0)
    position_y: Mapped[float] = mapped_column(Float, default=0.0)
    rotation: Mapped[float] = mapped_column(Float, default=0.0)
    scale: Mapped[float] = mapped_column(Float, default=1.0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    case: Mapped["Case"] = relationship(back_populates="shape_selections")  # noqa: F821


class ScanBodyDetection(Base):
    __tablename__ = "scan_body_detections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"), index=True)
    detected_diameter: Mapped[float | None] = mapped_column(Float, nullable=True)
    matched_tooth_position: Mapped[str | None] = mapped_column(String(32), nullable=True)
    matched_manufacturer: Mapped[str | None] = mapped_column(String(128), nullable=True)
    confidence_score: Mapped[float | None] = mapped_column(Float, nullable=True)

    scan: Mapped["Scan"] = relationship(back_populates="scan_body_detections")  # noqa: F821


class ScanBodySelection(Base):
    """Case-level scan-body diameter match (manual or photo-detected)."""

    __tablename__ = "scan_body_selections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("cases.id"), index=True)
    detected_diameter: Mapped[float | None] = mapped_column(Float, nullable=True)
    table_diameter_mm: Mapped[float | None] = mapped_column(Float, nullable=True)
    matched_tooth_position: Mapped[str | None] = mapped_column(String(32), nullable=True)
    matched_manufacturer: Mapped[str | None] = mapped_column(String(128), nullable=True)
    matched_platform: Mapped[str | None] = mapped_column(String(64), nullable=True)
    confidence_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    overridden_by_dentist: Mapped[bool] = mapped_column(Boolean, default=False)
    detection_method: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    case: Mapped["Case"] = relationship(back_populates="scan_body_selections")  # noqa: F821
