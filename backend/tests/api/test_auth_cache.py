import base64
import json
import time
from types import SimpleNamespace
from unittest.mock import patch

from app.core import security


def _jwt(exp: float) -> str:
    body = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return f"h.{body}.s"


def test_token_validated_once_then_cached_until_logout():
    security.clear_auth_cache()
    user = SimpleNamespace(id="u1", email="a@b.c", user_metadata={"role": "dentist"})
    client = SimpleNamespace(auth=SimpleNamespace(get_user=lambda t: SimpleNamespace(user=user)))
    token = _jwt(time.time() + 3600)
    with patch.object(security, "get_supabase", return_value=client) as sb, \
         patch.object(security, "fetch_profile", return_value=None):
        assert security.get_user_from_token(token).id == "u1"
        assert security.get_user_from_token(token).id == "u1"
        assert sb.call_count == 1
        security.clear_auth_cache()
        security.get_user_from_token(token)
        assert sb.call_count == 2
        # Expired token is never served from cache.
        old = _jwt(time.time() - 1)
        security.get_user_from_token(old)
        security.get_user_from_token(old)
        assert sb.call_count == 4
