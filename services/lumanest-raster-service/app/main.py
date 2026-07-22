from __future__ import annotations

import math
import os
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import Any

import numpy as np
import rasterio
from fastapi import FastAPI, HTTPException, Query
from rasterio.crs import CRS
from rasterio.errors import RasterioIOError
from rasterio.warp import transform


@dataclass(frozen=True)
class RasterMetadata:
    source_id: str
    attribution: str
    dataset_year: int
    resolution_meters: float


class ViirsRasterSampler:
    def __init__(self, path: str, metadata: RasterMetadata) -> None:
        self.path = Path(path)
        self.metadata = metadata
        self._dataset: Any | None = None
        self._lock = Lock()

    @property
    def configured(self) -> bool:
        return bool(str(self.path)) and self.path.is_file()

    def close(self) -> None:
        with self._lock:
            if self._dataset is not None:
                self._dataset.close()
                self._dataset = None

    def _open(self):
        if self._dataset is None:
            self._dataset = rasterio.open(self.path)
            if self._dataset.count < 1:
                self._dataset.close()
                self._dataset = None
                raise RasterioIOError("VIIRS raster has no bands")
        return self._dataset

    def sample(self, latitude: float, longitude: float) -> float | None:
        if not self.configured:
            return None
        with self._lock:
            dataset = self._open()
            source_crs = CRS.from_epsg(4326)
            target_crs = dataset.crs or source_crs
            xs, ys = transform(source_crs, target_crs, [longitude], [latitude])
            x, y = xs[0], ys[0]
            bounds = dataset.bounds
            if x < bounds.left or x > bounds.right or y < bounds.bottom or y > bounds.top:
                return None
            value = next(dataset.sample([(x, y)], indexes=1, masked=True), None)
            if value is None or len(value) != 1 or np.ma.is_masked(value[0]):
                return None
            radiance = float(value[0])
            if not math.isfinite(radiance) or radiance < 0:
                return None
            return radiance


def _integer_environment(name: str, fallback: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.getenv(name, str(fallback)))
    except ValueError:
        return fallback
    return min(maximum, max(minimum, value))


def _float_environment(name: str, fallback: float, minimum: float, maximum: float) -> float:
    try:
        value = float(os.getenv(name, str(fallback)))
    except ValueError:
        return fallback
    if not math.isfinite(value):
        return fallback
    return min(maximum, max(minimum, value))


def create_app(sampler: ViirsRasterSampler | None = None) -> FastAPI:
    active_sampler = sampler or ViirsRasterSampler(
        os.getenv("VIIRS_RASTER_PATH", ""),
        RasterMetadata(
            source_id=os.getenv("VIIRS_SOURCE_ID", "eog-viirs-annual-v2.2")[:120],
            attribution=os.getenv(
                "VIIRS_ATTRIBUTION",
                "Earth Observation Group VIIRS annual nighttime lights",
            )[:240],
            dataset_year=_integer_environment("VIIRS_DATASET_YEAR", 2024, 2012, 2100),
            resolution_meters=_float_environment(
                "VIIRS_RESOLUTION_METERS", 500.0, 1.0, 10_000.0
            ),
        ),
    )
    app = FastAPI(title="LumaNest Raster Service", version="1.0")
    app.state.viirs_sampler = active_sampler

    @app.on_event("shutdown")
    def close_sampler() -> None:
        active_sampler.close()

    @app.get("/healthz")
    def health() -> dict[str, object]:
        return {
            "status": "ok" if active_sampler.configured else "degraded",
            "viirsConfigured": active_sampler.configured,
        }

    @app.get("/v1/viirs/sample")
    def sample_viirs(
        latitude: float = Query(ge=-90, le=90),
        longitude: float = Query(ge=-180, le=180),
    ) -> dict[str, object]:
        if not active_sampler.configured:
            raise HTTPException(status_code=503, detail="viirs_unconfigured")
        try:
            radiance = active_sampler.sample(latitude, longitude)
        except RasterioIOError as error:
            raise HTTPException(status_code=503, detail="viirs_unavailable") from error
        if radiance is None:
            raise HTTPException(status_code=404, detail="viirs_sample_unavailable")
        metadata = active_sampler.metadata
        return {
            "status": "ready",
            "radiance": radiance,
            "radianceUnit": "nW/cm2/sr",
            "datasetYear": metadata.dataset_year,
            "resolutionMeters": metadata.resolution_meters,
            "sourceId": metadata.source_id,
            "attribution": metadata.attribution,
        }

    return app


app = create_app()
