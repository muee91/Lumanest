from __future__ import annotations

import math
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    HttpUrl,
    field_validator,
    model_validator,
)


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class SceneType(StrEnum):
    UNKNOWN = "unknown"
    CITY = "city"
    LAKE = "lake"
    MOUNTAIN = "mountain"
    DESERT = "desert"
    VILLAGE = "village"


class PrimaryScene(StrEnum):
    UNKNOWN = "unknown"
    URBAN = "urban"
    VILLAGE = "village"
    MOUNTAIN = "mountain"
    PLATEAU = "plateau"
    DESERT = "desert"
    FOREST = "forest"
    INLAND_WATER = "inlandWater"
    COAST = "coast"
    WETLAND = "wetland"


class SceneFacet(StrEnum):
    LAKE = "lake"
    RIVER = "river"
    RESERVOIR = "reservoir"
    WETLAND = "wetland"
    COAST = "coast"
    TIDAL_FLAT = "tidalFlat"
    WATERFALL = "waterfall"
    SNOW_COVER = "snowCover"
    GLACIER = "glacier"
    CANYON = "canyon"
    DUNE = "dune"
    GRASSLAND = "grassland"
    FOREST = "forest"
    BAMBOO_FOREST = "bambooForest"
    SKYLINE = "skyline"
    ARCHITECTURE = "architecture"
    OLD_TOWN = "oldTown"
    VILLAGE_STREET = "villageStreet"
    OPEN_ROAD = "openRoad"
    OPEN_HORIZON = "openHorizon"
    DARK_SKY = "darkSky"
    REVIEWED_PEAK = "reviewedPeak"
    REVIEWED_VIEWPOINT = "reviewedViewpoint"
    REFLECTIVE_SURFACE = "reflectiveSurface"


class ActivityState(StrEnum):
    STATIONARY = "stationary"
    WALKING = "walking"
    HIKING = "hiking"
    DRIVING = "driving"


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
    plateau: bool = False
    forest: bool = False
    coast: bool = False
    wetland: bool = False
    scene_facets: list[SceneFacet] = Field(
        default_factory=list, max_length=24, alias="sceneFacets"
    )
    reviewed_primary_scene: PrimaryScene | None = Field(
        None, alias="reviewedPrimaryScene"
    )


class CompositeSceneContext(ApiModel):
    primary_scene: PrimaryScene = Field(alias="primaryScene")
    facets: list[SceneFacet] = Field(max_length=24)
    activity: ActivityState
    scores: dict[PrimaryScene, int]
    reviewed_override: bool = Field(False, alias="reviewedOverride")


class WeatherInput(ApiModel):
    observed_at: datetime = Field(alias="observedAt")
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=2000, alias="precipitationMm")
    visibility_km: float = Field(ge=0, le=500, alias="visibilityKm")
    thunder: bool = False
    stale: bool = False
    temperature_celsius: float | None = Field(
        None, ge=-100, le=100, alias="temperatureCelsius"
    )
    wind_direction_degrees: float | None = Field(
        None, ge=0, lt=360, alias="windDirectionDegrees"
    )
    cloud_cover_percent: float | None = Field(
        None, ge=0, le=100, alias="cloudCoverPercent"
    )
    air_quality_index: int | None = Field(None, ge=0, le=500, alias="airQualityIndex")
    air_quality_category: str | None = Field(
        None, min_length=1, max_length=40, alias="airQualityCategory"
    )
    primary_pollutant: str | None = Field(
        None, min_length=1, max_length=40, alias="primaryPollutant"
    )
    air_quality_observed_at: datetime | None = Field(None, alias="airQualityObservedAt")
    air_quality_stale: bool = Field(True, alias="airQualityStale")

    @model_validator(mode="after")
    def require_complete_air_quality(self) -> "WeatherInput":
        if self.air_quality_index is None:
            if any(
                (
                    self.air_quality_category,
                    self.primary_pollutant,
                    self.air_quality_observed_at,
                )
            ):
                raise ValueError("air quality metadata requires an AQI")
            return self
        if (
            self.air_quality_observed_at is None
            or self.air_quality_observed_at.tzinfo is None
        ):
            raise ValueError("AQI requires a timezone-aware observation time")
        return self


