from __future__ import annotations

from dataclasses import dataclass

import httpx
import pytest

from app.feed import FeedFetchState, FeedSourceDefinition
from app.feed_worker import process_source
from app.models import (
    BrokerSearchResult,
    ExtractionCoordinate,
    ExtractedCandidate,
    ExtractedRegionInsight,
)


@dataclass(frozen=True)
class Scenario:
    id: str
    title: str
    publisher: str
    item_domain: str
    item_title: str
    item_summary: str
    item_path: str
    latitude: float
    longitude: float
    radius_meters: int
    mission_type: str
    candidate_kind: str
    candidate_title: str
    candidate_summary: str
    coordinate: tuple[float, float] | None
    resolved_coordinate: tuple[float, float] | None
    insight_type: str
    insight_title: str
    insight_summary: str
    expected_candidates: int

    @property
    def coordinate_text(self) -> str | None:
        value = self.coordinate or self.resolved_coordinate
        if value is None:
            return None
        return f"{value[0]},{value[1]}"


SCENARIOS = (
    Scenario(
        id="hangzhou-west-lake-events",
        title="杭州西湖人文活动",
        publisher="杭州文旅模拟源",
        item_domain="hangzhou.example.test",
        item_title="北山街周末摄影展活动",
        item_summary="本周末举办城市影像展，时间 10:00-18:00，坐标：30.2741,120.1551。",
        item_path="events/beishan-photo-exhibition",
        latitude=30.2500,
        longitude=120.1500,
        radius_meters=10_000,
        mission_type="humanityEvents",
        candidate_kind="event",
        candidate_title="北山街城市影像展",
        candidate_summary="可了解杭州城市影像与街区文化。",
        coordinate=(30.2741, 120.1551),
        resolved_coordinate=None,
        insight_type="event",
        insight_title="周末城市影像展",
        insight_summary="北山街本周末有城市影像展，可作为人文拍摄补充。",
        expected_candidates=1,
    ),
    Scenario(
        id="wuzhen-local-stories",
        title="乌镇古镇文化故事",
        publisher="桐乡文旅模拟源",
        item_domain="wuzhen.example.test",
        item_title="乌镇水阁与临河建筑历史",
        item_summary="资料介绍水阁、临河民居和传统街巷，参访点坐标：30.7461,120.4862。",
        item_path="stories/water-pavilions",
        latitude=30.7460,
        longitude=120.4860,
        radius_meters=8_000,
        mission_type="localStories",
        candidate_kind="attraction",
        candidate_title="乌镇水阁建筑观察点",
        candidate_summary="适合观察临河建筑结构与古镇生活空间。",
        coordinate=(30.7461, 120.4862),
        resolved_coordinate=None,
        insight_type="architecture",
        insight_title="临河水阁建筑",
        insight_summary="乌镇水阁反映了古镇沿河生活与建筑空间的结合。",
        expected_candidates=1,
    ),
    Scenario(
        id="dunhuang-yadan-viewpoints",
        title="敦煌雅丹摄影地点",
        publisher="敦煌文旅模拟源",
        item_domain="dunhuang.example.test",
        item_title="雅丹地貌日落摄影地点资料",
        item_summary="资料记录开阔地貌与日落方向，观察点坐标：40.498,93.005。",
        item_path="places/yadan-sunset",
        latitude=40.5000,
        longitude=93.0000,
        radius_meters=20_000,
        mission_type="hiddenPlaces",
        candidate_kind="candidate_viewpoint",
        candidate_title="雅丹日落观察点",
        candidate_summary="可观察地貌层次与低角度日落光线。",
        coordinate=(40.498, 93.005),
        resolved_coordinate=None,
        insight_type="photographyTheme",
        insight_title="雅丹地貌层次",
        insight_summary="开阔地貌适合表现风蚀结构、尺度和低角度光线。",
        expected_candidates=1,
    ),
    Scenario(
        id="siguniang-seasonal-signal",
        title="四姑娘山季节景观",
        publisher="阿坝文旅模拟源",
        item_domain="siguniang.example.test",
        item_title="四姑娘山秋季雪线与彩林观察",
        item_summary="资料记录秋季彩林、雪线变化及主要观察区域，地点名称为双桥沟观景区域。",
        item_path="season/autumn-snowline",
        latitude=31.1000,
        longitude=102.9000,
        radius_meters=15_000,
        mission_type="seasonalSignals",
        candidate_kind="candidate_viewpoint",
        candidate_title="双桥沟秋季观察区域",
        candidate_summary="可观察彩林与雪线的季节组合。",
        coordinate=None,
        resolved_coordinate=(31.105, 102.895),
        insight_type="seasonalSignal",
        insight_title="秋季彩林与雪线",
        insight_summary="秋季可能同时出现彩林和较清晰的雪线层次。",
        expected_candidates=1,
    ),
    Scenario(
        id="hangzhou-cross-region-poison",
        title="杭州异地污染隔离",
        publisher="杭州文旅模拟源",
        item_domain="hangzhou.example.test",
        item_title="杭州活动错误坐标样本",
        item_summary="该测试条目故意携带异地坐标：39.9,116.4，用于验证区域隔离。",
        item_path="tests/cross-region-coordinate",
        latitude=30.2500,
        longitude=120.1500,
        radius_meters=10_000,
        mission_type="humanityEvents",
        candidate_kind="event",
        candidate_title="异地坐标隔离样本",
        candidate_summary="该候选必须被距离准入门拒绝。",
        coordinate=(39.9, 116.4),
        resolved_coordinate=None,
        insight_type="event",
        insight_title="区域隔离测试",
        insight_summary="该事实仅用于测试证据链，不应生成杭州地点候选。",
        expected_candidates=0,
    ),
)


