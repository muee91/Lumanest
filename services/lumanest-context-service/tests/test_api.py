import os

from fastapi.testclient import TestClient

from app.main import app
from app.models import ContextImportResult
from app.store import ContextStore


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
        assert body["dataFreshness"] == {
            "context": "fresh",
            "weather": "fresh",
            "weatherObservedAt": "2026-07-14T10:00:00+08:00",
        }
        assert body["weather"]["windSpeedMps"] == 2
        assert body["sunMoon"]["moonPhase"] in {
            "newMoon", "waxingCrescent", "firstQuarter", "waxingGibbous",
            "fullMoon", "waningGibbous", "lastQuarter", "waningCrescent",
        }
        assert body["route"] == {"mode": "none", "stage": "none", "active": False}
        assert body["allowedActions"] == ["openExplore"]
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


def spatial_import_payload():
    return {
        "datasetType": "spatialFeatures",
        "source": {
            "id": "reviewed-lakes",
            "enabled": True,
            "licenseStatus": "approved",
            "attribution": "Reviewed fixture",
            "version": "2026-07-14",
        },
        "featureCollection": {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "id": "lake-1",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[120.0, 30.0], [120.2, 30.0], [120.2, 30.2], [120.0, 30.0]]],
                    },
                    "properties": {"kind": "water", "name": "Reviewed lake"},
                }
            ],
        },
    }


def test_internal_import_requires_token_and_returns_only_safe_metadata(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    captured = []

    async def fake_import(_store, body):
        captured.append(body)
        return ContextImportResult.model_validate({
            "sourceId": body.source.id,
            "datasetType": body.dataset_type,
            "importedCount": len(body.feature_collection.features),
            "enabled": body.source.enabled,
            "cacheInvalidated": True,
        })

    monkeypatch.setattr(ContextStore, "import_dataset", fake_import)
    with TestClient(app) as client:
        assert client.post("/internal/v1/imports", json=spatial_import_payload()).status_code == 401
        response = client.post(
            "/internal/v1/imports",
            json=spatial_import_payload(),
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
    assert response.status_code == 201
    assert response.json() == {
        "sourceId": "reviewed-lakes",
        "datasetType": "spatialFeatures",
        "importedCount": 1,
        "enabled": True,
        "cacheInvalidated": True,
    }
    assert len(captured) == 1


def test_import_rejects_unlicensed_enabled_source_and_sensitive_point(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    headers = {"X-Internal-Service-Token": "internal-test-token"}
    unlicensed = spatial_import_payload()
    unlicensed["source"]["licenseStatus"] = "pending"
    sensitive = spatial_import_payload()
    sensitive["source"]["enabled"] = False
    feature = sensitive["featureCollection"]["features"][0]
    feature["geometry"] = {"type": "Point", "coordinates": [120.1, 30.1]}
    feature["properties"]["sensitivity"] = "sensitive"
    too_precise = spatial_import_payload()
    too_precise["source"]["enabled"] = False
    precise_feature = too_precise["featureCollection"]["features"][0]
    precise_feature["properties"]["sensitivity"] = "sensitive"
    precise_feature["geometry"]["coordinates"] = [[
        [120.0, 30.0], [120.001, 30.0], [120.001, 30.001], [120.0, 30.0]
    ]]

    with TestClient(app) as client:
        assert client.post("/internal/v1/imports", json=unlicensed, headers=headers).status_code == 422
        assert client.post("/internal/v1/imports", json=sensitive, headers=headers).status_code == 422
        assert client.post("/internal/v1/imports", json=too_precise, headers=headers).status_code == 422