class SolarInput(ApiModel):
    day_phase: Literal["dawn", "day", "sunset", "blueHour", "night"] = Field(
        alias="dayPhase"
    )
    elevation_degrees: float | None = Field(
        None, ge=-90, le=90, alias="elevationDegrees"
    )
    azimuth_degrees: float | None = Field(None, ge=0, lt=360, alias="azimuthDegrees")


class RouteCorridorSample(ApiModel):
    """A transient point supplied by the client route planner.

    It is deliberately bounded and has no persistence model.  The server uses
    it only while evaluating this request to align an existing hourly forecast
    and deterministic solar position with an estimated arrival time.
    """

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    system: Literal["wgs84"] = "wgs84"
    expected_at: datetime = Field(alias="expectedAt")
    progress: float = Field(ge=0, le=1)

    @field_validator("expected_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("corridor expectedAt must include a timezone")
        return value


class RouteInput(ApiModel):
    mode: Literal["none", "driving", "hiking"] = "none"
    stage: Literal["none", "planned", "active", "paused"] = "none"
    route_id: str | None = Field(
        None, alias="routeId", pattern=r"^[A-Za-z0-9_-]{1,160}$"
    )
    corridor_samples: list[RouteCorridorSample] = Field(
        default_factory=list, max_length=3, alias="corridorSamples"
    )

    @model_validator(mode="after")
    def enforce_mode_stage_invariant(self) -> "RouteInput":
        # Current snapshot invariant: mode == "none" iff stage == "none".
        if (self.mode == "none") != (self.stage == "none"):
            raise ValueError("route mode must be none iff stage is none")
        if self.mode == "none" and (self.route_id is not None or self.corridor_samples):
            raise ValueError("route corridor requires a route")
        if self.corridor_samples and self.route_id is None:
            raise ValueError("corridor samples require an opaque routeId")
        if self.corridor_samples:
            progress = [item.progress for item in self.corridor_samples]
            moments = [item.expected_at for item in self.corridor_samples]
            if progress != sorted(progress) or moments != sorted(moments):
                raise ValueError(
                    "corridor samples must be ordered by progress and expectedAt"
                )
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
    # The current contract needs enough coverage to reach the next local evening even when the
    # app is opened early in the day. Older contracts remain valid with fewer
    # samples.
    hourly: list["HourlyForecastInput"] = Field(default_factory=list, max_length=24)

    @field_validator("observed_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("forecast observedAt must include a timezone")
        return value


class HourlyForecastInput(ApiModel):
    at: datetime
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    cloud_cover_percent: float | None = Field(
        None, ge=0, le=100, alias="cloudCoverPercent"
    )
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=2000, alias="precipitationMm")
    visibility_km: float | None = Field(None, ge=0, le=500, alias="visibilityKm")
    thunder: bool = False

    @field_validator("at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("hourly forecast at must include a timezone")
        return value


class OfficialWarningInput(ApiModel):
    id: str = Field(pattern=r"^[a-f0-9]{12}$")
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    severity: Literal["info", "caution", "warning", "critical"]
    title: str = Field(min_length=1, max_length=80)

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
    contract_version: Literal[5] = Field(alias="contractVersion")
    coordinate: Coordinate
    observed_at: datetime = Field(alias="observedAt")
    locale: Literal["zh-CN", "en"] = "zh-CN"
    intent: Literal["photography", "food", "supplies", "fuel", "wildlife"] = (
        "photography"
    )
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
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9._-]{0,95}$")
    channel: Literal["opportunity", "safety", "wildlifeOpportunity", "wildlifeSafety"]
    source: Literal[
        "weather", "solar", "rule", "official", "wildlifeHistorical", "astronomyCatalog"
    ]
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    confidence: float = Field(ge=0, le=1)
    geo_scope: Literal["point", "region", "route"] = Field(alias="geoScope")
    severity: Literal["info", "caution", "warning", "critical"] = "info"
    allowed_action: Literal[
        "openShootingWindow",
        "openExplore",
        "openRoute",
        "openPlaceDetail",
        "openAstronomyDetail",
        "openWildlifeDetail",
        "openSafetyDetail",
        "openCreativeDetail",
        "dismiss",
    ] = Field(alias="allowedAction")
    title: str | None = Field(None, min_length=1, max_length=80)
    source_url: HttpUrl | None = Field(None, alias="sourceUrl", max_length=500)

    @model_validator(mode="after")
    def require_authority_metadata_only_for_authority_action(self) -> "ContextEvent":
        if self.source == "astronomyCatalog":
            if (
                self.allowed_action != "openAstronomyDetail"
                or self.title is None
                or self.source_url is None
            ):
                raise ValueError(
                    "astronomy catalog events require title, URL and astronomy action"
                )
        elif self.source_url is not None:
            raise ValueError("sourceUrl is only allowed for astronomy catalog events")
        return self


class Manifest(ApiModel):
    layout_mode: Literal["quiet", "opportunity", "safety"] = Field(alias="layoutMode")
    primary_event_id: str | None = Field(None, alias="primaryEventId")
    secondary_event_ids: list[str] = Field(
        default_factory=list, alias="secondaryEventIds", max_length=2
    )
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
    air_quality_index: int | None = Field(None, ge=0, le=500, alias="airQualityIndex")
    air_quality_category: str | None = Field(
        None, min_length=1, max_length=40, alias="airQualityCategory"
    )
    primary_pollutant: str | None = Field(
        None, min_length=1, max_length=40, alias="primaryPollutant"
    )
    air_quality_observed_at: datetime | None = Field(None, alias="airQualityObservedAt")
    air_quality_stale: bool = Field(True, alias="airQualityStale")


class SunMoonState(ApiModel):
    day_phase: Literal["dawn", "day", "sunset", "blueHour", "night"] = Field(
        alias="dayPhase"
    )
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
        # Current snapshot invariant: mode == "none" iff stage == "none",
        # and active must be true iff stage == "active".
        if (self.mode == "none") != (self.stage == "none"):
            raise ValueError("route mode must be none iff stage is none")
        if self.active != (self.stage == "active"):
            raise ValueError("route active must be true iff stage is active")
        return self


class SnapshotResponse(ApiModel):
    contract_version: Literal[5] = Field(5, alias="contractVersion")
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
            "openShootingWindow",
            "openExplore",
            "openRoute",
            "openPlaceDetail",
            "openAstronomyDetail",
            "openWildlifeDetail",
            "openSafetyDetail",
            "openCreativeDetail",
            "dismiss",
        ]
    ] = Field(alias="allowedActions")
    manifest: Manifest
    scene_context: CompositeSceneContext = Field(alias="sceneContext")
    opportunity_catalog_version: Literal[1] = Field(
        1, alias="opportunityCatalogVersion"
    )
    shooting_sessions: list["ShootingSession"] = Field(
        default_factory=list, max_length=2, alias="shootingSessions"
    )


