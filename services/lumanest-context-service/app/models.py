from __future__ import annotations

import math
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator, model_validator


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class SceneType(StrEnum):
    UNKNOWN = "unknown"
    CITY = "city"
    LAKE = "lake"
    MOUNTAIN = "mountain"
    DESERT = "desert"
    VILLAGE = "village"
    DRIVING = "driving"
    HIKING = "hiking"


class Coordinate(ApiModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    system: Literal["wgs84"] = "wgs84"


class SceneEvidence(ApiModel):
    urban: bool = False
    water_body: bool = Field(False, alias="waterBody")
    mountainous: bool = False
    arid_land: bool = Field(False, alias="aridLand")
    settlement: bool = False
    wildlife_opportunity: bool = Field(False, alias="wildlifeOpportunity")
    wildlife_safety: bool = Field(False, alias="wildlifeSafety")


class WeatherInput(ApiModel):
    observed_at: datetime = Field(alias="observedAt")
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=2000, alias="precipitationMm")
    visibility_km: float = Field(ge=0, le=500, alias="visibilityKm")
    thunder: bool = False
    stale: bool = False
    temperature_celsius: float | None = Field(None, ge=-100, le=100, alias="temperatureCelsius")
    wind_direction_degrees: float | None = Field(
        None, ge=0, lt=360, alias="windDirectionDegrees"
    )
    cloud_cover_percent: float | None = Field(None, ge=0, le=100, alias="cloudCoverPercent")


class SolarInput(ApiModel):
    day_phase: Literal["dawn", "day", "sunset", "blueHour", "night"] = Field(alias="dayPhase")
    elevation_degrees: float | None = Field(None, ge=-90, le=90, alias="elevationDegrees")
    azimuth_degrees: float | None = Field(None, ge=0, lt=360, alias="azimuthDegrees")


class RouteInput(ApiModel):
    mode: Literal["none", "driving", "hiking"] = "none"
    stage: Literal["none", "planned", "active", "paused"] = "none"

    @model_validator(mode="after")
    def enforce_mode_stage_invariant(self) -> "RouteInput":
        # ContextSnapshotV2 invariant: mode == "none" iff stage == "none".
        if (self.mode == "none") != (self.stage == "none"):
            raise ValueError("route mode must be none iff stage is none")
        return self


