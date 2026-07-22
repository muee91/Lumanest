from __future__ import annotations

from datetime import datetime, timedelta
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Wgs84Coordinate(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    system: Literal["wgs84"]


class ActiveSourcePolicy(StrictModel):
    id: str = Field(min_length=1, max_length=80)
    version: str = Field(min_length=1, max_length=80)
    # Legacy reviewed policies are conservatively treated as B. They may
    # inform a brief but cannot by themselves produce a strong action.
    quality_tier: Literal["S", "A", "B", "C"] = Field(default="B", alias="qualityTier")


MissionType = Literal[
    "popularPlaces",
    "hiddenPlaces",
    "humanityEvents",
    "localStories",
    "routeConditions",
    "openingAndClosure",
    "seasonalSignals",
    "localFoodAndSpecialties",
    "culturalEtiquette",
]

DiscoveryActivationType = Literal[
    "user_manual",
    "foreground_opportunistic",
    "ai_verification",
    "admin_backfill",
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
    activation_type: DiscoveryActivationType = Field(alias="activationType")
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


BriefStatus = Literal["ready", "refreshing", "partial", "pending", "unavailable"]
BriefCompleteness = Literal["identityOnly", "partial", "actionable", "comprehensive"]
InsightVerification = Literal["authoritative", "corroborated", "singleSource", "candidate", "conflicting"]
InsightActionability = Literal["informational", "detail", "navigate", "remind"]
InsightType = Literal[
    "areaIdentity", "orientation", "history", "localStory", "architecture",
    "culturalPractice", "etiquette", "performance", "event", "market",
    "localFood", "specialty", "naturalFeature", "photographyTheme", "routeStop",
    "supply", "openingStatus", "regulation", "seasonalSignal",
]
QualityTier = Literal["S", "A", "B", "C"]


class ExplorationSceneProfile(StrictModel):
    physical_scene: Literal[
        "unknown", "urban", "village", "mountain", "plateau", "desert", "forest",
        "inlandWater", "coast", "wetland",
    ] = Field(alias="physicalScene")
    facets: list[str] = Field(max_length=24)
    settlement: Literal[
        "unknown", "none", "metropolitan", "urbanDistrict", "historicDistrict", "historicTown",
        "village", "pastoralSettlement", "scenicArea",
    ]
    remoteness: Literal["unknown", "connected", "edge", "remote", "extreme"]
    altitude: Literal["low", "moderate", "high", "veryHigh", "unknown"]
    poi_density: Literal["unknown", "dense", "normal", "sparse", "verySparse"] = Field(alias="poiDensity")
    mobility: Literal["stationary", "walking", "hiking", "driving"]
    route_stage: Literal["none", "planned", "active", "paused"] = Field(alias="routeStage")

    @field_validator("facets")
    @classmethod
    def unique_facets(cls, value: list[str]) -> list[str]:
        allowed = {
            "lake", "river", "reservoir", "wetland", "coast", "tidalFlat", "waterfall",
            "snowCover", "glacier", "canyon", "dune", "grassland", "forest",
            "bambooForest", "skyline", "architecture", "oldTown", "villageStreet",
            "openRoad", "openHorizon", "darkSky", "reviewedPeak", "reviewedViewpoint",
            "reflectiveSurface",
        }
        if len(set(value)) != len(value) or any(item not in allowed for item in value):
            raise ValueError("invalid scene facets")
        return value


class RegionBriefRequest(StrictModel):
    contract_version: Literal[2] = Field(alias="contractVersion")
    snapshot_id: str = Field(alias="snapshotId", pattern=r"^ctx_[a-f0-9]{24}$")
    activation_type: Literal["user_manual", "foreground_opportunistic"] = Field(alias="activationType")
    locale: str = Field(min_length=2, max_length=16, pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
    region: DiscoveryRegion
    scene_profile: ExplorationSceneProfile = Field(alias="sceneProfile")
    requested_sections: list[Literal[
        "identity", "orientation", "photoThemes", "happeningNow", "places", "localTaste", "etiquette", "practical",
    ]] = Field(alias="requestedSections", min_length=1, max_length=8)
    source_policies: list[ActiveSourcePolicy] = Field(default_factory=list, alias="sourcePolicies", max_length=16)

    @field_validator("requested_sections")
    @classmethod
    def unique_sections(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("requestedSections must be unique")
        return value


class RegionBriefText(StrictModel):
    summary: str = Field(min_length=1, max_length=120)
    fact_ids: list[str] = Field(alias="factIds", min_length=1, max_length=8)


class RegionBriefSource(StrictModel):
    id: str = Field(min_length=1, max_length=160)
    source_policy_id: str = Field(alias="sourcePolicyId", min_length=1, max_length=80)
    publisher: str = Field(min_length=1, max_length=80)
    title: str = Field(min_length=1, max_length=300)
    url: HttpUrl
    observed_at: datetime = Field(alias="observedAt")
    quality_tier: QualityTier = Field(alias="qualityTier")
    license: str = Field(min_length=1, max_length=160)
    version: str = Field(min_length=1, max_length=80)
    published_at: datetime | None = Field(default=None, alias="publishedAt")
    valid_from: datetime | None = Field(default=None, alias="validFrom")
    valid_until: datetime | None = Field(default=None, alias="validUntil")


class RegionBriefInsight(StrictModel):
    id: str = Field(min_length=1, max_length=160)
    region_id: str = Field(alias="regionId", min_length=1, max_length=160)
    type: InsightType
    title: str = Field(min_length=1, max_length=120)
    summary: str = Field(min_length=1, max_length=280)
    verification: InsightVerification
    fact_ids: list[str] = Field(alias="factIds", min_length=1, max_length=8)
    evidence_ids: list[str] = Field(alias="evidenceIds", min_length=1, max_length=8)
    observed_at: datetime = Field(alias="observedAt")
    expires_at: datetime = Field(alias="expiresAt")
    place_id: str | None = Field(default=None, alias="placeId", max_length=160)
    coordinate: Wgs84Coordinate | None = None
    starts_at: datetime | None = Field(default=None, alias="startsAt")
    ends_at: datetime | None = Field(default=None, alias="endsAt")
    time_sensitive: bool = Field(alias="timeSensitive")
    actionability: InsightActionability
    scene_tags: list[str] = Field(alias="sceneTags", max_length=12)
    photo_theme_tags: list[str] = Field(alias="photoThemeTags", max_length=8)

    @field_validator("expires_at")
    @classmethod
    def expires_after_observed(cls, value: datetime, info):
        observed_at = info.data.get("observed_at")
        if observed_at is not None and value <= observed_at:
            raise ValueError("expiresAt must be after observedAt")
        return value


class RegionBriefRefresh(StrictModel):
    refreshing_missions: list[str] = Field(alias="refreshingMissions", max_length=9)
    retry_after_seconds: int | None = Field(alias="retryAfterSeconds", ge=1, le=3600)


class RegionBriefResponse(StrictModel):
    contract_version: Literal[2] = Field(alias="contractVersion")
    brief_id: str = Field(alias="briefId", min_length=1, max_length=160)
    region_id: str = Field(alias="regionId", min_length=1, max_length=160)
    region_name: str = Field(alias="regionName", min_length=1, max_length=160)
    profile: ExplorationSceneProfile
    generated_at: datetime = Field(alias="generatedAt")
    expires_at: datetime = Field(alias="expiresAt")
    status: BriefStatus
    completeness: BriefCompleteness
    identity: RegionBriefText | None
    orientation: RegionBriefText | None
    photo_themes: list[dict[str, str]] = Field(alias="photoThemes", max_length=5)
    insights: list[RegionBriefInsight] = Field(max_length=40)
    sources: list[RegionBriefSource] = Field(max_length=40)
    refresh: RegionBriefRefresh

    @field_validator("expires_at")
    @classmethod
    def response_expires_after_generated(cls, value: datetime, info):
        generated_at = info.data.get("generated_at")
        if generated_at is not None and value <= generated_at:
            raise ValueError("expiresAt must be after generatedAt")
        return value

    @model_validator(mode="after")
    def status_has_consistent_content(self):
        if self.status in {"pending", "unavailable"}:
            if any((
                self.identity is not None,
                self.orientation is not None,
                self.photo_themes,
                self.insights,
                self.sources,
            )):
                raise ValueError("pending and unavailable briefs must not contain facts")
        elif self.identity is None or self.orientation is None:
            raise ValueError("available briefs require fact-bound identity and orientation")
        elif not set(self.identity.fact_ids + self.orientation.fact_ids).issubset(
            {fact_id for insight in self.insights for fact_id in insight.fact_ids}
        ):
            raise ValueError("brief summary fact IDs must resolve through an insight")
        return self


# The following contracts are deliberately internal.  They are the narrow
# hand-off between the discovery worker and the Broker.  Keeping them here
# means an upstream provider or model cannot silently add a field which the
# worker then starts trusting or storing.
class BrokerSearchResult(StrictModel):
    source_id: str = Field(alias="sourceId", min_length=1, max_length=80)
    publisher: str = Field(min_length=1, max_length=80)
    license: str = Field(min_length=1, max_length=160)
    source_version: str = Field(alias="version", min_length=1, max_length=80)
    quality_tier: Literal["S", "A", "B", "C"] = Field(default="B", alias="qualityTier")
    crawl_enabled: bool = Field(default=False, alias="crawlEnabled")
    crawl_mode: Literal["static"] = Field(default="static", alias="crawlMode")
    allowed_path_prefixes: list[str] = Field(
        default_factory=list, max_length=8, alias="allowedPathPrefixes"
    )
    denied_path_patterns: list[str] = Field(
        default_factory=list, max_length=8, alias="deniedPathPatterns"
    )
    title: str = Field(min_length=1, max_length=300)
    snippet: str = Field(default="", max_length=1200)
    url: HttpUrl
    published_at: datetime | None = Field(default=None, alias="publishedAt")

    @field_validator("allowed_path_prefixes", "denied_path_patterns")
    @classmethod
    def validate_crawl_paths(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value) or any(
            len(item) > 120
            or not item.startswith("/")
            or ".." in item
            or any(character in item for character in ("?", "#", "\x00"))
            for item in value
        ):
            raise ValueError("invalid crawl path policy")
        return value

    @model_validator(mode="after")
    def require_bounded_crawl_opt_in(self) -> "BrokerSearchResult":
        if self.crawl_enabled and not self.allowed_path_prefixes:
            raise ValueError("crawl opt-in requires allowed path prefixes")
        return self


class BrokerSearchResponse(StrictModel):
    results: list[BrokerSearchResult] = Field(max_length=24)


class ExtractionCoordinate(StrictModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class ExtractedCandidate(StrictModel):
    kind: Literal["candidate_viewpoint", "attraction", "event"]
    title: str = Field(min_length=1, max_length=120)
    summary: str | None = Field(default=None, max_length=280)
    address_hint: str | None = Field(default=None, alias="addressHint", max_length=300)
    coordinate: ExtractionCoordinate | None = None
    coordinate_evidence: str | None = Field(default=None, alias="coordinateEvidence", min_length=3, max_length=120)
    starts_at: datetime | None = Field(default=None, alias="startsAt")
    ends_at: datetime | None = Field(default=None, alias="endsAt")
    source_indexes: list[int] = Field(alias="sourceIndexes", min_length=1, max_length=4)


class BrokerExtractionResponse(StrictModel):
    candidates: list[ExtractedCandidate] = Field(max_length=20)
    insights: list["ExtractedRegionInsight"] = Field(default_factory=list, max_length=12)


class ExtractedRegionInsight(StrictModel):
    type: InsightType
    title: str = Field(min_length=1, max_length=120)
    summary: str = Field(min_length=1, max_length=280)
    fact_text: str = Field(alias="factText", min_length=1, max_length=600)
    source_indexes: list[int] = Field(alias="sourceIndexes", min_length=1, max_length=4)
    starts_at: datetime | None = Field(default=None, alias="startsAt")
    ends_at: datetime | None = Field(default=None, alias="endsAt")
    time_sensitive: bool = Field(default=False, alias="timeSensitive")
    actionability: InsightActionability = "informational"
    scene_tags: list[str] = Field(default_factory=list, alias="sceneTags", max_length=12)
    photo_theme_tags: list[str] = Field(default_factory=list, alias="photoThemeTags", max_length=8)


class BrokerDeterministicResponse(StrictModel):
    candidates: list[ExtractedCandidate] = Field(max_length=6)
    evidence: list[BrokerSearchResult] = Field(max_length=6)


class PlaceResolutionRequest(StrictModel):
    query: str = Field(min_length=1, max_length=240)
    address_hint: str | None = Field(default=None, alias="addressHint", max_length=300)
    region: DiscoveryRegion
    locale: str = Field(min_length=2, max_length=16)


class PlaceResolutionResponse(StrictModel):
    status: Literal["resolved", "ambiguous", "not_found", "failed"]
    place: dict | None = None
    evidence: BrokerSearchResult | None = None