class V5EntryAction(ApiModel):
    type: Literal[
        "openShootingWindow",
        "openExplore",
        "openRoute",
        "openPlaceDetail",
        "openAstronomyDetail",
        "openWildlifeDetail",
        "openSafetyDetail",
        "openCreativeDetail",
        "dismiss",
    ]
    target_id: str | None = Field(None, alias="targetId")
    query: str | None = None


class V5EntryPayload(ApiModel):
    type: Literal["safety", "opportunity", "system"]
    event_id: str | None = Field(None, alias="eventId")
    definition_id: str | None = Field(None, alias="definitionId")
    instance_id: str | None = Field(None, alias="instanceId")
    session_id: str | None = Field(None, alias="sessionId")


class V5EntryPresentation(ApiModel):
    variant: Literal[
        "safety",
        "shootingSession",
        "skyOpportunity",
        "manifestOpportunity",
        "quiet",
    ]
    title: str = Field(min_length=1, max_length=120)
    short_label: str | None = Field(None, alias="shortLabel")
    fallback_summary: str | None = Field(None, alias="fallbackSummary")


class V5EntryProvenance(ApiModel):
    source_id: str = Field(alias="sourceId", min_length=1, max_length=120)
    observed_at: datetime = Field(alias="observedAt")
    source_url: HttpUrl | None = Field(None, alias="sourceUrl")


