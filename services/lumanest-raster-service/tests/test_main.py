from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio
from fastapi.testclient import TestClient
from rasterio.transform import from_origin

from app.main import RasterMetadata, ViirsRasterSampler, create_app


def _write_raster(path: Path) -> None:
    data = np.array([[0.1, 0.4], [1.2, 8.0]], dtype="float32")
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=2,
        width=2,
        count=1,
        dtype=data.dtype,
        crs="EPSG:4326",
        transform=from_origin(120.0, 31.0, 0.5, 0.5),
        nodata=-9999,
    ) as dataset:
        dataset.write(data, 1)


def test_viirs_endpoint_samples_the_configured_geotiff(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(
        str(path),
        RasterMetadata(
            source_id="eog-viirs-annual-v2.2",
            attribution="Earth Observation Group",
            dataset_year=2024,
            resolution_meters=500,
        ),
    )
    with TestClient(create_app(sampler)) as client:
        response = client.get(
            "/v1/viirs/sample", params={"latitude": 30.75, "longitude": 120.25}
        )
    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "radiance": response.json()["radiance"],
        "radianceUnit": "nW/cm2/sr",
        "datasetYear": 2024,
        "resolutionMeters": 500,
        "sourceId": "eog-viirs-annual-v2.2",
        "attribution": "Earth Observation Group",
    }
    assert abs(response.json()["radiance"] - 0.1) < 0.0001


def test_viirs_endpoint_rejects_points_outside_the_raster(tmp_path: Path) -> None:
    path = tmp_path / "viirs.tif"
    _write_raster(path)
    sampler = ViirsRasterSampler(
        str(path), RasterMetadata("test", "test", 2024, 500)
    )
    with TestClient(create_app(sampler)) as client:
        response = client.get(
            "/v1/viirs/sample", params={"latitude": 10, "longitude": 10}
        )
    assert response.status_code == 404


def test_health_is_degraded_without_a_raster(tmp_path: Path) -> None:
    sampler = ViirsRasterSampler(
        str(tmp_path / "missing.tif"), RasterMetadata("test", "test", 2024, 500)
    )
    with TestClient(create_app(sampler)) as client:
        response = client.get("/healthz")
    assert response.json() == {"status": "degraded", "viirsConfigured": False}
