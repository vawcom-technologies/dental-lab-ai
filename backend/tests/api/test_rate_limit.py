from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.core import rate_limit


def _req(ip="1.2.3.4", fwd=""):
    return SimpleNamespace(headers={"x-forwarded-for": fwd} if fwd else {}, client=SimpleNamespace(host=ip))


def test_per_email_limit_blocks_guessing_from_many_ips():
    rate_limit.reset()
    for i in range(5):
        rate_limit.guard(_req(ip=f"10.0.0.{i}"), "signin", "a@b.de", per_ip=20, per_email=5, window=60)
    with pytest.raises(HTTPException) as e:
        rate_limit.guard(_req(ip="10.0.0.99"), "signin", "a@b.de", per_ip=20, per_email=5, window=60)
    assert e.value.status_code == 429 and "Retry-After" in e.value.headers


def test_per_ip_limit_uses_forwarded_for_and_resets_per_action():
    rate_limit.reset()
    for i in range(3):
        rate_limit.guard(_req(fwd="9.9.9.9, 10.0.0.1"), "forgot", f"u{i}@x.de", per_ip=3, per_email=3, window=60)
    with pytest.raises(HTTPException):
        rate_limit.guard(_req(fwd="9.9.9.9"), "forgot", "new@x.de", per_ip=3, per_email=3, window=60)
    # A different action has its own budget.
    rate_limit.guard(_req(fwd="9.9.9.9"), "signin", "new@x.de", per_ip=3, per_email=3, window=60)


def test_signup_photo_required_for_dentists_only():
    from pydantic import ValidationError

    from app.schemas import SignUpRequest

    base = {"email": "a@b.de", "name": "Ada", "password": "Abcdef1!x", "phone": "01701234567"}
    SignUpRequest(**base, role="laboratory")  # lab without a photo: fine
    with pytest.raises(ValidationError):
        SignUpRequest(**base, role="dentist")
    SignUpRequest(**base, role="dentist", avatar="aGk=", avatar_content_type="image/jpeg")