class V5ContextEntry(ApiModel):
    id: str = Field(pattern=r"^entry_[a-zA-Z0-9_-]{1,120}$")
    kind: Literal[
        "safety",
        "photographyOpportunity",
        "place",
        "route",
        "astronomy",
        "inspiration",
        "system",
    ]
    source_namespace: str = Field(alias="sourceNamespace", min_length=1, max_length=80)
    source_id: str = Field(alias="sourceId", min_length=1, max_length=160)
    revision: int = Field(ge=1)
    observed_at: datetime = Field(alias="observedAt")
    valid_from: datetime = Field(alias="validFrom")
    expires_at: datetime = Field(alias="expiresAt")
    freshness: Literal["fresh", "stale", "expired"]
    evidence_confidence: float = Field(alias="evidenceConfidence", ge=0, le=1)
    base_priority: Literal["p0", "p1", "p2", "p3"] = Field(alias="basePriority")
    severity: Literal["info", "caution", "warning", "critical"]
    geo_scope: Literal["point", "region", "route"] = Field(alias="geoScope")
    allowed_surfaces: list[
        Literal[
            "today",
            "explore",
            "route",
            "inspiration",
            "profile",
            "shootingWindow",
            "widget",
            "notification",
        ]
    ] = Field(alias="allowedSurfaces", min_length=1)
    actions: list[V5EntryAction] = Field(min_length=1, max_length=3)
    presentation: V5EntryPresentation
    payload: V5EntryPayload
    provenance: list[V5EntryProvenance] = Field(min_length=1, max_length=8)
    dedupe_key: str = Field(alias="dedupeKey", min_length=1, max_length=200)
    suppression_keys: list[str] = Field(
        default_factory=list, alias="suppressionKeys", max_length=8
    )
    content_fingerprint: str = Field(
        alias="contentFingerprint", pattern=r"^sha256:[a-f0-9]{64}$"
    )


class V5Environment(ApiModel):
    scene: SceneType
    data_freshness: DataFreshness = Field(alias="dataFreshness")
    weather: WeatherState
    sun_moon: SunMoonState = Field(alias="sunMoon")
    route: RouteState
    scene_context: CompositeSceneContext = Field(alias="sceneContext")
    allowed_actions: list[
        Literal[
            "openShootingWindow",
            "openExplore",
            "openRoute",
            "openPlaceDetail",
            "openAstronomyDetail",
            "openWildlifeDetail",
            "openSafetyDetail",
            "openCreativeDetail",
            "dismiss",
        ]
    ] = Field(alias="allowedActions")


class V5Facts(ApiModel):
    events: list[ContextEvent]
    shooting_sessions: list["ShootingSession"] = Field(
        default_factory=list, max_length=2, alias="shootingSessions"
    )


class V5SnapshotResponse(ApiModel):
    contract_version: Literal[5] = Field(5, alias="contractVersion")
    context_id: str = Field(alias="contextId")
    snapshot_revision: int = Field(alias="snapshotRevision", ge=1)
    generated_at: datetime = Field(alias="generatedAt")
    expires_at: datetime = Field(alias="expiresAt")
    source_revisions: dict[str, int] = Field(alias="sourceRevisions")
    stale: bool
    environment: V5Environment
    facts: V5Facts
    entries: list[V5ContextEntry] = Field(max_length=64)
    refresh_hints: dict[str, str] = Field(alias="refreshHints")


class PhotographyTarget(ApiModel):
    """A reviewed, public, static place a creative opportunity may point to.

    This is deliberately not a user place, a route waypoint, or a live location
    record.  It is emitted only from an explicitly marked public source feature.
    """

    id: str = Field(pattern=r"^target_[a-f0-9]{24}$")
    name: str = Field(min_length=1, max_length=200)
    kind: Literal["viewpoint", "lakeshore", "trailhead", "urban"]
    coordinate: Coordinate
    arrival_deadline: datetime = Field(alias="arrivalDeadline")

    @field_validator("arrival_deadline")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("target arrivalDeadline must include a timezone")
        return value


