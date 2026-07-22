from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio
from fastapi.testclient import TestClient
from rasterio.transform import from_origin

from app.main import RasterMetadata, ViirsRasterSampler, create_app

TOKEN = "internal-secret"


def _metadata(revision: str = "eog-v2.2-2024-median-masked-r1") -> RasterMetadata:
    return RasterMetadata(
        source_id="eog-viirs-annual-v2.2",
        attribution="Earth Observation Group",
        dataset_year=2024,
        resolution_meters=500,
        dataset_revision=revision,
    )


def _write_raster(path: Path, *, crs: str | None = "EPSG:4326") -> None:
    data = np.array([[0.1, 0.4], [1.2, 8.0]], dtype="float32")
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=2,
        width=2,
        count=1,
        dtype=data.dtype,
        crs=crs,
        transform=from_origin(120.0, 31.0, 0.5, 0.5),
        nodata=-9999,
    ) as dataset:
        dataset.write(data, 1)


def _write_spatial_raster(path: Path) -> None:
    size = 81
    data = np.full((size, size), 0.2, dtype="float32")
    data[50:60, 50:60] = 20.0
    data[25:30, 20:25] = -9999
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=size,
        width=size,
        count=1,
        dtype=data.dtype,
        crs="EPSG:4326",
        transform=from_origin(119.7975, 30.2025, 0.005, 0.005),
        nodata=-9999,
    ) as dataset:
        dataset.write(data, 1)


def _authorized_get(client: TestClient, path: str, **kwargs):
    headers = {"Authorization": f"Bearer {TOKEN}"}
    return client.get(path, headers=headers, **kwargs)


def test_viirs_endpoint_samples_the_configured_geotiff(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = _authorized_get(
            client,
            "/v1/viirs/sample",
            params={"latitude": 30.75, "longitude": 120.25},
        )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["radianceUnit"] == "nW/cm2/sr"
    assert body["datasetYear"] == 2024
    assert body["datasetRevision"] == "eog-v2.2-2024-median-masked-r1"
    assert body["resolutionMeters"] == 500
    assert body["sourceId"] == "eog-viirs-annual-v2.2"
    assert body["attribution"] == "Earth Observation Group"
    assert abs(body["radiance"] - 0.1) < 0.0001
    assert abs(body["sampledLatitude"] - 30.75) < 0.0001
    assert abs(body["sampledLongitude"] - 120.25) < 0.0001
    analysis = body["spatialAnalysis"]
    assert analysis["analysisVersion"] == "viirs-spatial-radiance.1"
    assert [item["radiusKm"] for item in analysis["neighborhoods"]] == [1.0, 5.0, 20.0]
    assert analysis["lightDomes"]["sectorCount"] == 8


def test_spatial_analysis_detects_a_southeast_light_dome(tmp_path: Path) -> None:
    path = tmp_path / "spatial.tif"
    _write_spatial_raster(path)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = _authorized_get(
            client,
            "/v1/viirs/sample",
            params={"latitude": 30.0, "longitude": 120.0},
        )
    assert response.status_code == 200
    analysis = response.json()["spatialAnalysis"]
    neighborhoods = {item["radiusKm"]: item for item in analysis["neighborhoods"]}
    assert neighborhoods[1.0]["sampleCount"] > 0
    assert neighborhoods[1.0]["coverageRatio"] == 1.0
    assert neighborhoods[20.0]["maximum"] == 20.0
    assert 0 < neighborhoods[20.0]["coverageRatio"] < 1.0
    light_domes = analysis["lightDomes"]
    assert light_domes["dominantDirection"] == "southeast"
    assert light_domes["dominantAzimuthDegrees"] == 135.0
    assert len(light_domes["sectors"]) == 8
    southeast = next(
        sector for sector in light_domes["sectors"] if sector["direction"] == "southeast"
    )
    assert southeast["p90"] == 20.0
    assert 1.0 < southeast["peakDistanceKm"] <= 20.0
    assert southeast["coverageRatio"] == 1.0


def test_viirs_endpoint_requires_the_internal_bearer_token(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        missing = client.get(
            "/v1/viirs/sample",
            params={"latitude": 30.75, "longitude": 120.25},
        )
        wrong = client.get(
            "/v1/viirs/sample",
            params={"latitude": 30.75, "longitude": 120.25},
            headers={"Authorization": "Bearer wrong"},
        )
    assert missing.status_code == 401
    assert wrong.status_code == 401
    assert missing.headers["www-authenticate"] == "Bearer"


def test_viirs_endpoint_rejects_points_outside_the_raster(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = _authorized_get(
            client,
            "/v1/viirs/sample",
            params={"latitude": 10, "longitude": 10},
        )
    assert response.status_code == 404


def test_health_eagerly_reports_validated_dataset_metadata(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        response = client.get("/healthz")
    body = response.json()
    assert body["status"] == "ok"
    assert body["viirsConfigured"] is True
    assert body["viirsReady"] is True
    assert body["authenticationConfigured"] is True
    assert body["error"] is None
    assert body["dataset"]["dataset_revision"] == "eog-v2.2-2024-median-masked-r1"
    assert body["dataset"]["crs"] == "EPSG:4326"
    assert body["dataset"]["width"] == 2
    assert body["dataset"]["height"] == 2
    assert body["dataset"]["spatialAnalysisVersion"] == "viirs-spatial-radiance.1"
    assert body["dataset"]["spatialAnalysisMaximumRadiusKm"] == 20.0


def test_health_is_degraded_without_a_raster_or_authentication(tmp_path: Path) -> None:
    sampler = ViirsRasterSampler(str(tmp_path / "missing.tif"), _metadata())
    with TestClient(create_app(sampler, service_token="")) as client:
        response = client.get("/healthz")
        sample = client.get(
            "/v1/viirs/sample",
            params={"latitude": 30.75, "longitude": 120.25},
        )
    assert response.json() == {
        "status": "degraded",
        "viirsConfigured": False,
        "viirsReady": False,
        "authenticationConfigured": False,
        "error": "viirs_unconfigured",
        "dataset": None,
    }
    assert sample.status_code == 503
    assert sample.json()["detail"] == "raster_auth_unconfigured"


def test_health_rejects_a_present_but_invalid_raster(tmp_path: Path) -> None:
    path = tmp_path / "invalid.tif"
    _write_raster(path, crs=None)
    sampler = ViirsRasterSampler(str(path), _metadata())
    with TestClient(create_app(sampler, service_token=TOKEN)) as client:
        health = client.get("/healthz")
        sample = _authorized_get(
            client,
            "/v1/viirs/sample",
            params={"latitude": 30.75, "longitude": 120.25},
        )
    assert health.json()["status"] == "degraded"
    assert health.json()["viirsConfigured"] is True
    assert health.json()["viirsReady"] is False
    assert "CRS" in health.json()["error"]
    assert sample.status_code == 503
    assert sample.json()["detail"] == "viirs_unavailable"
