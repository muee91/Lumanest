from __future__ import annotations

import math
import os
import secrets
from dataclasses import asdict, dataclass
from pathlib import Path
from threading import Lock
from typing import Any

import numpy as np
import rasterio
from fastapi import FastAPI, Header, HTTPException, Query
from rasterio.crs import CRS
from rasterio.errors import RasterioIOError
from rasterio.windows import Window
from rasterio.warp import transform


@dataclass(frozen=True)
class RasterMetadata:
    source_id: str
    attribution: str
    dataset_year: int
    resolution_meters: float
    dataset_revision: str


@dataclass(frozen=True)
class RasterSample:
    radiance: float
    latitude: float
    longitude: float


class ViirsRasterSampler:
    def __init__(self, path: str, metadata: RasterMetadata) -> None:
        self.path = Path(path)
        self.metadata = metadata
        self._dataset: Any | None = None
        self._inspection: dict[str, object] | None = None
        self._lock = Lock()

    @property
    def configured(self) -> bool:
        return bool(str(self.path)) and self.path.is_file()

    @property
    def ready(self) -> bool:
        return bool(self.inspect().get("ready"))

    def close(self) -> None:
        with self._lock:
            if self._dataset is not None:
                self._dataset.close()
                self._dataset = None

    def _open_unlocked(self):
        if self._dataset is None:
            self._dataset = rasterio.open(self.path)
        return self._dataset

    def inspect(self) -> dict[str, object]:
        with self._lock:
            if self._inspection is not None:
                return dict(self._inspection)
            if not self.configured:
                self._inspection = {
                    "ready": False,
                    "error": "viirs_unconfigured",
                }
                return dict(self._inspection)
            try:
                dataset = self._open_unlocked()
                if dataset.count < 1:
                    raise RasterioIOError("VIIRS raster has no bands")
                if dataset.crs is None:
                    raise RasterioIOError("VIIRS raster has no CRS")
                if dataset.width < 1 or dataset.height < 1:
                    raise RasterioIOError("VIIRS raster has invalid dimensions")
                bounds = dataset.bounds
                if not all(math.isfinite(value) for value in bounds):
                    raise RasterioIOError("VIIRS raster has invalid bounds")
                if bounds.left >= bounds.right or bounds.bottom >= bounds.top:
                    raise RasterioIOError("VIIRS raster has empty bounds")
                dtype = np.dtype(dataset.dtypes[0])
                if not np.issubdtype(dtype, np.number):
                    raise RasterioIOError("VIIRS raster band is not numeric")
                self._inspection = {
                    "ready": True,
                    "error": None,
                    "crs": dataset.crs.to_string(),
                    "width": dataset.width,
                    "height": dataset.height,
                    "bounds": {
                        "left": bounds.left,
                        "bottom": bounds.bottom,
                        "right": bounds.right,
                        "top": bounds.top,
                    },
                    "bandCount": dataset.count,
                    "dtype": dataset.dtypes[0],
                    "nodata": dataset.nodata,
                }
            except (RasterioIOError, ValueError, TypeError) as error:
                if self._dataset is not None:
                    self._dataset.close()
                    self._dataset = None
                self._inspection = {
                    "ready": False,
                    "error": str(error)[:240] or "viirs_unavailable",
                }
            return dict(self._inspection)

    def health_snapshot(self, authentication_configured: bool) -> dict[str, object]:
        inspection = self.inspect()
        ready = bool(inspection.get("ready"))
        status = "ok" if ready and authentication_configured else "degraded"
        return {
            "status": status,
            "viirsConfigured": self.configured,
            "viirsReady": ready,
            "authenticationConfigured": authentication_configured,
            "error": inspection.get("error"),
            "dataset": {
                **asdict(self.metadata),
                **{key: value for key, value in inspection.items() if key not in {"ready", "error"}},
            }
            if ready
            else None,
        }

    def sample(self, latitude: float, longitude: float) -> RasterSample | None:
        if not self.ready:
            return None
        with self._lock:
            dataset = self._open_unlocked()
            source_crs = CRS.from_epsg(4326)
            target_crs = dataset.crs
            xs, ys = transform(source_crs, target_crs, [longitude], [latitude])
            x, y = xs[0], ys[0]
            bounds = dataset.bounds
            if x < bounds.left or x >= bounds.right or y < bounds.bottom or y >= bounds.top:
                return None
            row, column = dataset.index(x, y)
            if row < 0 or row >= dataset.height or column < 0 or column >= dataset.width:
                return None
            value = dataset.read(
                1,
                window=Window(column, row, 1, 1),
                masked=True,
            )
            if value.size != 1 or np.ma.is_masked(value[0, 0]):
                return None
            radiance = float(value[0, 0])
            if not math.isfinite(radiance) or radiance < 0:
                return None
            center_x, center_y = dataset.xy(row, column, offset="center")
            longitudes, latitudes = transform(
                target_crs,
                source_crs,
                [center_x],
                [center_y],
            )
            return RasterSample(
                radiance=radiance,
                latitude=float(latitudes[0]),
                longitude=float(longitudes[0]),
            )


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


