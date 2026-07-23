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

EARTH_RADIUS_METERS = 6_371_008.8
AZIMUTH_STEP_DEGREES = 5
MAXIMUM_DISTANCE_KM = 40.0
OBSERVER_HEIGHT_METERS = 1.7
REFRACTION_COEFFICIENT = 0.13
MINIMUM_SAMPLE_SPACING_METERS = 60.0
MAXIMUM_SAMPLE_SPACING_METERS = 250.0
HORIZON_ALGORITHM_VERSION = "terrain-horizon-radial.1"


@dataclass(frozen=True)
class TerrainMetadata:
    source_id: str
    attribution: str
    dataset_revision: str
    resolution_meters: float


@dataclass(frozen=True)
class HorizonSample:
    azimuth_degrees: int
    horizon_altitude_degrees: float | None
    obstruction_distance_km: float | None
    obstruction_elevation_meters: float | None
    coverage_ratio: float


@dataclass(frozen=True)
class HorizonProfile:
    observer_elevation_meters: float
    observer_latitude: float
    observer_longitude: float
    sample_spacing_meters: float
    coverage_ratio: float
    samples: tuple[HorizonSample, ...]


class DemHorizonSampler:
    def __init__(self, path: str, metadata: TerrainMetadata) -> None:
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
                self._inspection = {"ready": False, "error": "dem_unconfigured"}
                return dict(self._inspection)
            try:
                dataset = self._open_unlocked()
                if dataset.count < 1:
                    raise RasterioIOError("DEM raster has no bands")
                if dataset.crs is None:
                    raise RasterioIOError("DEM raster has no CRS")
                if dataset.width < 1 or dataset.height < 1:
                    raise RasterioIOError("DEM raster has invalid dimensions")
                bounds = dataset.bounds
                if not all(math.isfinite(value) for value in bounds):
                    raise RasterioIOError("DEM raster has invalid bounds")
                if bounds.left >= bounds.right or bounds.bottom >= bounds.top:
                    raise RasterioIOError("DEM raster has empty bounds")
                dtype = np.dtype(dataset.dtypes[0])
                if not np.issubdtype(dtype, np.number):
                    raise RasterioIOError("DEM raster band is not numeric")
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
                    "error": str(error)[:240] or "dem_unavailable",
                }
            return dict(self._inspection)

    def health_snapshot(self, authentication_configured: bool) -> dict[str, object]:
        inspection = self.inspect()
        ready = bool(inspection.get("ready"))
        return {
            "status": "ok" if ready and authentication_configured else "degraded",
            "demConfigured": self.configured,
            "demReady": ready,
            "authenticationConfigured": authentication_configured,
            "error": inspection.get("error"),
            "dataset": {
                **asdict(self.metadata),
                **{key: value for key, value in inspection.items() if key not in {"ready", "error"}},
            }
            if ready
            else None,
            "algorithm": {
                "version": HORIZON_ALGORITHM_VERSION,
                "azimuthStepDegrees": AZIMUTH_STEP_DEGREES,
                "maximumDistanceKm": MAXIMUM_DISTANCE_KM,
                "observerHeightMeters": OBSERVER_HEIGHT_METERS,
                "refractionCoefficient": REFRACTION_COEFFICIENT,
            },
        }

    @staticmethod
    def _valid_elevation(value: object) -> float | None:
        if np.ma.is_masked(value):
            return None
        try:
            elevation = float(value)
        except (TypeError, ValueError):
            return None
        return elevation if math.isfinite(elevation) and -500 <= elevation <= 9_000 else None

    def horizon_profile(self, latitude: float, longitude: float) -> HorizonProfile | None:
        if not self.ready:
            return None
        with self._lock:
            dataset = self._open_unlocked()
            source_crs = CRS.from_epsg(4326)
            target_crs = dataset.crs
            observer_xs, observer_ys = transform(source_crs, target_crs, [longitude], [latitude])
            observer_x, observer_y = observer_xs[0], observer_ys[0]
            bounds = dataset.bounds
            if observer_x < bounds.left or observer_x >= bounds.right or observer_y < bounds.bottom or observer_y >= bounds.top:
                return None
            row, column = dataset.index(observer_x, observer_y)
            if row < 0 or row >= dataset.height or column < 0 or column >= dataset.width:
                return None
            observer_value = dataset.read(1, window=Window(column, row, 1, 1), masked=True)
            if observer_value.size != 1:
                return None
            observer_elevation = self._valid_elevation(observer_value[0, 0])
            if observer_elevation is None:
                return None
            center_x, center_y = dataset.xy(row, column, offset="center")
            observer_lons, observer_lats = transform(target_crs, source_crs, [center_x], [center_y])

            sample_spacing = max(MINIMUM_SAMPLE_SPACING_METERS, min(MAXIMUM_SAMPLE_SPACING_METERS, self.metadata.resolution_meters * 2))
            distances = np.arange(sample_spacing, MAXIMUM_DISTANCE_KM * 1_000 + sample_spacing * 0.5, sample_spacing, dtype="float64")
            azimuths = np.arange(0, 360, AZIMUTH_STEP_DEGREES, dtype="float64")
            bearings = np.deg2rad(np.repeat(azimuths, distances.size))
            radial_distances = np.tile(distances, azimuths.size)
            angular_distances = radial_distances / EARTH_RADIUS_METERS
            latitude_radians = math.radians(latitude)
            longitude_radians = math.radians(longitude)
            sin_latitude = math.sin(latitude_radians)
            cos_latitude = math.cos(latitude_radians)
            sin_angular = np.sin(angular_distances)
            cos_angular = np.cos(angular_distances)
            destination_latitudes = np.arcsin(sin_latitude * cos_angular + cos_latitude * sin_angular * np.cos(bearings))
            destination_longitudes = longitude_radians + np.arctan2(
                np.sin(bearings) * sin_angular * cos_latitude,
                cos_angular - sin_latitude * np.sin(destination_latitudes),
            )
            destination_latitude_degrees = np.rad2deg(destination_latitudes)
            destination_longitude_degrees = (np.rad2deg(destination_longitudes) + 540.0) % 360.0 - 180.0
            xs, ys = transform(source_crs, target_crs, destination_longitude_degrees.tolist(), destination_latitude_degrees.tolist())
            xs_array = np.asarray(xs, dtype="float64")
            ys_array = np.asarray(ys, dtype="float64")
            inside = (xs_array >= bounds.left) & (xs_array < bounds.right) & (ys_array >= bounds.bottom) & (ys_array < bounds.top)
            elevations = np.full(radial_distances.size, np.nan, dtype="float64")
            valid_indices = np.flatnonzero(inside)
            coordinates = zip(xs_array[valid_indices], ys_array[valid_indices])
            for index, sampled in zip(valid_indices, dataset.sample(coordinates, indexes=1, masked=True)):
                value = sampled[0] if sampled.size else None
                elevation = self._valid_elevation(value)
                if elevation is not None:
                    elevations[index] = elevation

            effective_radius = EARTH_RADIUS_METERS / (1.0 - REFRACTION_COEFFICIENT)
            curvature_drop = radial_distances * radial_distances / (2.0 * effective_radius)
            apparent_delta = elevations - (observer_elevation + OBSERVER_HEIGHT_METERS) - curvature_drop
            elevation_angles = np.rad2deg(np.arctan2(apparent_delta, radial_distances))

            samples: list[HorizonSample] = []
            total_valid = 0
            for azimuth_index, azimuth in enumerate(azimuths.astype(int)):
                start = azimuth_index * distances.size
                end = start + distances.size
                direction_elevations = elevations[start:end]
                valid = np.isfinite(direction_elevations)
                valid_count = int(np.count_nonzero(valid))
                total_valid += valid_count
                coverage_ratio = valid_count / distances.size
                if valid_count == 0:
                    samples.append(HorizonSample(int(azimuth), None, None, None, coverage_ratio))
                    continue
                direction_angles = elevation_angles[start:end].copy()
                direction_angles[~valid] = -np.inf
                maximum_index = int(np.argmax(direction_angles))
                samples.append(HorizonSample(
                    int(azimuth),
                    float(direction_angles[maximum_index]),
                    float(distances[maximum_index] / 1_000.0),
                    float(direction_elevations[maximum_index]),
                    coverage_ratio,
                ))
            overall_coverage = total_valid / (azimuths.size * distances.size)
            return HorizonProfile(
                observer_elevation,
                float(observer_lats[0]),
                float(observer_lons[0]),
                sample_spacing,
                overall_coverage,
                tuple(samples),
            )


