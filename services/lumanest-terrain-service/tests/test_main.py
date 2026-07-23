from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio
from fastapi.testclient import TestClient
from rasterio.transform import from_origin

from app.main import DemHorizonSampler, TerrainMetadata, create_app

TOKEN = "terrain-secret"


def _metadata(revision: str = "copernicus-glo30-test-r1") -> TerrainMetadata:
    return TerrainMetadata(
        source_id="copernicus-dem-glo30",
        attribution="Copernicus DEM",
        dataset_revision=revision,
        resolution_meters=30,
    )


def _write_dem(path: Path, *, crs: str | None = "EPSG:4326") -> tuple[float, float]:
    size = 121
    data = np.full((size, size), 100.0, dtype="float32")
    center = size // 2
    data[:, center + 18 : center + 22] = 350.0
    transform = from_origin(119.94, 30.06, 0.001, 0.001)
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=size,
        width=size,
        count=1,
        dtype=data.dtype,
        crs=crs,
        transform=transform,
        nodata=-9999,
    ) as dataset:
        dataset.write(data, 1)
        x, y = dataset.xy(center, center, offset="center")
    return float(y), float(x)


def _authorized_get(client: TestClient, path: str, **kwargs):
    return client.get(path, headers={"Authorization": f"Bearer {TOKEN}"}, **kwargs)


def test_horizon_profile_detects_the_eastern_ridge(tmp_path: Path) -> None:
    path = tmp_path / "dem.tif"
    latitude, longitude = _write_dem(path)
    sampler = DemHorizonSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = _authorized_get(
            client,
            "/v1/dem/horizon",
            params={"latitude": latitude, "longitude": longitude},
        )
    assert response.status_code == 200
    body = response.json()
    assert body["algorithmVersion"] == "terrain-horizon-radial.1"
    assert body["azimuthStepDegrees"] == 5
    assert len(body["samples"]) == 72
    by_azimuth = {item["azimuthDegrees"]: item for item in body["samples"]}
    assert by_azimuth[90]["horizonAltitudeDegrees"] > by_azimuth[270]["horizonAltitudeDegrees"]
    assert 1 <= by_azimuth[90]["obstructionDistanceKm"] <= 4
    assert by_azimuth[90]["obstructionElevationMeters"] == 350
    assert 0 < body["coverageRatio"] <= 1


def test_horizon_endpoint_requires_internal_authentication(tmp_path: Path) -> None:
    path = tmp_path / "dem.tif"
    latitude, longitude = _write_dem(path)
    sampler = DemHorizonSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        missing = client.get(
            "/v1/dem/horizon",
            params={"latitude": latitude, "longitude": longitude},
        )
        wrong = client.get(
            "/v1/dem/horizon",
            params={"latitude": latitude, "longitude": longitude},
            headers={"Authorization": "Bearer wrong"},
        )
    assert missing.status_code == 401
    assert wrong.status_code == 401
    assert missing.headers["www-authenticate"] == "Bearer"


def test_horizon_endpoint_rejects_points_outside_the_dem(tmp_path: Path) -> None:
    path = tmp_path / "dem.tif"
    _write_dem(path)
    sampler = DemHorizonSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = _authorized_get(
            client,
            "/v1/dem/horizon",
            params={"latitude": 10, "longitude": 10},
        )
    assert response.status_code == 404


def test_health_reports_validated_dem_and_algorithm_metadata(tmp_path: Path) -> None:
    path = tmp_path / "dem.tif"
    _write_dem(path)
    sampler = DemHorizonSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        body = client.get("/healthz").json()
    assert body["status"] == "ok"
    assert body["demConfigured"] is True
    assert body["demReady"] is True
    assert body["authenticationConfigured"] is True
    assert body["dataset"]["dataset_revision"] == "copernicus-glo30-test-r1"
    assert body["algorithm"]["azimuthStepDegrees"] == 5


def test_health_rejects_a_present_dem_without_a_crs(tmp_path: Path) -> None:
    path = tmp_path / "invalid.tif"
    _write_dem(path, crs=None)
    sampler = DemHorizonSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        health = client.get("/healthz").json()
    assert health["status"] == "degraded"
    assert health["demConfigured"] is True
    assert health["demReady"] is False
    assert "CRS" in health["error"]
