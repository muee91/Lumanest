from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


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


class WeatherInput(ApiModel):
    observed_at: datetime = Field(alias="observedAt")
    condition: Literal["clear", "cloudy", "rain", "snow", "dust", "unknown"]
    wind_speed_mps: float = Field(ge=0, le=150, alias="windSpeedMps")
    precipitation_mm: float = Field(ge=0, le=2000, alias="precipitationMm")
    visibility_km: float = Field(ge=0, le=500, alias="visibilityKm")
    thunder: bool = False
    stale: bool = False


class SolarInput(ApiModel):
    day_phase: Literal["dawn", "day", "sunset", "blueHour", "night"] = Field(alias="dayPhase")


class RouteInput(ApiModel):
    mode: Literal["none", "driving", "hiking"] = "none"
    stage: Literal["none", "planned", "active", "paused"] = "none"


class SnapshotRequest(ApiModel):
    contract_version: Literal[2] = Field(alias="contractVersion")
    coordinate: Coordinate
    observed_at: datetime = Field(alias="observedAt")
    locale: Literal["zh-CN", "en"] = "zh-CN"
    intent: Literal["photography", "food", "supplies", "fuel", "wildlife"] = "photography"
    route: RouteInput = RouteInput()
    evidence: SceneEvidence = SceneEvidence()
    weather: WeatherInput
    solar: SolarInput

    @field_validator("observed_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("observedAt must include a timezone")
        return value


class ContextEvent(ApiModel):
    id: str = Field(pattern=r"^[a-z0-9_-]{1,64}$")
    channel: Literal["opportunity", "safety", "wildlifeOpportunity", "wildlifeSafety"]
    source: Literal["weather", "solar", "rule", "official", "wildlifeHistorical"]
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    confidence: float = Field(ge=0, le=1)
    geo_scope: Literal["point", "regional", "route"] = Field(alias="geoScope")
    severity: Literal["info", "caution", "warning", "critical"] = "info"
    allowed_action: Literal[
        "openExplore", "openShootingWindow", "openWeather", "openSafety", "openRoute"
    ] = Field(alias="allowedAction")


class Manifest(ApiModel):
    layout_mode: Literal["quiet", "opportunity", "safety"] = Field(alias="layoutMode")
    primary_event_id: str | None = Field(None, alias="primaryEventId")
    secondary_event_ids: list[str] = Field(default_factory=list, alias="secondaryEventIds", max_length=2)
    safety_event_ids: list[str] = Field(default_factory=list, alias="safetyEventIds")


class SnapshotResponse(ApiModel):
    contract_version: Literal[2] = Field(2, alias="contractVersion")
    context_id: str = Field(alias="contextId")
    generated_at: datetime = Field(alias="generatedAt")
    expires_at: datetime = Field(alias="expiresAt")
    scene: SceneType
    fingerprint: str
    stale: bool
    events: list[ContextEvent]
    manifest: Manifest


class SourceStatus(ApiModel):
    id: str
    enabled: bool
    license_status: Literal["approved", "pending", "disabled"] = Field(alias="licenseStatus")
    attribution: str
    updated_at: datetime | None = Field(None, alias="updatedAt")
