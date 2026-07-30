from datetime import datetime

from sqlalchemy import String, DateTime, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Case(Base):
    """Clinical case for a patient (scan / shade / shape / chat hang here)."""

    __tablename__ = "cases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    # pending | in_progress | in_review | rejected | completed
    status: Mapped[str] = mapped_column(String(32), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    patient: Mapped["Patient"] = relationship(back_populates="cases")  # noqa: F821
    scans: Mapped[list["Scan"]] = relationship(back_populates="case")  # noqa: F821
    photos: Mapped[list["Photo"]] = relationship(back_populates="case")  # noqa: F821
    shade_selections: Mapped[list["ShadeSelection"]] = relationship(back_populates="case")  # noqa: F821
    shape_selections: Mapped[list["ShapeSelection"]] = relationship(back_populates="case")  # noqa: F821
    scan_body_selections: Mapped[list["ScanBodySelection"]] = relationship(back_populates="case")  # noqa: F821
    messages: Mapped[list["Message"]] = relationship(back_populates="case")  # noqa: F821
    xml_exports: Mapped[list["XMLExport"]] = relationship(back_populates="case")  # noqa: F821
    notifications: Mapped[list["Notification"]] = relationship(back_populates="case")  # noqa: F821
