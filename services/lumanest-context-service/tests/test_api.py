from copy import deepcopy
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.main import app
from app.models import (ContextImportResult, PhotographyTarget, RouteState,
                        SceneEvidence, ShootingTarget, SpatialFeaturesImport,
                        WildlifeLayerArea)
from app.store import ContextStore


def payload():
    return {
        "contractVersion": 4,
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
        "forecast": {
            "observedAt": "2026-07-14T10:00:00+08:00",
            "nextHourPrecipitationMm": 0,
            "nextThreeHoursMaxWindSpeedMps": 3,
            "thunderNextThreeHours": False,
        },
        "officialWarnings": [],
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
        assert body["contractVersion"] == 4
        assert body["scene"] == "lake"
        assert body["manifest"]["primaryEventId"] == "session.water.evening"
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
        assert body["allowedActions"] == ["openShootingWindow"]
        assert "latitude" not in body and "longitude" not in body


def test_internal_evaluate_merges_generic_scene_with_reviewed_safety(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")

    async def spatial_evidence(_store, _latitude, _longitude):
        return SceneEvidence(wildlifeSafety=True)

    monkeypatch.setattr(ContextStore, "spatial_evidence", spatial_evidence)
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/evaluate",
            json=payload(),
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["scene"] == "lake"
    risk = next(event for event in body["events"] if event["id"] == "wildlife-safety")
    assert risk["channel"] == "wildlifeSafety"
    assert risk["source"] == "official"


def test_internal_target_resolve_verifies_public_id_and_coordinate(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    target = ShootingTarget.model_validate({
        "id": "target_0123456789abcdef01234567",
        "name": "东岸审核湖岸",
        "coordinate": {"latitude": 30.251, "longitude": 120.151, "system": "wgs84"},
        "supportedSessions": ["waterEvening"],
        "viewBearingDegrees": 286,
        "bearingToleranceDegrees": 25,
        "accessModes": ["driving", "walking"],
        "leadTimeMinutes": 12,
        "arrivalRadiusMeters": 100,
        "shorelineSide": "east",
        "reviewedAt": "2026-07-01T00:00:00Z",
        "reviewReference": "https://review.example/targets/east-bank",
        "sourceAttribution": "审核目录",
        "sourceLicense": "CC-BY-4.0",
        "sourceUrl": "https://source.example/lakes/east-bank",
    })

    async def resolve(_store, target_id, latitude, longitude):
        assert target_id == target.id
        assert (latitude, longitude) == (30.251, 120.151)
        return target

    monkeypatch.setattr(ContextStore, "resolve_shooting_target", resolve)
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/shooting-targets/resolve",
            json={
                "targetId": target.id,
                "coordinate": {
                    "latitude": 30.251,
                    "longitude": 120.151,
                    "system": "wgs84",
                },
            },
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )

    assert response.status_code == 200
    assert response.json()["id"] == target.id


def test_anonymous_feedback_contract_rejects_location_identity_and_media(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    recorded = []

    async def record(_store, body):
        recorded.append(body)

    monkeypatch.setattr(ContextStore, "record_shooting_feedback", record)
    valid = {
        "contractVersion": 2,
        "ruleVersion": "water-evening.1",
        "conditionBand": "good",
        "factors": [{"id": "wind", "effect": "limiting"}],
        "outcome": "conditionsDidNotAppear",
        "reasons": ["wind"],
        "targetId": None,
    }
    with TestClient(app) as client:
        accepted = client.post(
            "/internal/v1/shooting-feedback",
            json=valid,
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
        for forbidden in ("coordinate", "deviceId", "photo", "exif"):
            rejected = client.post(
                "/internal/v1/shooting-feedback",
                json=valid | {forbidden: "forbidden"},
                headers={"X-Internal-Service-Token": "internal-test-token"},
            )
            assert rejected.status_code == 422

    assert accepted.status_code == 200
    assert accepted.json() == {"accepted": True}
    assert len(recorded) == 1


@pytest.mark.asyncio
async def test_feedback_calibration_returns_only_thresholded_factor_aggregates():
    captured = {}

    class Result:
        def mappings(self):
            return self

        def all(self):
            return [
                {
                    "rule_version": "water-evening.1",
                    "condition_band": "good",
                    "factor_id": "wind",
                    "factor_effect": "supporting",
                    "evaluated_count": 10,
                    "captured_count": 7,
                    "conditions_did_not_appear_count": 3,
                }
            ]

    class Connection:
        async def execute(self, statement, parameters):
            captured["statement"] = str(statement)
            captured["parameters"] = parameters
            return Result()

    class ConnectionContext:
        async def __aenter__(self):
            return Connection()

        async def __aexit__(self, *_args):
            return None

    class Engine:
        def connect(self):
            return ConnectionContext()

    since = datetime.now(timezone.utc) - timedelta(days=90)
    store = ContextStore(None, None)
    store.engine = Engine()
    report = await store.shooting_feedback_calibration(since, 5)

    assert report.rows[0].captured_rate == pytest.approx(0.7)
    assert report.rows[0].evaluated_count == 10
    assert captured["parameters"] == {"since": since, "minimum_samples": 5}
    assert "target_id" not in captured["statement"]
    assert "HAVING COUNT(*) >=" in captured["statement"]


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


@pytest.mark.asyncio
async def test_cached_snapshot_reads_redis_value_after_astronomy_store_extension():
    class FakeRedis:
        async def get(self, key):
            assert key == "context:v5:fingerprint"
            return '{"contextId":"cached"}'

    store = ContextStore(None, None)
    store.redis = FakeRedis()

    assert await store.cached_snapshot("fingerprint") == {"contextId": "cached"}


@pytest.mark.asyncio
async def test_spatial_evidence_reads_all_query_columns_for_scene_and_wildlife():
    class Result:
        def all(self):
            return [
                ("water", "scene", "spatial"),
                ("protected", "wildlifeOpportunity", "wildlifeHistorical"),
                ("risk", "wildlifeSafety", "officialRisk"),
            ]

    class Connection:
        async def execute(self, _statement, parameters):
            assert parameters == {"latitude": 30.25, "longitude": 120.15}
            return Result()

    class ConnectionContext:
        async def __aenter__(self):
            return Connection()

        async def __aexit__(self, *_args):
            return None

    class Engine:
        def connect(self):
            return ConnectionContext()

    store = ContextStore(None, None)
    store.engine = Engine()
    evidence = await store.spatial_evidence(30.25, 120.15)

    assert evidence.water_body is True
    assert evidence.wildlife_opportunity is True
    assert evidence.wildlife_safety is True


@pytest.mark.asyncio
async def test_photography_target_store_requires_approved_public_static_point():
    captured = {}

    class Result:
        def mappings(self):
            return self

        def first(self):
            return {
                "id": "f" * 64, "name": "东岸观景台", "target_type": "lakeshore",
                "latitude": 30.251, "longitude": 120.151,
            }

    class Connection:
        async def execute(self, statement, parameters):
            captured["statement"] = str(statement)
            captured["parameters"] = parameters
            return Result()

    class ConnectionContext:
        async def __aenter__(self):
            return Connection()

        async def __aexit__(self, *_args):
            return None

    class Engine:
        def connect(self):
            return ConnectionContext()

    store = ContextStore(None, None)
    store.engine = Engine()
    target = await store.photography_target(30.25, 120.15)

    assert target is not None
    assert target.kind == "lakeshore"
    assert target.coordinate.system == "wgs84"
    assert captured["parameters"] == {"latitude": 30.25, "longitude": 120.15}
    assert "license_status = 'approved'" in captured["statement"]
    assert "sensitivity = 'public'" in captured["statement"]
    assert "target_type IN" in captured["statement"]


def test_internal_evaluate_includes_only_bounded_astronomy_authority(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")

    async def astronomy_events(_store, _moment):
        return [{
            "external_id": "meteor-2026",
            "event_type": "meteorShower",
            "title": "英仙座流星雨极大期",
            "source_url": "https://science.nasa.gov/meteor-showers/",
            "starts_at": datetime(2026, 7, 14, 1, tzinfo=timezone.utc),
            "ends_at": datetime(2026, 7, 14, 4, tzinfo=timezone.utc),
        }]

    monkeypatch.setattr(ContextStore, "active_astronomy_events", astronomy_events)
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/evaluate",
            json=payload(),
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )

    assert response.status_code == 200
    event = next(item for item in response.json()["events"] if item["source"] == "astronomyCatalog")
    assert event["title"] == "英仙座流星雨极大期"
    assert event["sourceUrl"].startswith("https://")
    assert event["allowedAction"] == "openAstronomyDetail"


def test_source_status_exposes_all_enabled_qweather_sources(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    with TestClient(app) as client:
        response = client.get(
            "/internal/v1/sources",
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
    assert response.status_code == 200
    sources = {source["id"]: source for source in response.json()}
    assert sources["qweather-hourly"]["enabled"] is True
    assert sources["qweather-warning"]["licenseStatus"] == "approved"
    assert sources["qweather-air-quality"]["enabled"] is True
    assert sources["qweather-air-quality"]["licenseStatus"] == "approved"


def test_internal_wildlife_layers_require_token_and_return_reviewed_areas(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")

    async def fake_layers(_store, latitude, longitude, radius_km):
        assert (latitude, longitude, radius_km) == (30.25, 120.15, 20)
        return [WildlifeLayerArea.model_validate({
            "id": "a" * 64,
            "name": "历史观察区域",
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [120.0, 30.0], [120.2, 30.0], [120.2, 30.2], [120.0, 30.0]
                ]],
            },
            "source": {
                "attribution": "Reviewed wildlife dataset",
                "version": "2026.07",
                "updatedAt": "2026-07-16T00:00:00Z",
            },
        })]

    monkeypatch.setattr(ContextStore, "wildlife_layers", fake_layers)
    path = "/internal/v1/wildlife/layers?latitude=30.25&longitude=120.15&radiusKm=20"
    with TestClient(app) as client:
        assert client.get(path).status_code == 401
        response = client.get(
            path,
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["contractVersion"] == 1
    assert body["radiusKm"] == 20
    assert body["areas"][0]["name"] == "历史观察区域"
    assert body["areas"][0]["source"]["attribution"] == "Reviewed wildlife dataset"
    assert "sourceId" not in str(body)


def test_wildlife_layer_contract_rejects_points_and_radius_outside_policy(monkeypatch):
    with pytest.raises(ValidationError):
        WildlifeLayerArea.model_validate({
            "id": "b" * 64,
            "name": "must not expose a point",
            "geometry": {"type": "Point", "coordinates": [120.1, 30.1]},
            "source": {"attribution": "fixture", "version": "1"},
        })

    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    with TestClient(app) as client:
        response = client.get(
            "/internal/v1/wildlife/layers?latitude=30&longitude=120&radiusKm=2",
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_wildlife_layer_store_filters_license_and_hides_sensitive_names():
    captured = {}

    class FakeMappings:
        def all(self):
            return [{
                "id": "c" * 64,
                "public_name": "历史观察区域",
                "geometry": '{"type":"Polygon","coordinates":[[[120,30],[120.2,30],[120.2,30.2],[120,30]]]}',
                "attribution": "Reviewed fixture",
                "version": "2026.07",
                "updated_at": datetime(2026, 7, 16, tzinfo=timezone.utc),
            }]

    class FakeResult:
        def mappings(self):
            return FakeMappings()

    class FakeConnection:
        async def execute(self, statement, parameters):
            captured["statement"] = str(statement)
            captured["parameters"] = parameters
            return FakeResult()

    class ConnectionContext:
        async def __aenter__(self):
            return FakeConnection()

        async def __aexit__(self, *_args):
            return None

    class FakeEngine:
        def connect(self):
            return ConnectionContext()

    store = ContextStore(None, None)
    store.engine = FakeEngine()
    result = await store.wildlife_layers(30.1, 120.1, 20)

    assert result[0].name == "历史观察区域"
    assert captured["parameters"]["radius_meters"] == 20_000
    assert "license_status = 'approved'" in captured["statement"]
    assert "category = 'wildlifeHistorical'" in captured["statement"]
    assert "sensitivity = 'sensitive'" in captured["statement"]


def test_server_computes_solar_and_keeps_official_warning_out_of_model_control(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    request = payload()
    request.pop("solar")
    request["evidence"] = {}
    request["officialWarnings"] = [{
        "id": "abcdef123456",
        "observedAt": "2026-07-14T09:55:00+08:00",
        "expiresAt": "2026-07-14T12:00:00+08:00",
        "severity": "critical",
        "title": "雷电红色预警",
    }]
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/evaluate",
            json=request,
            headers={"X-Internal-Service-Token": "internal-test-token"},
        )
    assert response.status_code == 200
    body = response.json()
    warning = next(event for event in body["events"] if event["source"] == "official")
    assert warning["id"] == "weather-warning-abcdef123456"
    assert warning["severity"] == "critical"
    assert warning["title"] == "雷电红色预警"
    assert warning["allowedAction"] == "openSafetyDetail"
    assert body["sunMoon"]["sunElevationDegrees"] is not None


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


def test_photography_target_import_requires_an_explicit_public_scene_point():
    valid = spatial_import_payload()
    valid["featureCollection"]["features"][0] = {
        "type": "Feature", "id": "east-bank", "geometry": {
            "type": "Point", "coordinates": [120.151, 30.251],
        },
        "properties": {
            "kind": "water", "name": "东岸观景台", "photographyTarget": True,
            "targetType": "lakeshore",
        },
    }
    assert SpatialFeaturesImport.model_validate(valid).feature_collection.features[0].properties.target_type == "lakeshore"

    sensitive = valid | {"featureCollection": valid["featureCollection"] | {"features": [{
        **valid["featureCollection"]["features"][0],
        "properties": valid["featureCollection"]["features"][0]["properties"] | {"sensitivity": "sensitive"},
    }]}}
    with pytest.raises(ValueError):
        SpatialFeaturesImport.model_validate(sensitive)


def test_shooting_target_import_requires_traceable_license_shoreline_and_review():
    valid = spatial_import_payload()
    valid["source"] |= {
        "licenseId": "CC-BY-4.0",
        "sourceUrl": "https://source.example/lakes/east-bank",
        "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
    }
    valid["featureCollection"]["features"][0] = {
        "type": "Feature",
        "id": "east-bank-reviewed",
        "geometry": {"type": "Point", "coordinates": [120.151, 30.251]},
        "properties": {
            "kind": "water",
            "name": "东岸审核湖岸",
            "photographyTarget": True,
            "targetType": "lakeshore",
            "shootingSessionTarget": True,
            "supportedSessions": ["waterMorning", "waterEvening"],
            "viewBearingDegrees": 286,
            "bearingToleranceDegrees": 25,
            "accessModes": ["driving", "walking"],
            "leadTimeMinutes": 12,
            "arrivalRadiusMeters": 100,
            "shorelineSide": "east",
            "reviewedAt": "2026-07-18T00:00:00Z",
            "reviewReference": "https://review.example/targets/east-bank",
        },
    }

    imported = SpatialFeaturesImport.model_validate(valid)
    target = imported.feature_collection.features[0].properties
    assert target.supported_sessions == ["waterMorning", "waterEvening"]
    assert target.shoreline_side == "east"

    missing_license = deepcopy(valid)
    missing_license["source"].pop("licenseId")
    with pytest.raises(ValueError):
        SpatialFeaturesImport.model_validate(missing_license)

    missing_review = deepcopy(valid)
    missing_review["featureCollection"]["features"][0]["properties"].pop(
        "reviewReference"
    )
    with pytest.raises(ValueError):
        SpatialFeaturesImport.model_validate(missing_review)

    duplicate_sessions = deepcopy(valid)
    duplicate_sessions["featureCollection"]["features"][0]["properties"][
        "supportedSessions"
    ] = ["waterEvening", "waterEvening"]
    with pytest.raises(ValueError):
        SpatialFeaturesImport.model_validate(duplicate_sessions)


def test_import_requires_reviewed_source_categories_for_wildlife_evidence(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    headers = {"X-Internal-Service-Token": "internal-test-token"}
    opportunity = spatial_import_payload()
    opportunity["featureCollection"]["features"][0]["properties"] = {
        "kind": "protected", "name": "Reviewed observation area", "sensitivity": "sensitive",
        "evidenceClass": "wildlifeOpportunity",
    }
    opportunity["featureCollection"]["features"][0]["geometry"] = {
        "type": "Polygon",
        "coordinates": [[[120.0, 30.0], [120.2, 30.0], [120.2, 30.2], [120.0, 30.0]]],
    }
    async def fake_import(_store, body):
        return ContextImportResult.model_validate({
            "sourceId": body.source.id,
            "datasetType": body.dataset_type,
            "importedCount": len(body.feature_collection.features),
            "enabled": body.source.enabled,
            "cacheInvalidated": True,
        })

    monkeypatch.setattr(ContextStore, "import_dataset", fake_import)
    with TestClient(app) as client:
        assert client.post("/internal/v1/imports", json=opportunity, headers=headers).status_code == 422
        opportunity["source"]["category"] = "wildlifeHistorical"
        assert client.post("/internal/v1/imports", json=opportunity, headers=headers).status_code == 201


@pytest.fixture
def internal_headers(monkeypatch):
    monkeypatch.setenv("CONTEXT_INTERNAL_TOKEN", "internal-test-token")
    return {"X-Internal-Service-Token": "internal-test-token"}


@pytest.mark.parametrize("mode,stage", [("none", "active"), ("driving", "none")])
def test_route_input_rejects_mode_stage_mismatch(mode, stage, internal_headers):
    request = payload()
    request["route"] = {"mode": mode, "stage": stage}
    with TestClient(app) as client:
        response = client.post("/internal/v1/evaluate", json=request, headers=internal_headers)
    assert response.status_code == 422


def test_route_input_accepts_none_none(internal_headers):
    request = payload()
    request["route"] = {"mode": "none", "stage": "none"}
    with TestClient(app) as client:
        response = client.post("/internal/v1/evaluate", json=request, headers=internal_headers)
    assert response.status_code == 200
    assert response.json()["route"] == {"mode": "none", "stage": "none", "active": False}


@pytest.mark.parametrize("stage,active", [
    ("planned", False),
    ("active", True),
    ("paused", False),
])
def test_route_input_accepts_driving_stages(stage, active, internal_headers):
    request = payload()
    request["route"] = {"mode": "driving", "stage": stage}
    with TestClient(app) as client:
        response = client.post("/internal/v1/evaluate", json=request, headers=internal_headers)
    assert response.status_code == 200
    assert response.json()["route"] == {"mode": "driving", "stage": stage, "active": active}


def test_route_state_model_rejects_active_mismatch():
    # stage == "planned" requires active == False; True must be rejected.
    with pytest.raises(ValidationError):
        RouteState.model_validate({"mode": "driving", "stage": "planned", "active": True})
    # stage == "active" requires active == True; False must be rejected.
    with pytest.raises(ValidationError):
        RouteState.model_validate({"mode": "driving", "stage": "active", "active": False})
