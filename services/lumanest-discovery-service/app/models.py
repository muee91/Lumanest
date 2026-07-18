from __future__ import annotations

from datetime import datetime, timedelta
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Wgs84Coordinate(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    system: Literal["wgs84"]


class ActiveSourcePolicy(StrictModel):
    id: str = Field(min_length=1, max_length=80)
    version: str = Field(min_length=1, max_length=80)


MissionType = Literal[
    "popularPlaces",
    "hiddenPlaces",
    "humanityEvents",
    "localStories",
    "routeConditions",
    "openingAndClosure",
    "seasonalSignals",
]


class DiscoveryRegion(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    radius_meters: int = Field(alias="radiusMeters", ge=100, le=50_000)


class DiscoveryTimeRange(StrictModel):
    starts_at: datetime = Field(alias="startsAt")
    ends_at: datetime = Field(alias="endsAt")

    @field_validator("ends_at")
    @classmethod
    def valid_end(cls, value: datetime, info):
        starts_at = info.data.get("starts_at")
        if starts_at is not None and (value <= starts_at or value - starts_at > timedelta(days=31)):
            raise ValueError("timeRange must be ordered and at most 31 days")
        return value


class DiscoveryRouteSample(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class DiscoveryRouteCorridor(StrictModel):
    route_id: str = Field(alias="routeId", min_length=1, max_length=160)
    name: str = Field(min_length=1, max_length=160)
    samples: list[DiscoveryRouteSample] = Field(min_length=2, max_length=16)


class DiscoveryRequest(StrictModel):
    mission_type: MissionType = Field(alias="missionType")
    focus: str = Field(min_length=1, max_length=180)
    locale: str = Field(min_length=2, max_length=16, pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
    region: DiscoveryRegion
    time_range: DiscoveryTimeRange = Field(alias="timeRange")
    route_corridor: DiscoveryRouteCorridor | None = Field(alias="routeCorridor")
    interests: list[str] = Field(max_length=16)
    source_policies: list[ActiveSourcePolicy] = Field(default_factory=list, alias="sourcePolicies", max_length=16)

    @field_validator("interests")
    @classmethod
    def valid_interests(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value) or any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9._-]{0,63}", item) for item in value):
            raise ValueError("invalid interests")
        return value

    @field_validator("route_corridor")
    @classmethod
    def route_required_for_route_mission(cls, value: DiscoveryRouteCorridor | None, info):
        if info.data.get("mission_type") == "routeConditions" and value is None:
            raise ValueError("routeConditions requires routeCorridor")
        return value


class DiscoveryEvidence(StrictModel):
    publisher: str = Field(min_length=1, max_length=80)
    title: str = Field(min_length=1, max_length=200)
    url: HttpUrl
    observed_at: datetime = Field(alias="observedAt")


class DiscoveryItem(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    kind: Literal["candidate_viewpoint", "attraction", "event"]
    title: str = Field(min_length=1, max_length=120)
    subtitle: str | None = Field(default=None, max_length=280)
    place_status: Literal["candidate", "verified", "mine"] = Field(alias="placeStatus")
    coordinate: Wgs84Coordinate
    distance_meters: int = Field(alias="distanceMeters", ge=0, le=50_000)
    address: str | None = Field(default=None, max_length=200)
    starts_at: datetime | None = Field(default=None, alias="startsAt")
    ends_at: datetime | None = Field(default=None, alias="endsAt")
    evidence: list[DiscoveryEvidence] = Field(max_length=4)

    @field_validator("evidence")
    @classmethod
    def require_evidence(cls, value: list[DiscoveryEvidence]) -> list[DiscoveryEvidence]:
        if not value:
            raise ValueError("evidence must not be empty")
        return value


class DiscoveryResponse(StrictModel):
    mission_type: MissionType = Field(alias="missionType")
    status: Literal["ready", "refreshing", "pending"]
    generated_at: datetime = Field(alias="generatedAt")
    expires_at: datetime | None = Field(alias="expiresAt")
    retry_after_seconds: int | None = Field(alias="retryAfterSeconds", ge=1, le=3600)
    items: list[DiscoveryItem] = Field(max_length=40)


# The following contracts are deliberately internal.  They are the narrow
# hand-off between the discovery worker and the Broker.  Keeping them here
# means an upstream provider or model cannot silently add a field which the
# worker then starts trusting or storing.
class BrokerSearchResult(StrictModel):
    source_id: str = Field(alias="sourceId", min_length=1, max_length=80)
    publisher: str = Field(min_length=1, max_length=80)
    license: str = Field(min_length=1, max_length=160)
    source_version: str = Field(alias="version", min_length=1, max_length=80)
    title: str = Field(min_length=1, max_length=300)
    snippet: str = Field(default="", max_length=1200)
    url: HttpUrl
    published_at: datetime | None = Field(default=None, alias="publishedAt")


class BrokerSearchResponse(StrictModel):
    results: list[BrokerSearchResult] = Field(max_length=24)


class ExtractionCoordinate(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class ExtractedCandidate(StrictModel):
    kind: Literal["candidate_viewpoint", "attraction", "event"]
    title: str = Field(min_length=1, max_length=120)
    summary: str | None = Field(default=None, max_length=280)
    coordinate: ExtractionCoordinate | None = None
    coordinate_evidence: str | None = Field(default=None, alias="coordinateEvidence", min_length=3, max_length=120)
    starts_at: datetime | None = Field(default=None, alias="startsAt")
    ends_at: datetime | None = Field(default=None, alias="endsAt")
    source_indexes: list[int] = Field(alias="sourceIndexes", min_length=1, max_length=4)


class BrokerExtractionResponse(StrictModel):
    candidates: list[ExtractedCandidate] = Field(max_length=20)


class BrokerDeterministicResponse(StrictModel):
    candidates: list[ExtractedCandidate] = Field(max_length=6)
    evidence: list[BrokerSearchResult] = Field(max_length=6)
