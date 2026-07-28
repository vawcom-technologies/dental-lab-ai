from datetime import datetime

from sqlalchemy import String, DateTime, ForeignKey, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Scan(Base):
    __tablename__ = "scans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("cases.id"), index=True)
    file_path: Mapped[str] = mapped_column(String(512))  # encrypted at rest in prod
    format: Mapped[str] = mapped_column(String(16), default="PLY")
    scan_quality_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    # good | bad | blurry | missing_margin | unknown
    validation_result: Mapped[str | None] = mapped_column(String(32), nullable=True)
    rescanned_from_id: Mapped[int | None] = mapped_column(ForeignKey("scans.id"), nullable=True)
    uploaded_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    case: Mapped["Case"] = relationship(back_populates="scans")  # noqa: F821
    scan_body_detections: Mapped[list["ScanBodyDetection"]] = relationship(  # noqa: F821
        back_populates="scan"
    )