class WeatherForecastInput(ApiModel):
    observed_at: datetime = Field(alias="observedAt")
    next_hour_precipitation_mm: float = Field(
        ge=0, le=2000, alias="nextHourPrecipitationMm"
    )
    next_three_hours_max_wind_speed_mps: float | None = Field(
        None, ge=0, le=150, alias="nextThreeHoursMaxWindSpeedMps"
    )
    thunder_next_three_hours: bool = Field(False, alias="thunderNextThreeHours")

    @field_validator("observed_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("forecast observedAt must include a timezone")
        return value


class OfficialWarningInput(ApiModel):
    id: str = Field(pattern=r"^[a-f0-9]{12}$")
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    severity: Literal["info", "caution", "warning", "critical"]

    @field_validator("observed_at", "expires_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("warning timestamps must include a timezone")
        return value

    @model_validator(mode="after")
    def require_ordered_times(self) -> "OfficialWarningInput":
        if self.expires_at <= self.observed_at:
            raise ValueError("warning expiresAt must be later than observedAt")
        return self


class SnapshotRequest(ApiModel):
    contract_version: Literal[2] = Field(alias="contractVersion")
    coordinate: Coordinate
    observed_at: datetime = Field(alias="observedAt")
    locale: Literal["zh-CN", "en"] = "zh-CN"
    intent: Literal["photography", "food", "supplies", "fuel", "wildlife"] = "photography"
    route: RouteInput = RouteInput()
    evidence: SceneEvidence = SceneEvidence()
    weather: WeatherInput
    forecast: WeatherForecastInput
    official_warnings: list[OfficialWarningInput] = Field(
        default_factory=list, alias="officialWarnings", max_length=8
    )
    solar: SolarInput | None = None

    @field_validator("observed_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("observedAt must include a timezone")
        return value


class ContextEvent(ApiModel):
    id: str = Field(pattern=r"^[a-z0-9_-]{1,64}$")
    channel: Literal["opportunity", "safety", "wildlifeOpportunity", "wildlifeSafety"]
    source: Literal[
        "weather", "solar", "rule", "official", "wildlifeHistorical", "astronomyCatalog"
    ]
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    confidence: float = Field(ge=0, le=1)
    geo_scope: Literal["point", "regional", "route"] = Field(alias="geoScope")
    severity: Literal["info", "caution", "warning", "critical"] = "info"
    allowed_action: Literal[
        "openExplore", "openShootingWindow", "openWeather", "openSafety", "openRoute",
        "openAuthority",
    ] = Field(alias="allowedAction")
    title: str | None = Field(None, min_length=1, max_length=80)
    source_url: HttpUrl | None = Field(None, alias="sourceUrl", max_length=500)

    @model_validator(mode="after")
    def require_authority_metadata_only_for_authority_action(self) -> "ContextEvent":
        if self.allowed_action == "openAuthority":
            if self.source != "astronomyCatalog" or self.title is None or self.source_url is None:
                raise ValueError("authority actions require catalog title and URL")
        elif self.source_url is not None:
            raise ValueError("sourceUrl is only allowed for authority actions")
        return self


class Manifest(ApiModel):
    layout_mode: Literal["quiet", "opportunity", "safety"] = Field(alias="layoutMode")
    primary_event_id: str | None = Field(None, alias="primaryEventId")
    secondary_event_ids: list[str] = Field(default_factory=list, alias="secondaryEventIds", max_length=2)
    safety_event_ids: list[str] = Field(default_factory=list, alias="safetyEventIds")


class DataFreshness(ApiModel):
    context: Literal["fresh", "stale"]
    weather: Literal["fresh", "stale"]
    weather_observed_at: datetime = Field(alias="weatherObservedAt")


class WeatherState(ApiModel):
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    temperature_celsius: float | None = Field(None, alias="temperatureCelsius")
    wind_speed_mps: float = Field(alias="windSpeedMps")
    wind_direction_degrees: float | None = Field(None, alias="windDirectionDegrees")
    precipitation_mm: float = Field(alias="precipitationMm")
    visibility_km: float = Field(alias="visibilityKm")
    cloud_cover_percent: float | None = Field(None, alias="cloudCoverPercent")
    thunder: bool


class SunMoonState(ApiModel):
    day_phase: Literal["dawn", "day", "sunset", "blueHour", "night"] = Field(alias="dayPhase")
    sun_elevation_degrees: float | None = Field(None, alias="sunElevationDegrees")
    sun_azimuth_degrees: float | None = Field(None, alias="sunAzimuthDegrees")
    moon_phase: Literal[
        "newMoon",
        "waxingCrescent",
        "firstQuarter",
        "waxingGibbous",
        "fullMoon",
        "waningGibbous",
        "lastQuarter",
        "waningCrescent",
    ] = Field(alias="moonPhase")
    moon_illumination: float = Field(ge=0, le=1, alias="moonIllumination")


class RouteState(ApiModel):
    mode: Literal["none", "driving", "hiking"]
    stage: Literal["none", "planned", "active", "paused"]
    active: bool

    @model_validator(mode="after")
    def enforce_mode_stage_active_invariant(self) -> "RouteState":
        # ContextSnapshotV2 invariant: mode == "none" iff stage == "none",
        # and active must be true iff stage == "active".
        if (self.mode == "none") != (self.stage == "none"):
            raise ValueError("route mode must be none iff stage is none")
        if self.active != (self.stage == "active"):
            raise ValueError("route active must be true iff stage is active")
        return self


class SnapshotResponse(ApiModel):
    contract_version: Literal[2] = Field(2, alias="contractVersion")
    context_id: str = Field(alias="contextId")
    generated_at: datetime = Field(alias="generatedAt")
    expires_at: datetime = Field(alias="expiresAt")
    scene: SceneType
    fingerprint: str
    stale: bool
    data_freshness: DataFreshness = Field(alias="dataFreshness")
    weather: WeatherState
    sun_moon: SunMoonState = Field(alias="sunMoon")
    route: RouteState
    events: list[ContextEvent]
    allowed_actions: list[
        Literal[
            "openExplore", "openShootingWindow", "openWeather", "openSafety", "openRoute",
            "openAuthority",
        ]
    ] = Field(alias="allowedActions")
    manifest: Manifest


class SourceStatus(ApiModel):
    id: str
    dataset_type: Literal["unknown", "spatialFeatures", "astronomyEvents"] = Field(
        alias="datasetType"
    )
    enabled: bool
    license_status: Literal["approved", "pending", "disabled"] = Field(alias="licenseStatus")
    attribution: str
    version: str
    updated_at: datetime | None = Field(None, alias="updatedAt")


class ImportSource(ApiModel):
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9_-]{0,63}$")
    enabled: bool = False
    license_status: Literal["approved", "pending", "disabled"] = Field(alias="licenseStatus")
    attribution: str = Field(min_length=1, max_length=500)
    version: str = Field(min_length=1, max_length=100)
    category: Literal["spatial", "wildlifeHistorical", "officialRisk"] = "spatial"

    @field_validator("attribution", "version")
    @classmethod
    def require_visible_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("source metadata must not be blank")
        return value

    @model_validator(mode="after")
    def require_approved_license_when_enabled(self) -> "ImportSource":
        if self.enabled and self.license_status != "approved":
            raise ValueError("enabled sources require an approved license")
        return self


class SpatialFeatureProperties(ApiModel):
    kind: Literal["urban", "water", "mountain", "arid", "settlement", "protected", "risk"]
    name: str = Field(min_length=1, max_length=200)
    sensitivity: Literal["public", "sensitive"] = "public"
    evidence_class: Literal["scene", "wildlifeOpportunity", "wildlifeSafety"] = Field(
        "scene", alias="evidenceClass"
    )


class GeoJsonGeometry(ApiModel):
    type: Literal["Point", "Polygon", "MultiPolygon"]
    coordinates: list[object]

    @model_validator(mode="after")
    def validate_coordinates(self) -> "GeoJsonGeometry":
        def position(value: object) -> bool:
            return (
                isinstance(value, list)
                and len(value) >= 2
                and all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in value[:2])
                and all(math.isfinite(float(item)) for item in value[:2])
                and -180 <= float(value[0]) <= 180
                and -90 <= float(value[1]) <= 90
            )

        def ring(value: object) -> bool:
            return (
                isinstance(value, list)
                and len(value) >= 4
                and all(position(item) for item in value)
                and value[0][:2] == value[-1][:2]
            )

        valid = False
        if self.type == "Point":
            valid = position(self.coordinates)
        elif self.type == "Polygon":
            valid = bool(self.coordinates) and all(ring(item) for item in self.coordinates)
        elif self.type == "MultiPolygon":
            valid = bool(self.coordinates) and all(
                isinstance(polygon, list) and bool(polygon) and all(ring(item) for item in polygon)
                for polygon in self.coordinates
            )
        if not valid:
            raise ValueError("invalid GeoJSON coordinates")
        return self


class WildlifeLayerSource(ApiModel):
    attribution: str = Field(min_length=1, max_length=500)
    version: str = Field(min_length=1, max_length=100)
    updated_at: datetime | None = Field(None, alias="updatedAt")


class WildlifeLayerArea(ApiModel):
    id: str = Field(pattern=r"^[a-f0-9]{64}$")
    name: str = Field(min_length=1, max_length=200)
    geometry: GeoJsonGeometry
    source: WildlifeLayerSource

    @model_validator(mode="after")
    def require_area_geometry(self) -> "WildlifeLayerArea":
        if self.geometry.type not in ("Polygon", "MultiPolygon"):
            raise ValueError("wildlife layers require polygon geometry")
        return self


class WildlifeLayerResponse(ApiModel):
    contract_version: Literal[1] = Field(1, alias="contractVersion")
    generated_at: datetime = Field(alias="generatedAt")
    radius_km: int = Field(ge=5, le=50, alias="radiusKm")
    areas: list[WildlifeLayerArea] = Field(max_length=50)


class GeoJsonFeature(ApiModel):
    type: Literal["Feature"]
    id: str = Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$")
    geometry: GeoJsonGeometry
    properties: SpatialFeatureProperties

    @model_validator(mode="after")
    def prevent_exact_sensitive_points(self) -> "GeoJsonFeature":
        if self.properties.sensitivity == "sensitive":
            if self.geometry.type == "Point":
                raise ValueError("sensitive features must use a coarse polygon")

            positions: list[list[float]] = []

            def collect(value: object) -> None:
                if (
                    isinstance(value, list)
                    and len(value) >= 2
                    and all(isinstance(item, (int, float)) for item in value[:2])
                ):
                    positions.append([float(value[0]), float(value[1])])
                    return
                if isinstance(value, list):
                    for item in value:
                        collect(item)

            collect(self.geometry.coordinates)
            longitude_span = max(item[0] for item in positions) - min(item[0] for item in positions)
            latitude_span = max(item[1] for item in positions) - min(item[1] for item in positions)
            if longitude_span < 0.01 or latitude_span < 0.01:
                raise ValueError("sensitive feature polygon is too precise")
        return self


class GeoJsonFeatureCollection(ApiModel):
    type: Literal["FeatureCollection"]
    features: list[GeoJsonFeature] = Field(max_length=500)

    @model_validator(mode="after")
    def require_unique_feature_ids(self) -> "GeoJsonFeatureCollection":
        ids = [feature.id for feature in self.features]
        if len(ids) != len(set(ids)):
            raise ValueError("feature IDs must be unique within a source")
        return self


class SpatialFeaturesImport(ApiModel):
    dataset_type: Literal["spatialFeatures"] = Field(alias="datasetType")
    source: ImportSource
    feature_collection: GeoJsonFeatureCollection = Field(alias="featureCollection")

    @model_validator(mode="after")
    def require_traceable_wildlife_sources(self) -> "SpatialFeaturesImport":
        for feature in self.feature_collection.features:
            evidence = feature.properties.evidence_class
            if evidence == "scene" and self.source.category != "spatial":
                raise ValueError("scene features require a spatial source")
            if evidence == "wildlifeOpportunity":
                if self.source.category != "wildlifeHistorical":
                    raise ValueError("wildlife opportunities require a historical wildlife source")
                if feature.properties.kind != "protected":
                    raise ValueError("wildlife opportunities require a reviewed observation area")
            if evidence == "wildlifeSafety":
                if self.source.category != "officialRisk":
                    raise ValueError("wildlife safety requires an official risk source")
                if feature.properties.kind != "risk":
                    raise ValueError("wildlife safety requires a risk area")
        return self


class AstronomyEventImport(ApiModel):
    id: str = Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$")
    event_type: Literal["solarEclipse", "lunarEclipse", "meteorShower", "comet"] = Field(
        alias="eventType"
    )
    starts_at: datetime = Field(alias="startsAt")
    ends_at: datetime = Field(alias="endsAt")
    title: str = Field(min_length=1, max_length=200)
    source_url: HttpUrl = Field(alias="sourceUrl", max_length=500)

    @model_validator(mode="after")
    def validate_event(self) -> "AstronomyEventImport":
        if self.starts_at.tzinfo is None or self.ends_at.tzinfo is None:
            raise ValueError("astronomy event timestamps require timezones")
        if self.ends_at <= self.starts_at:
            raise ValueError("astronomy event must end after it starts")
        if self.source_url.scheme != "https":
            raise ValueError("astronomy sourceUrl must use https")
        return self


class AstronomyEventsImport(ApiModel):
    dataset_type: Literal["astronomyEvents"] = Field(alias="datasetType")
    source: ImportSource
    events: list[AstronomyEventImport] = Field(max_length=500)

    @model_validator(mode="after")
    def require_unique_event_ids(self) -> "AstronomyEventsImport":
        ids = [event.id for event in self.events]
        if len(ids) != len(set(ids)):
            raise ValueError("event IDs must be unique within a source")
        return self


ContextImportRequest = Annotated[
    SpatialFeaturesImport | AstronomyEventsImport,
    Field(discriminator="dataset_type"),
]


class ContextImportResult(ApiModel):
    source_id: str = Field(alias="sourceId")
    dataset_type: Literal["spatialFeatures", "astronomyEvents"] = Field(alias="datasetType")
    imported_count: int = Field(ge=0, alias="importedCount")
    enabled: bool
    cache_invalidated: bool = Field(alias="cacheInvalidated")