class RecordingRegistry:
    redis = None

    def __init__(self) -> None:
        self.statuses: list[tuple[str, FeedFetchState]] = []

    async def get(self, _source_id: str):
        return None

    async def set_status(self, source_id: str, status: FeedFetchState) -> None:
        self.statuses.append((source_id, status))


class RecordingStore:
    def __init__(self) -> None:
        self.insight_batches = []
        self.candidate_batches = []

    async def persist_region_insights(self, job, insights, evidence) -> None:
        self.insight_batches.append((job, list(insights), list(evidence)))

    async def persist_candidates(self, job, candidates) -> None:
        self.candidate_batches.append((job, list(candidates)))


class ScenarioBroker:
    def __init__(self, scenario: Scenario) -> None:
        self.scenario = scenario
        self.resolve_calls = 0

    async def extract_with_insights(self, job, evidence):
        coordinate = None
        coordinate_evidence = None
        if self.scenario.coordinate is not None:
            coordinate = {
                "latitude": self.scenario.coordinate[0],
                "longitude": self.scenario.coordinate[1],
            }
            coordinate_evidence = self.scenario.coordinate_text

        candidate = ExtractedCandidate.model_validate(
            {
                "kind": self.scenario.candidate_kind,
                "title": self.scenario.candidate_title,
                "summary": self.scenario.candidate_summary,
                "addressHint": self.scenario.candidate_title,
                "coordinate": coordinate,
                "coordinateEvidence": coordinate_evidence,
                "sourceIndexes": [0],
            }
        )
        insight = ExtractedRegionInsight.model_validate(
            {
                "type": self.scenario.insight_type,
                "title": self.scenario.insight_title,
                "summary": self.scenario.insight_summary,
                "factText": self.scenario.insight_summary,
                "sourceIndexes": [0],
                "timeSensitive": self.scenario.mission_type in {"humanityEvents", "seasonalSignals"},
                "actionability": "detail",
                "sceneTags": [],
                "photoThemeTags": [],
            }
        )
        assert job.region.mission_type == self.scenario.mission_type
        assert evidence[0].source_id == self.scenario.id
        return [candidate], [insight]

    async def resolve_place(self, _job, candidate):
        self.resolve_calls += 1
        if self.scenario.resolved_coordinate is None:
            return None
        latitude, longitude = self.scenario.resolved_coordinate
        coordinate_text = self.scenario.coordinate_text
        resolved = candidate.model_copy(
            update={
                "coordinate": ExtractionCoordinate(latitude=latitude, longitude=longitude),
                "coordinate_evidence": coordinate_text,
            }
        )
        resolver_evidence = BrokerSearchResult.model_validate(
            {
                "sourceId": "amap-poi",
                "publisher": "高德地图",
                "license": "高德开放平台服务",
                "version": "amap-web-service-v1",
                "qualityTier": "S",
                "title": self.scenario.candidate_title,
                "snippet": f"结构化地点解析。坐标：{coordinate_text}",
                "url": "https://ditu.amap.com/",
                "publishedAt": "2026-07-24T00:00:00Z",
            }
        )
        return resolved, resolver_evidence


