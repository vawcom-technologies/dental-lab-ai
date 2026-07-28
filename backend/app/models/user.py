from datetime import datetime

from sqlalchemy import String, DateTime, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32), default="dentist")  # dentist | lab | admin
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    last_login: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    patients: Mapped[list["Patient"]] = relationship(back_populates="dentist")  # noqa: F821
    messages: Mapped[list["Message"]] = relationship(back_populates="sender")  # noqa: F821
    notifications: Mapped[list["Notification"]] = relationship(back_populates="user")  # noqa: F821
