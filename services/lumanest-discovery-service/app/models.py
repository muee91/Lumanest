from __future__ import annotations

from datetime import datetime
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


class DiscoveryRequest(StrictModel):
    contract_version: Literal[1] = Field(alias="contractVersion")
    coordinate: Wgs84Coordinate
    locale: str = Field(min_length=2, max_length=16, pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
    focus: Literal["photography", "water", "humanity"] = "photography"
    source_policies: list[ActiveSourcePolicy] = Field(default_factory=list, alias="sourcePolicies", max_length=16)


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
    contract_version: Literal[1] = Field(default=1, alias="contractVersion")
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
