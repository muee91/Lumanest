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
from rasterio.transform import xy
from rasterio.windows import Window
from rasterio.warp import transform

EARTH_RADIUS_KM = 6371.0088
ANALYSIS_RADII_KM = (1.0, 5.0, 20.0)
LIGHT_DOME_INNER_RADIUS_KM = 1.0
LIGHT_DOME_OUTER_RADIUS_KM = 20.0
LIGHT_DOME_DIRECTIONS = (
    ("north", 0.0),
    ("northeast", 45.0),
    ("east", 90.0),
    ("southeast", 135.0),
    ("south", 180.0),
    ("southwest", 225.0),
    ("west", 270.0),
    ("northwest", 315.0),
)
SPATIAL_ANALYSIS_VERSION = "viirs-spatial-radiance.1"


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
                self._inspection = {"ready": False, "error": "viirs_unconfigured"}
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
                    "spatialAnalysisVersion": SPATIAL_ANALYSIS_VERSION,
                    "spatialAnalysisMaximumRadiusKm": LIGHT_DOME_OUTER_RADIUS_KM,
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
                **{
                    key: value
                    for key, value in inspection.items()
                    if key not in {"ready", "error"}
                },
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
            value = dataset.read(1, window=Window(column, row, 1, 1), masked=True)
            if value.size != 1 or np.ma.is_masked(value[0, 0]):
                return None
            radiance = float(value[0, 0])
            if not math.isfinite(radiance) or radiance < 0:
                return None
            center_x, center_y = dataset.xy(row, column, offset="center")
            longitudes, latitudes = transform(
                target_crs, source_crs, [center_x], [center_y]
            )
            return RasterSample(
                radiance=radiance,
                latitude=float(latitudes[0]),
                longitude=float(longitudes[0]),
            )

    def spatial_analysis(self, latitude: float, longitude: float) -> dict[str, object] | None:
        if not self.ready:
            return None
        with self._lock:
            dataset = self._open_unlocked()
            window = self._analysis_window(
                dataset, latitude, longitude, LIGHT_DOME_OUTER_RADIUS_KM
            )
            if window is None:
                return None
            data = dataset.read(1, window=window, masked=True)
            if data.size == 0:
                return None
            row_offsets, column_offsets = np.indices(data.shape)
            rows = (row_offsets + int(window.row_off)).ravel()
            columns = (column_offsets + int(window.col_off)).ravel()
            xs, ys = xy(dataset.transform, rows, columns, offset="center")
            longitudes, latitudes = transform(
                dataset.crs, CRS.from_epsg(4326), list(xs), list(ys)
            )
            radiance = np.ma.filled(data, np.nan).astype("float64", copy=False).ravel()
            latitude_values = np.asarray(latitudes, dtype="float64")
            longitude_values = np.asarray(longitudes, dtype="float64")
            distances = self._haversine_distances(
                latitude, longitude, latitude_values, longitude_values
            )
            bearings = self._initial_bearings(
                latitude, longitude, latitude_values, longitude_values
            )
            finite_values = np.isfinite(radiance) & (radiance >= 0)
            neighborhoods = [
                self._neighborhood_statistics(
                    radius_km, radiance, distances, finite_values
                )
                for radius_km in ANALYSIS_RADII_KM
            ]
            return {
                "analysisVersion": SPATIAL_ANALYSIS_VERSION,
                "maximumRadiusKm": LIGHT_DOME_OUTER_RADIUS_KM,
                "neighborhoods": neighborhoods,
                "lightDomes": self._light_dome_statistics(
                    radiance, distances, bearings, finite_values
                ),
            }

    @staticmethod
    def _analysis_window(dataset, latitude: float, longitude: float, radius_km: float):
        latitude_delta = math.degrees(radius_km / EARTH_RADIUS_KM)
        cosine = max(0.01, abs(math.cos(math.radians(latitude))))
        longitude_delta = min(
            180.0, math.degrees(radius_km / (EARTH_RADIUS_KM * cosine))
        )
        minimum_latitude = max(-90.0, latitude - latitude_delta)
        maximum_latitude = min(90.0, latitude + latitude_delta)
        minimum_longitude = max(-180.0, longitude - longitude_delta)
        maximum_longitude = min(180.0, longitude + longitude_delta)
        source_crs = CRS.from_epsg(4326)
        corner_longitudes = [
            minimum_longitude,
            maximum_longitude,
            maximum_longitude,
            minimum_longitude,
        ]
        corner_latitudes = [
            minimum_latitude,
            minimum_latitude,
            maximum_latitude,
            maximum_latitude,
        ]
        xs, ys = transform(
            source_crs, dataset.crs, corner_longitudes, corner_latitudes
        )
        indices = [dataset.index(x, y) for x, y in zip(xs, ys)]
        row_start = max(0, min(row for row, _ in indices) - 1)
        row_stop = min(dataset.height, max(row for row, _ in indices) + 2)
        column_start = max(0, min(column for _, column in indices) - 1)
        column_stop = min(dataset.width, max(column for _, column in indices) + 2)
        if row_start >= row_stop or column_start >= column_stop:
            return None
        return Window(
            column_start,
            row_start,
            column_stop - column_start,
            row_stop - row_start,
        )

    @staticmethod
    def _haversine_distances(
        latitude: float,
        longitude: float,
        latitudes: np.ndarray,
        longitudes: np.ndarray,
    ) -> np.ndarray:
        origin_latitude = math.radians(latitude)
        origin_longitude = math.radians(longitude)
        latitude_radians = np.radians(latitudes)
        longitude_radians = np.radians(longitudes)
        latitude_delta = latitude_radians - origin_latitude
        longitude_delta = longitude_radians - origin_longitude
        haversine = (
            np.sin(latitude_delta / 2.0) ** 2
            + math.cos(origin_latitude)
            * np.cos(latitude_radians)
            * np.sin(longitude_delta / 2.0) ** 2
        )
        return 2.0 * EARTH_RADIUS_KM * np.arcsin(
            np.sqrt(np.clip(haversine, 0.0, 1.0))
        )

    @staticmethod
    def _initial_bearings(
        latitude: float,
        longitude: float,
        latitudes: np.ndarray,
        longitudes: np.ndarray,
    ) -> np.ndarray:
        origin_latitude = math.radians(latitude)
        origin_longitude = math.radians(longitude)
        latitude_radians = np.radians(latitudes)
        longitude_radians = np.radians(longitudes)
        longitude_delta = longitude_radians - origin_longitude
        y = np.sin(longitude_delta) * np.cos(latitude_radians)
        x = (
            math.cos(origin_latitude) * np.sin(latitude_radians)
            - math.sin(origin_latitude)
            * np.cos(latitude_radians)
            * np.cos(longitude_delta)
        )
        return (np.degrees(np.arctan2(y, x)) + 360.0) % 360.0

    @staticmethod
    def _summary(values: np.ndarray) -> tuple[float, float, float]:
        return (
            float(np.median(values)),
            float(np.percentile(values, 90)),
            float(np.max(values)),
        )

    def _neighborhood_statistics(
        self,
        radius_km: float,
        radiance: np.ndarray,
        distances: np.ndarray,
        finite_values: np.ndarray,
    ) -> dict[str, object]:
        candidate_mask = distances <= radius_km
        valid_mask = candidate_mask & finite_values
        candidate_count = int(np.count_nonzero(candidate_mask))
        sample_count = int(np.count_nonzero(valid_mask))
        coverage_ratio = sample_count / candidate_count if candidate_count else 0.0
        if sample_count == 0:
            median = p90 = maximum = None
        else:
            median, p90, maximum = self._summary(radiance[valid_mask])
        return {
            "radiusKm": radius_km,
            "sampleCount": sample_count,
            "coverageRatio": float(coverage_ratio),
            "median": median,
            "p90": p90,
            "maximum": maximum,
        }

    def _light_dome_statistics(
        self,
        radiance: np.ndarray,
        distances: np.ndarray,
        bearings: np.ndarray,
        finite_values: np.ndarray,
    ) -> dict[str, object]:
        ring_mask = (
            (distances > LIGHT_DOME_INNER_RADIUS_KM)
            & (distances <= LIGHT_DOME_OUTER_RADIUS_KM)
        )
        sector_indices = np.floor(((bearings + 22.5) % 360.0) / 45.0).astype(int)
        sectors: list[dict[str, object]] = []
        for index, (direction, azimuth) in enumerate(LIGHT_DOME_DIRECTIONS):
            candidate_mask = ring_mask & (sector_indices == index)
            valid_mask = candidate_mask & finite_values
            candidate_count = int(np.count_nonzero(candidate_mask))
            sample_count = int(np.count_nonzero(valid_mask))
            coverage_ratio = sample_count / candidate_count if candidate_count else 0.0
            if sample_count == 0:
                median = p90 = maximum = peak_distance = None
            else:
                values = radiance[valid_mask]
                median, p90, maximum = self._summary(values)
                sector_distances = distances[valid_mask]
                peak_distance = float(sector_distances[int(np.argmax(values))])
            sectors.append(
                {
                    "direction": direction,
                    "azimuthCenterDegrees": azimuth,
                    "sampleCount": sample_count,
                    "coverageRatio": float(coverage_ratio),
                    "median": median,
                    "p90": p90,
                    "maximum": maximum,
                    "peakDistanceKm": peak_distance,
                }
            )
        usable = [sector for sector in sectors if sector["sampleCount"] > 0]
        dominant = (
            max(
                usable,
                key=lambda sector: (
                    float(sector["p90"]),
                    float(sector["maximum"]),
                    int(sector["sampleCount"]),
                ),
            )
            if usable
            else None
        )
        return {
            "innerRadiusKm": LIGHT_DOME_INNER_RADIUS_KM,
            "outerRadiusKm": LIGHT_DOME_OUTER_RADIUS_KM,
            "sectorCount": len(LIGHT_DOME_DIRECTIONS),
            "dominantDirection": dominant["direction"] if dominant else None,
            "dominantAzimuthDegrees": (
                dominant["azimuthCenterDegrees"] if dominant else None
            ),
            "sectors": sectors,
        }


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
    app = FastAPI(title="LumaNest Raster Service", version="1.2")
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
            spatial_analysis = active_sampler.spatial_analysis(latitude, longitude)
        except RasterioIOError as error:
            raise HTTPException(status_code=503, detail="viirs_unavailable") from error
        if sample is None:
            raise HTTPException(status_code=404, detail="viirs_sample_unavailable")
        if spatial_analysis is None:
            raise HTTPException(status_code=503, detail="viirs_analysis_unavailable")
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
            "spatialAnalysis": spatial_analysis,
            "sourceId": metadata.source_id,
            "attribution": metadata.attribution,
        }

    return app


app = create_app()
