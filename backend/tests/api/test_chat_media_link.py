"""Chat media: signed link only for conversation participants; EU endpoint."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import media
from app.core.config import settings
from app.core.security import AuthUser, get_current_user
from app.services import r2

MSG = {"id": "m1", "conversation_id": "c1", "media_type": "video", "media_url": "https://pub.r2.dev/chat/c1/video/a.mp4"}
CONV = {"id": "c1", "user_a": "u1", "user_b": "u2"}


@pytest.fixture
def client(monkeypatch):
    app = FastAPI()
    app.include_router(media.router, prefix="/api/media")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    monkeypatch.setattr(media.cm, "fetch_message", lambda i: MSG if i == "m1" else None)
    monkeypatch.setattr(media.cm, "fetch_conversation", lambda i: CONV)
    monkeypatch.setattr(settings, "r2_videos_bucket", "vids")
    monkeypatch.setattr(settings, "r2_account_id", "acc")
    monkeypatch.setattr(settings, "r2_access_key_id", "k")
    monkeypatch.setattr(settings, "r2_secret_access_key", "s")
    monkeypatch.setattr(settings, "r2_jurisdiction", "eu")
    r2.get_r2_client.cache_clear()
    yield TestClient(app)
    r2.get_r2_client.cache_clear()


def test_participant_gets_eu_signed_link(client):
    r = client.get("/api/media/chat-files/m1")
    assert r.status_code == 200
    url = r.json()["url"]
    assert url.startswith("https://acc.eu.r2.cloudflarestorage.com/vids/chat/c1/video/a.mp4?")
    assert "X-Amz-Signature" in url


def test_non_participant_and_missing_get_404(client, monkeypatch):
    assert client.get("/api/media/chat-files/nope").status_code == 404
    monkeypatch.setitem(CONV, "user_a", "x")
    monkeypatch.setitem(CONV, "user_b", "y")
    assert client.get("/api/media/chat-files/m1").status_code == 404


def test_key_from_legacy_url_or_bare_key():
    assert r2.chat_key_from_url("https://pub.r2.dev/chat/c/a.jpg") == "chat/c/a.jpg"
    assert r2.chat_key_from_url("chat/c/a.jpg") == "chat/c/a.jpg"
