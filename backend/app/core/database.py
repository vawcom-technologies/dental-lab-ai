"""Local SQLAlchemy database removed — auth and data now go through Supabase.

This module is kept as a stub so older imports fail with a clear message
until remaining domain APIs are migrated.
"""


def get_db():
    raise RuntimeError(
        "Local database removed. Use Supabase Auth / Supabase client instead."
    )
