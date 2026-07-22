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
    assert body == {
        "status": "ready",
        "radiance": body["radiance"],
        "radianceUnit": "nW/cm2/sr",
        "datasetYear": 2024,
        "datasetRevision": "eog-v2.2-2024-median-masked-r1",
        "resolutionMeters": 500,
        "sampledLatitude": body["sampledLatitude"],
        "sampledLongitude": body["sampledLongitude"],
        "sourceId": "eog-viirs-annual-v2.2",
        "attribution": "Earth Observation Group",
    }
    assert abs(body["radiance"] - 0.1) < 0.0001
    assert abs(body["sampledLatitude"] - 30.75) < 0.0001
    assert abs(body["sampledLongitude"] - 120.25) < 0.0001


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
