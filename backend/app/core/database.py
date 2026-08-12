"""Local SQLAlchemy engine removed — auth and data now go through Supabase.

`Base` remains so legacy model modules can still import (and in-memory tests can
bind their own engines). `get_db` stays a hard fail until those APIs migrate.
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def get_db():
    raise RuntimeError(
        "Local database removed. Use Supabase Auth / Supabase client instead."
    )