class ShootingTarget(ApiModel):
    """A reviewed target that is eligible for a current shooting session."""

    id: str = Field(pattern=r"^target_[a-f0-9]{24}$")
    name: str = Field(min_length=1, max_length=200)
    kind: Literal["lakeshore"] = "lakeshore"
    coordinate: Coordinate
    supported_sessions: list[Literal["waterMorning", "waterEvening"]] = Field(
        min_length=1, max_length=2, alias="supportedSessions"
    )
    view_bearing_degrees: float = Field(ge=0, lt=360, alias="viewBearingDegrees")
    bearing_tolerance_degrees: float = Field(
        ge=5, le=90, alias="bearingToleranceDegrees"
    )
    access_modes: list[Literal["driving", "walking"]] = Field(
        min_length=1, max_length=2, alias="accessModes"
    )
    lead_time_minutes: int = Field(ge=0, le=180, alias="leadTimeMinutes")
    arrival_radius_meters: int = Field(ge=25, le=1000, alias="arrivalRadiusMeters")
    shoreline_side: Literal[
        "north",
        "northeast",
        "east",
        "southeast",
        "south",
        "southwest",
        "west",
        "northwest",
    ] = Field(alias="shorelineSide")
    reviewed_at: datetime = Field(alias="reviewedAt")
    review_reference: HttpUrl = Field(alias="reviewReference", max_length=500)
    source_attribution: str = Field(
        min_length=1, max_length=500, alias="sourceAttribution"
    )
    source_license: str = Field(min_length=1, max_length=100, alias="sourceLicense")
    source_url: HttpUrl = Field(alias="sourceUrl", max_length=500)

    @field_validator("reviewed_at")
    @classmethod
    def require_review_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("target reviewedAt must include a timezone")
        return value


class ShootingTargetResolveRequest(ApiModel):
    """Resolve one public reviewed target without accepting a user location."""

    target_id: str = Field(alias="targetId", pattern=r"^target_[a-f0-9]{24}$")
    coordinate: Coordinate


class ShootingFeedbackFactor(ApiModel):
    id: Literal["cloud", "wind", "precipitation", "visibility", "dataCoverage"]
    effect: Literal["supporting", "neutral", "limiting"]


class ShootingSessionFeedbackRequest(ApiModel):
    """Anonymous, bounded feedback. Deliberately has no identity or media fields."""

    contract_version: Literal[2] = Field(2, alias="contractVersion")
    rule_version: str = Field(pattern=r"^[a-z0-9._-]{1,32}$", alias="ruleVersion")
    condition_band: Literal["good", "fair", "limited"] = Field(alias="conditionBand")
    factors: list[ShootingFeedbackFactor] = Field(min_length=1, max_length=8)
    outcome: Literal["captured", "conditionsDidNotAppear", "arrivedLate", "didNotGo"]
    reasons: list[Literal["wind", "cloud", "precipitation", "target"]] = Field(
        default_factory=list, max_length=4
    )
    target_id: str | None = Field(
        None, alias="targetId", pattern=r"^target_[a-f0-9]{24}$"
    )

    @field_validator("factors")
    @classmethod
    def require_unique_factors(
        cls, value: list[ShootingFeedbackFactor]
    ) -> list[ShootingFeedbackFactor]:
        if len({item.id for item in value}) != len(value):
            raise ValueError("feedback factors must be unique")
        return value

    @field_validator("reasons")
    @classmethod
    def require_unique_reasons(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("feedback reasons must be unique")
        return value


class ShootingSessionFeedbackReceipt(ApiModel):
    accepted: Literal[True] = True


class ShootingFeedbackCalibrationRow(ApiModel):
    rule_version: str = Field(alias="ruleVersion")
    condition_band: Literal["good", "fair", "limited"] = Field(alias="conditionBand")
    factor_id: Literal[
        "cloud", "wind", "precipitation", "visibility", "dataCoverage"
    ] = Field(alias="factorId")
    factor_effect: Literal["supporting", "neutral", "limiting"] = Field(
        alias="factorEffect"
    )
    evaluated_count: int = Field(ge=1, alias="evaluatedCount")
    captured_count: int = Field(ge=0, alias="capturedCount")
    conditions_did_not_appear_count: int = Field(
        ge=0, alias="conditionsDidNotAppearCount"
    )
    captured_rate: float = Field(ge=0, le=1, alias="capturedRate")


class ShootingFeedbackCalibrationResponse(ApiModel):
    generated_at: datetime = Field(alias="generatedAt")
    since: datetime
    minimum_samples: int = Field(ge=5, le=100, alias="minimumSamples")
    rows: list[ShootingFeedbackCalibrationRow] = Field(max_length=500)


class ShootingSessionFactor(ApiModel):
    id: Literal["cloud", "wind", "precipitation", "visibility", "dataCoverage"]
    effect: Literal["supporting", "neutral", "limiting"]
    label: str = Field(min_length=1, max_length=40)
    value: str = Field(min_length=1, max_length=80)
    source_at: datetime = Field(alias="sourceAt")


class ShootingSessionTrendSample(ApiModel):
    at: datetime
    condition_index: int = Field(ge=0, le=100, alias="conditionIndex")
    cloud_cover_percent: float | None = Field(
        None, ge=0, le=100, alias="cloudCoverPercent"
    )
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=2000, alias="precipitationMm")


