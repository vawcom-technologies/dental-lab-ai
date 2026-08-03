"""All SQLAlchemy models — import this package so metadata registers tables."""

from app.models.user import User
from app.models.patient import Patient
from app.models.case import Case
from app.models.scan import Scan
from app.models.photo import Photo
from app.models.clinical import (
    ShadeSelection,
    ShadeAnalysis,
    ShadeToothResult,
    ShadeZoneResult,
    ShapeSelection,
    ScanBodyDetection,
    ScanBodySelection,
)
from app.models.comms import Message, Notification, XMLExport, ActivityLog

__all__ = [
    "User",
    "Patient",
    "Case",
    "Scan",
    "Photo",
    "ShadeSelection",
    "ShadeAnalysis",
    "ShadeToothResult",
    "ShadeZoneResult",
    "ShapeSelection",
    "ScanBodyDetection",
    "ScanBodySelection",
    "Message",
    "Notification",
    "XMLExport",
    "ActivityLog",
]
