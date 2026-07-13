import os

from fastapi.testclient import TestClient

from app.main import app


def payload():
    return {
        "contractVersion": 2,
        "coordinate": {"latitude": 30.25, "longitude": 120.15, "system": "wgs84"},
        "observedAt": "2026-07-14T10:00:00+08:00",
        "locale": "zh-CN",
        "intent": "photography",
        "route": {"mode": "none", "stage": "none"},
        "evidence": {"waterBody": True},
        "weather": {
            "observedAt": "2026-07-14T10:00:00+08:00",
            "condition": "clear",
            "windSpeedMps": 2,
            "precipitationMm": 0,
            "visibilityKm": 20,
            "thunder": False,
            "stale": False,
        },
        "solar": {"dayPhase": "sunset"},
    }


def test_health_is_public_and_does_not_expose_configuration():
    with TestClient(app) as client:
        assert client.get("/healthz").json() == {"status": "ok"}


def test_internal_evaluate_requires_the_separate_service_token(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    with TestClient(app) as client:
        assert client.post("/internal/v1/evaluate", json=payload()).status_code == 401
        response = client.post(
            "/internal/v1/evaluate",
            json=payload(),
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["contractVersion"] == 2
        assert body["scene"] == "lake"
        assert body["manifest"]["primaryEventId"] == "reflection"
        assert "latitude" not in body and "longitude" not in body


def test_unknown_fields_are_rejected(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    invalid = payload() | {"deviceId": "must-not-be-accepted"}
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/evaluate",
            json=invalid,
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
        assert response.status_code == 422