class ShootingSessionPhase(ApiModel):
    kind: Literal[
        "morningBlueHour",
        "sunrise",
        "morningMist",
        "reflection",
        "warmLight",
        "sunset",
        "blueHour",
        "artificialLights",
        "rainEnding",
        "wetReflection",
        "desertSideLight",
        "texture",
        "approach",
        "safeStop",
        "shoot",
        "rejoinRoute",
        "returnWindow",
        "sessionEnd",
    ]
    start_at: datetime = Field(alias="startAt")
    peak_at: datetime = Field(alias="peakAt")
    end_at: datetime = Field(alias="endAt")
    condition_band: Literal["good", "fair", "limited"] = Field(alias="conditionBand")
    direction_degrees: float = Field(ge=0, lt=360, alias="directionDegrees")

    @model_validator(mode="after")
    def require_ordered_phase(self) -> "ShootingSessionPhase":
        if not self.start_at <= self.peak_at <= self.end_at:
            raise ValueError("shooting session phase must be ordered")
        return self


class ShootingSession(ApiModel):
    id: str = Field(pattern=r"^session_[a-f0-9]{24}$")
    kind: Literal[
        "generalMorning",
        "generalEvening",
        "waterMorning",
        "waterEvening",
        "mountainMorning",
        "mountainEvening",
        "cityBlueHour",
        "cityAfterRain",
        "desertSideLight",
        "routeLightWindow",
    ]
    title: str = Field(min_length=1, max_length=80)
    start_at: datetime = Field(alias="startAt")
    end_at: datetime = Field(alias="endAt")
    primary_phase: Literal[
        "morningBlueHour",
        "sunrise",
        "morningMist",
        "reflection",
        "warmLight",
        "sunset",
        "blueHour",
        "artificialLights",
        "rainEnding",
        "wetReflection",
        "desertSideLight",
        "texture",
        "approach",
        "safeStop",
        "shoot",
        "rejoinRoute",
        "returnWindow",
        "sessionEnd",
    ] = Field(alias="primaryPhase")
    condition_band: Literal["good", "fair", "limited"] = Field(alias="conditionBand")
    confidence_band: Literal["high", "medium", "limited"] = Field(
        alias="confidenceBand"
    )
    trend: Literal["improving", "stable", "weakening"]
    phases: list[ShootingSessionPhase] = Field(min_length=1, max_length=5)
    factors: list[ShootingSessionFactor] = Field(min_length=1, max_length=8)
    trend_samples: list[ShootingSessionTrendSample] = Field(
        min_length=2, max_length=12, alias="trendSamples"
    )
    target_candidates: list[ShootingTarget] = Field(
        default_factory=list, max_length=3, alias="targetCandidates"
    )
    recommended_capabilities: list[
        Literal[
            "tripod",
            "wide_angle",
            "telephoto",
            "filter",
            "weather_protection",
            "headlamp",
        ]
    ] = Field(default_factory=list, max_length=4, alias="recommendedCapabilities")
    rule_version: str = Field(pattern=r"^[a-z0-9._-]{1,32}$", alias="ruleVersion")
    expires_at: datetime = Field(alias="expiresAt")

    @model_validator(mode="after")
    def require_ordered_session(self) -> "ShootingSession":
        if self.end_at <= self.start_at:
            raise ValueError("shooting session times must be ordered")
        if self.primary_phase not in {phase.kind for phase in self.phases}:
            raise ValueError("primary phase must exist in phases")
        return self