def _float_environment(name: str, fallback: float, minimum: float, maximum: float) -> float:
    try:
        value = float(os.getenv(name, str(fallback)))
    except ValueError:
        return fallback
    if not math.isfinite(value):
        return fallback
    return min(maximum, max(minimum, value))


def _bounded_environment(name: str, fallback: str, maximum: int) -> str:
    return os.getenv(name, fallback).strip()[:maximum]


def _authorized(authorization: str | None, service_token: str) -> bool:
    return bool(service_token and authorization) and secrets.compare_digest(authorization, f"Bearer {service_token}")


def create_app(sampler: DemHorizonSampler | None = None, service_token: str | None = None) -> FastAPI:
    active_sampler = sampler or DemHorizonSampler(
        os.getenv("DEM_RASTER_PATH", ""),
        TerrainMetadata(
            source_id=_bounded_environment("DEM_SOURCE_ID", "copernicus-dem-glo30", 120),
            attribution=_bounded_environment("DEM_ATTRIBUTION", "Copernicus DEM GLO-30", 240),
            dataset_revision=_bounded_environment("DEM_DATASET_REVISION", "unversioned", 120),
            resolution_meters=_float_environment("DEM_RESOLUTION_METERS", 30.0, 1.0, 1_000.0),
        ),
    )
    active_service_token = service_token.strip() if service_token is not None else os.getenv("TERRAIN_SERVICE_TOKEN", "").strip()
    active_sampler.inspect()
    app = FastAPI(title="LumaNest Terrain Service", version="1.0")
    app.state.dem_sampler = active_sampler

    @app.on_event("shutdown")
    def close_sampler() -> None:
        active_sampler.close()

    @app.get("/healthz")
    def health() -> dict[str, object]:
        return active_sampler.health_snapshot(bool(active_service_token))

    @app.get("/v1/dem/horizon")
    def horizon(
        latitude: float = Query(ge=-90, le=90),
        longitude: float = Query(ge=-180, le=180),
        authorization: str | None = Header(default=None, alias="Authorization"),
    ) -> dict[str, object]:
        if not active_service_token:
            raise HTTPException(status_code=503, detail="terrain_auth_unconfigured")
        if not _authorized(authorization, active_service_token):
            raise HTTPException(status_code=401, detail="invalid_terrain_service_token", headers={"WWW-Authenticate": "Bearer"})
        inspection = active_sampler.inspect()
        if not active_sampler.configured:
            raise HTTPException(status_code=503, detail="dem_unconfigured")
        if not inspection.get("ready"):
            raise HTTPException(status_code=503, detail="dem_unavailable")
        try:
            profile = active_sampler.horizon_profile(latitude, longitude)
        except RasterioIOError as error:
            raise HTTPException(status_code=503, detail="dem_unavailable") from error
        if profile is None:
            raise HTTPException(status_code=404, detail="dem_horizon_unavailable")
        metadata = active_sampler.metadata
        return {
            "status": "ready",
            "algorithmVersion": HORIZON_ALGORITHM_VERSION,
            "datasetRevision": metadata.dataset_revision,
            "resolutionMeters": metadata.resolution_meters,
            "sourceId": metadata.source_id,
            "attribution": metadata.attribution,
            "observer": {
                "elevationMeters": profile.observer_elevation_meters,
                "sampledLatitude": profile.observer_latitude,
                "sampledLongitude": profile.observer_longitude,
                "heightMeters": OBSERVER_HEIGHT_METERS,
            },
            "azimuthStepDegrees": AZIMUTH_STEP_DEGREES,
            "maximumDistanceKm": MAXIMUM_DISTANCE_KM,
            "sampleSpacingMeters": profile.sample_spacing_meters,
            "refractionCoefficient": REFRACTION_COEFFICIENT,
            "coverageRatio": profile.coverage_ratio,
            "samples": [
                {
                    "azimuthDegrees": item.azimuth_degrees,
                    "horizonAltitudeDegrees": item.horizon_altitude_degrees,
                    "obstructionDistanceKm": item.obstruction_distance_km,
                    "obstructionElevationMeters": item.obstruction_elevation_meters,
                    "coverageRatio": item.coverage_ratio,
                }
                for item in profile.samples
            ],
        }

    return app


app = create_app()