def feed_source(scenario: Scenario) -> FeedSourceDefinition:
    return FeedSourceDefinition.model_validate(
        {
            "id": scenario.id,
            "title": scenario.title,
            "publisher": scenario.publisher,
            "feedUrl": f"https://feeds.example.test/{scenario.id}.xml",
            "itemDomains": [scenario.item_domain],
            "sourceId": scenario.id,
            "sourceVersion": "simulation-2026-07-24",
            "license": "simulation-fixture",
            "qualityTier": "A",
            "locale": "zh-CN",
            "region": {
                "latitude": scenario.latitude,
                "longitude": scenario.longitude,
                "radiusMeters": scenario.radius_meters,
            },
            "missionTypes": [scenario.mission_type],
            "refreshIntervalSeconds": 3600,
            "enabled": True,
        }
    )


def feed_payload(scenario: Scenario) -> bytes:
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\"><channel><title>{scenario.title}</title><item>
<title>{scenario.item_title}</title>
<link>https://{scenario.item_domain}/{scenario.item_path}</link>
<description>{scenario.item_summary}</description>
<pubDate>Fri, 24 Jul 2026 00:00:00 GMT</pubDate>
</item></channel></rss>""".encode("utf-8")


@pytest.mark.asyncio
@pytest.mark.parametrize("scenario", SCENARIOS, ids=[item.id for item in SCENARIOS])
async def test_representative_locations_flow_through_feed_evidence_chain(scenario: Scenario):
    payload = feed_payload(scenario)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            content=payload,
            headers={"etag": f'"{scenario.id}-v1"'},
            request=request,
        )

    registry = RecordingRegistry()
    store = RecordingStore()
    broker = ScenarioBroker(scenario)
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        await process_source(
            registry,
            store,
            broker,
            feed_source(scenario),
            client=client,
            resolve_dns=False,
        )
    finally:
        await client.aclose()

    assert len(registry.statuses) == 1
    _, status = registry.statuses[0]
    assert status.last_error is None
    assert status.failure_count == 0
    assert status.item_count == 1
    assert status.content_hash is not None
    assert status.next_refresh_at is not None

    assert len(store.insight_batches) == 1
    insight_job, insights, insight_evidence = store.insight_batches[0]
    assert insight_job.region.region_id.startswith("g")
    assert insight_job.region.mission_type == scenario.mission_type
    assert insight_job.region.focus == scenario.title
    assert insights[0].type == scenario.insight_type
    assert insight_evidence[0].source_id == scenario.id
    assert insight_evidence[0].quality_tier == "A"
    assert insight_evidence[0].license == "simulation-fixture"

    assert len(store.candidate_batches) == 1
    candidate_job, admitted = store.candidate_batches[0]
    assert candidate_job.region.region_id == insight_job.region.region_id
    assert len(admitted) == scenario.expected_candidates

    if scenario.expected_candidates:
        candidate, linked_evidence = admitted[0]
        expected_coordinate = scenario.coordinate or scenario.resolved_coordinate
        assert expected_coordinate is not None
        assert candidate.coordinate is not None
        assert candidate.coordinate.latitude == expected_coordinate[0]
        assert candidate.coordinate.longitude == expected_coordinate[1]
        assert linked_evidence[0].source_id == scenario.id
    else:
        assert scenario.id == "hangzhou-cross-region-poison"

    assert broker.resolve_calls == (1 if scenario.resolved_coordinate is not None else 0)