class PhotographyCorridorObservation(ApiModel):
    progress: float = Field(ge=0, le=1)
    expected_at: datetime = Field(alias="expectedAt")
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    cloud_cover_percent: float | None = Field(
        None, ge=0, le=100, alias="cloudCoverPercent"
    )
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=500, alias="precipitationMm")
    thunder: bool
    sun_azimuth_degrees: float | None = Field(
        None, ge=0, lt=360, alias="sunAzimuthDegrees"
    )
    opportunity_id: str | None = Field(
        None, alias="opportunityId", pattern=r"^photo-[a-z0-9_-]{1,58}$"
    )

    @field_validator("expected_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("corridor expectedAt must include a timezone")
        return value


class PhotographyCorridor(ApiModel):
    route_id: str = Field(alias="routeId", pattern=r"^[A-Za-z0-9_-]{1,160}$")
    observations: list[PhotographyCorridorObservation] = Field(max_length=3)

    @model_validator(mode="after")
    def require_ordered_observations(self) -> "PhotographyCorridor":
        progress = [item.progress for item in self.observations]
        moments = [item.expected_at for item in self.observations]
        if progress != sorted(progress) or moments != sorted(moments):
            raise ValueError("corridor observations must be ordered")
        return self


class SourceStatus(ApiModel):
    id: str
    dataset_type: Literal["unknown", "spatialFeatures", "astronomyEvents"] = Field(
        alias="datasetType"
    )
    enabled: bool
    license_status: Literal["approved", "pending", "disabled"] = Field(
        alias="licenseStatus"
    )
    attribution: str
    version: str
    license_id: str | None = Field(None, alias="licenseId")
    source_url: HttpUrl | None = Field(None, alias="sourceUrl")
    license_url: HttpUrl | None = Field(None, alias="licenseUrl")
    updated_at: datetime | None = Field(None, alias="updatedAt")


class ImportSource(ApiModel):
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9_-]{0,63}$")
    enabled: bool = False
    license_status: Literal["approved", "pending", "disabled"] = Field(
        alias="licenseStatus"
    )
    attribution: str = Field(min_length=1, max_length=500)
    version: str = Field(min_length=1, max_length=100)
    license_id: str | None = Field(
        None, min_length=1, max_length=100, alias="licenseId"
    )
    source_url: HttpUrl | None = Field(None, alias="sourceUrl", max_length=500)
    license_url: HttpUrl | None = Field(None, alias="licenseUrl", max_length=500)
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
        for url in (self.source_url, self.license_url):
            if url is not None and url.scheme != "https":
                raise ValueError("source and license URLs must use https")
        return self


class SpatialFeatureProperties(ApiModel):
    kind: Literal[
        "urban", "water", "mountain", "arid", "settlement", "protected", "risk"
    ]
    name: str = Field(min_length=1, max_length=200)
    sensitivity: Literal["public", "sensitive"] = "public"
    evidence_class: Literal["scene", "wildlifeOpportunity", "wildlifeSafety"] = Field(
        "scene", alias="evidenceClass"
    )
    photography_target: bool = Field(False, alias="photographyTarget")
    target_type: Literal["viewpoint", "lakeshore", "trailhead", "urban"] | None = Field(
        None, alias="targetType"
    )
    shooting_session_target: bool = Field(False, alias="shootingSessionTarget")
    supported_sessions: list[Literal["waterMorning", "waterEvening"]] = Field(
        default_factory=list, max_length=2, alias="supportedSessions"
    )
    view_bearing_degrees: float | None = Field(
        None, ge=0, lt=360, alias="viewBearingDegrees"
    )
    bearing_tolerance_degrees: float | None = Field(
        None, ge=5, le=90, alias="bearingToleranceDegrees"
    )
    access_modes: list[Literal["driving", "walking"]] = Field(
        default_factory=list, max_length=2, alias="accessModes"
    )
    lead_time_minutes: int | None = Field(None, ge=0, le=180, alias="leadTimeMinutes")
    arrival_radius_meters: int | None = Field(
        None, ge=25, le=1000, alias="arrivalRadiusMeters"
    )
    shoreline_side: (
        Literal[
            "north",
            "northeast",
            "east",
            "southeast",
            "south",
            "southwest",
            "west",
            "northwest",
        ]
        | None
    ) = Field(None, alias="shorelineSide")
    reviewed_at: datetime | None = Field(None, alias="reviewedAt")
    review_reference: HttpUrl | None = Field(
        None, alias="reviewReference", max_length=500
    )

    @model_validator(mode="after")
    def require_complete_target_metadata(self) -> "SpatialFeatureProperties":
        if self.photography_target != (self.target_type is not None):
            raise ValueError("photography targets require targetType")
        metadata = (
            self.supported_sessions,
            self.view_bearing_degrees,
            self.bearing_tolerance_degrees,
            self.access_modes,
            self.lead_time_minutes,
            self.arrival_radius_meters,
            self.shoreline_side,
            self.reviewed_at,
            self.review_reference,
        )
        if self.shooting_session_target:
            if (
                not self.photography_target
                or self.target_type != "lakeshore"
                or not self.supported_sessions
                or not self.access_modes
                or any(value is None for value in metadata[1:])
            ):
                raise ValueError(
                    "shooting session targets require complete reviewed metadata"
                )
            if self.reviewed_at is not None and self.reviewed_at.tzinfo is None:
                raise ValueError(
                    "shooting session target reviewedAt must include a timezone"
                )
        elif any((self.supported_sessions, self.access_modes)) or any(
            value is not None
            for value in (
                self.view_bearing_degrees,
                self.bearing_tolerance_degrees,
                self.lead_time_minutes,
                self.arrival_radius_meters,
                self.shoreline_side,
                self.reviewed_at,
                self.review_reference,
            )
        ):
            raise ValueError("reviewed target metadata requires shootingSessionTarget")
        if len(self.supported_sessions) != len(set(self.supported_sessions)):
            raise ValueError("supportedSessions must be unique")
        if len(self.access_modes) != len(set(self.access_modes)):
            raise ValueError("accessModes must be unique")
        if (
            self.review_reference is not None
            and self.review_reference.scheme != "https"
        ):
            raise ValueError("reviewReference must use https")
        return self