def _bounded_environment(name: str, fallback: str, maximum: int) -> str:
    value = os.getenv(name, fallback).strip()
    return value[:maximum]


def _authorized(authorization: str | None, service_token: str) -> bool:
    if not service_token or authorization is None:
        return False
    expected = f"Bearer {service_token}"
    return secrets.compare_digest(authorization, expected)


def create_app(
    sampler: ViirsRasterSampler | None = None,
    service_token: str | None = None,
) -> FastAPI:
    active_sampler = sampler or ViirsRasterSampler(
        os.getenv("VIIRS_RASTER_PATH", ""),
        RasterMetadata(
            source_id=_bounded_environment(
                "VIIRS_SOURCE_ID", "eog-viirs-annual-v2.2", 120
            ),
            attribution=_bounded_environment(
                "VIIRS_ATTRIBUTION",
                "Earth Observation Group VIIRS annual nighttime lights",
                240,
            ),
            dataset_year=_integer_environment("VIIRS_DATASET_YEAR", 2024, 2012, 2100),
            resolution_meters=_float_environment(
                "VIIRS_RESOLUTION_METERS", 500.0, 1.0, 10_000.0
            ),
            dataset_revision=_bounded_environment(
                "VIIRS_DATASET_REVISION", "unversioned", 120
            ),
        ),
    )
    active_service_token = (
        service_token.strip()
        if service_token is not None
        else os.getenv("RASTER_SERVICE_TOKEN", "").strip()
    )
    active_sampler.inspect()
    app = FastAPI(title="LumaNest Raster Service", version="1.1")
    app.state.viirs_sampler = active_sampler

    @app.on_event("shutdown")
    def close_sampler() -> None:
        active_sampler.close()

    @app.get("/healthz")
    def health() -> dict[str, object]:
        return active_sampler.health_snapshot(bool(active_service_token))

    @app.get("/v1/viirs/sample")
    def sample_viirs(
        latitude: float = Query(ge=-90, le=90),
        longitude: float = Query(ge=-180, le=180),
        authorization: str | None = Header(default=None, alias="Authorization"),
    ) -> dict[str, object]:
        if not active_service_token:
            raise HTTPException(status_code=503, detail="raster_auth_unconfigured")
        if not _authorized(authorization, active_service_token):
            raise HTTPException(
                status_code=401,
                detail="invalid_raster_service_token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        inspection = active_sampler.inspect()
        if not active_sampler.configured:
            raise HTTPException(status_code=503, detail="viirs_unconfigured")
        if not inspection.get("ready"):
            raise HTTPException(status_code=503, detail="viirs_unavailable")
        try:
            sample = active_sampler.sample(latitude, longitude)
        except RasterioIOError as error:
            raise HTTPException(status_code=503, detail="viirs_unavailable") from error
        if sample is None:
            raise HTTPException(status_code=404, detail="viirs_sample_unavailable")
        metadata = active_sampler.metadata
        return {
            "status": "ready",
            "radiance": sample.radiance,
            "radianceUnit": "nW/cm2/sr",
            "datasetYear": metadata.dataset_year,
            "datasetRevision": metadata.dataset_revision,
            "resolutionMeters": metadata.resolution_meters,
            "sampledLatitude": sample.latitude,
            "sampledLongitude": sample.longitude,
            "sourceId": metadata.source_id,
            "attribution": metadata.attribution,
        }

    return app


app = create_app()
