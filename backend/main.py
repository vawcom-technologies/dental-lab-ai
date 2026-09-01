"""Deploy entrypoint. Railpack looks for main.py at the service root."""

from app.main import app

__all__ = ["app"]