class GeoJsonGeometry(ApiModel):
    type: Literal["Point", "Polygon", "MultiPolygon"]
    coordinates: list[object]

    @model_validator(mode="after")
    def validate_coordinates(self) -> "GeoJsonGeometry":
        def position(value: object) -> bool:
            return (
                isinstance(value, list)
                and len(value) >= 2
                and all(
                    isinstance(item, (int, float)) and not isinstance(item, bool)
                    for item in value[:2]
                )
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
            valid = bool(self.coordinates) and all(
                ring(item) for item in self.coordinates
            )
        elif self.type == "MultiPolygon":
            valid = bool(self.coordinates) and all(
                isinstance(polygon, list)
                and bool(polygon)
                and all(ring(item) for item in polygon)
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
        if self.properties.photography_target:
            if self.properties.sensitivity != "public":
                raise ValueError("photography targets must be public")
            if (
                self.properties.evidence_class != "scene"
                or self.geometry.type != "Point"
            ):
                raise ValueError("photography targets must be public scene points")
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
            longitude_span = max(item[0] for item in positions) - min(
                item[0] for item in positions
            )
            latitude_span = max(item[1] for item in positions) - min(
                item[1] for item in positions
            )
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
                    raise ValueError(
                        "wildlife opportunities require a historical wildlife source"
                    )
                if feature.properties.kind != "protected":
                    raise ValueError(
                        "wildlife opportunities require a reviewed observation area"
                    )
            if evidence == "wildlifeSafety":
                if self.source.category != "officialRisk":
                    raise ValueError("wildlife safety requires an official risk source")
                if feature.properties.kind != "risk":
                    raise ValueError("wildlife safety requires a risk area")
            if feature.properties.shooting_session_target and (
                self.source.license_status != "approved"
                or not self.source.license_id
                or self.source.source_url is None
                or self.source.license_url is None
            ):
                raise ValueError(
                    "shooting session targets require traceable source and license URLs"
                )
        return self


class AstronomyEventImport(ApiModel):
    id: str = Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$")
    event_type: Literal["solarEclipse", "lunarEclipse", "meteorShower", "comet"] = (
        Field(alias="eventType")
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
    dataset_type: Literal["spatialFeatures", "astronomyEvents"] = Field(
        alias="datasetType"
    )
    imported_count: int = Field(ge=0, alias="importedCount")
    enabled: bool
    cache_invalidated: bool = Field(alias="cacheInvalidated")
