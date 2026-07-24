from __future__ import annotations

from dataclasses import dataclass

import httpx
import pytest

from app.feed import FeedFetchState, FeedSourceDefinition
from app.feed_worker import process_source
from app.models import ExtractedCandidate, ExtractedRegionInsight


@dataclass(frozen=True)
class HainingHumanityScenario:
    id: str
    title: str
    source_path: str
    item_title: str
    item_summary: str
    mission_type: str
    candidate_kind: str
    candidate_title: str
    candidate_summary: str
    coordinate: tuple[float, float] | None
    insight_type: str
    insight_title: str
    insight_summary: str
    scene_tags: tuple[str, ...]
    photo_theme_tags: tuple[str, ...]
    expected_candidates: int

    @property
    def coordinate_text(self) -> str | None:
        if self.coordinate is None:
            return None
        return f"{self.coordinate[0]},{self.coordinate[1]}"

    @property
    def source_url(self) -> str:
        return f"https://www.haining.gov.cn{self.source_path}"


# The titles and summaries mirror stable themes documented by Haining government
# publications. Coordinates are deliberately low-precision simulation fixtures;
# they are not production POI truth and are never fetched from the public pages.
HAINING_SCENARIOS = (
    HainingHumanityScenario(
        id="haining-yanguan-tide-culture",
        title="海宁盐官潮文化",
        source_path="/art/2017/2/13/art_1229777387_131640.html",
        item_title="盐官古城与钱江潮文化资料",
        item_summary=(
            "海宁以钱江大潮、千年古城形成潮文化旅游主题，"
            "模拟观察区域坐标：30.455,120.552。"
        ),
        mission_type="localStories",
        candidate_kind="attraction",
        candidate_title="盐官古城潮文化观察区域",
        candidate_summary="可理解古城空间、观潮传统与海宁潮文化之间的联系。",
        coordinate=(30.455, 120.552),
        insight_type="localStory",
        insight_title="潮城与千年古城",
        insight_summary="盐官的人文识别应同时包含钱江潮传统和古城历史，而不只是一处观景点。",
        scene_tags=("oldTown", "river"),
        photo_theme_tags=("humanity", "architecture"),
        expected_candidates=1,
    ),
    HainingHumanityScenario(
        id="haining-xiashi-lantern-craft",
        title="海宁硖石灯彩非遗",
        source_path="/art/2017/2/13/art_1229777387_131640.html",
        item_title="硖石灯彩传统工艺与展示空间",
        item_summary=(
            "海宁以硖石灯彩为非遗文化资源，包含灯彩设计、展示和传承体验，"
            "模拟参访区域坐标：30.529,120.684。"
        ),
        mission_type="localStories",
        candidate_kind="attraction",
        candidate_title="硖石灯彩文化观察区域",
        candidate_summary="适合了解灯彩结构、制作工艺和夜间视觉语言。",
        coordinate=(30.529, 120.684),
        insight_type="culturalPractice",
        insight_title="硖石灯彩",
        insight_summary="灯彩应被解释为持续传承的地方工艺，而不是普通夜景装饰。",
        scene_tags=("historicDistrict", "architecture"),
        photo_theme_tags=("folkCraft", "nightCulture"),
        expected_candidates=1,
    ),
    HainingHumanityScenario(
        id="haining-jinyong-hometown",
        title="海宁金庸故里文化",
        source_path="/art/2024/12/13/art_1688422_176631.html",
        item_title="袁花金庸故里与侠义文化资料",
        item_summary=(
            "袁花镇围绕金庸故居、作品阅读与侠义文化开展地方文化建设，"
            "模拟故里区域坐标：30.426,120.756。"
        ),
        mission_type="localStories",
        candidate_kind="attraction",
        candidate_title="金庸故里文化观察区域",
        candidate_summary="可从故居、乡土环境和地方叙事理解金庸文化的海宁根源。",
        coordinate=(30.426, 120.756),
        insight_type="localStory",
        insight_title="金庸故里",
        insight_summary="前台应说明金庸文化与袁花地方环境的关系，避免只显示名人标签。",
        scene_tags=("villageStreet", "architecture"),
        photo_theme_tags=("literature", "humanity"),
        expected_candidates=1,
    ),
    HainingHumanityScenario(
        id="haining-zhimo-cultural-route",
        title="海宁志摩故里街区",
        source_path="/art/2025/1/21/art_1688462_177358.html",
        item_title="志摩故里与硖石历史街区游线",
        item_summary=(
            "志摩故里游线串联南关厢、干河街、横头街和康桥1924等文化空间，"
            "模拟街区中心坐标：30.526,120.681。"
        ),
        mission_type="popularPlaces",
        candidate_kind="attraction",
        candidate_title="志摩故里历史街区游线",
        candidate_summary="适合观察江南街巷、民国建筑和工业遗存之间的城市文化层次。",
        coordinate=(30.526, 120.681),
        insight_type="architecture",
        insight_title="志摩故里街区层次",
        insight_summary="这条文化线索应按街区组合呈现，而不是被压缩成单一故居介绍。",
        scene_tags=("historicDistrict", "architecture"),
        photo_theme_tags=("street", "literature"),
        expected_candidates=1,
    ),
    HainingHumanityScenario(
        id="haining-city-cultural-identity-only",
        title="海宁城市文化识别",
        source_path="/art/2017/2/13/art_1229777387_131640.html",
        item_title="海宁潮灯名人三类文化资源",
        item_summary=(
            "官方规划将潮文化、硖石灯彩和名人文化作为海宁的重要文化资源。"
            "该城市级概述没有可验证的单一地点坐标。"
        ),
        mission_type="localStories",
        candidate_kind="attraction",
        candidate_title="海宁城市文化概述",
        candidate_summary="该内容只应形成区域认知，不应被伪造成可导航地点。",
        coordinate=None,
        insight_type="areaIdentity",
        insight_title="潮、灯、名人",
        insight_summary="海宁的区域身份可概括为潮文化、灯彩非遗和名人文化三条主线。",
        scene_tags=("urban",),
        photo_theme_tags=("humanity",),
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


class HainingScenarioBroker:
    def __init__(self, scenario: HainingHumanityScenario) -> None:
        self.scenario = scenario
        self.resolve_calls = 0

    async def extract_with_insights(self, job, evidence):
        coordinate = None
        if self.scenario.coordinate is not None:
            coordinate = {
                "latitude": self.scenario.coordinate[0],
                "longitude": self.scenario.coordinate[1],
            }

        candidate = ExtractedCandidate.model_validate(
            {
                "kind": self.scenario.candidate_kind,
                "title": self.scenario.candidate_title,
                "summary": self.scenario.candidate_summary,
                "addressHint": self.scenario.candidate_title,
                "coordinate": coordinate,
                "coordinateEvidence": self.scenario.coordinate_text,
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
                "timeSensitive": False,
                "actionability": "detail",
                "sceneTags": list(self.scenario.scene_tags),
                "photoThemeTags": list(self.scenario.photo_theme_tags),
            }
        )

        assert job.region.mission_type == self.scenario.mission_type
        assert len(evidence) == 1
        assert str(evidence[0].url) == self.scenario.source_url
        return [candidate], [insight]

    async def resolve_place(self, _job, _candidate):
        self.resolve_calls += 1
        return None


def source_for(scenario: HainingHumanityScenario) -> FeedSourceDefinition:
    return FeedSourceDefinition.model_validate(
        {
            "id": scenario.id,
            "title": scenario.title,
            "publisher": "海宁市人民政府模拟订阅源",
            "feedUrl": f"https://feeds.example.test/{scenario.id}.xml",
            "itemDomains": ["haining.gov.cn"],
            "sourceId": scenario.id,
            "sourceVersion": "simulation-2026-07-24",
            "license": "simulation-fixture-from-official-publication",
            "qualityTier": "A",
            "locale": "zh-CN",
            "region": {
                "latitude": 30.525,
                "longitude": 120.675,
                "radiusMeters": 30_000,
            },
            "missionTypes": [scenario.mission_type],
            "refreshIntervalSeconds": 21_600,
            "enabled": True,
        }
    )


def payload_for(scenario: HainingHumanityScenario) -> bytes:
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\"><channel><title>{scenario.title}</title><item>
<title>{scenario.item_title}</title>
<link>{scenario.source_url}</link>
<description>{scenario.item_summary}</description>
<pubDate>Fri, 24 Jul 2026 00:00:00 GMT</pubDate>
</item></channel></rss>""".encode("utf-8")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "scenario",
    HAINING_SCENARIOS,
    ids=[scenario.id for scenario in HAINING_SCENARIOS],
)
async def test_haining_humanity_items_flow_through_the_feed_chain(
    scenario: HainingHumanityScenario,
):
    payload = payload_for(scenario)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            content=payload,
            headers={"etag": f'"{scenario.id}-v1"'},
            request=request,
        )

    registry = RecordingRegistry()
    store = RecordingStore()
    broker = HainingScenarioBroker(scenario)
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        await process_source(
            registry,
            store,
            broker,
            source_for(scenario),
            client=client,
            resolve_dns=False,
        )
    finally:
        await client.aclose()

    assert len(registry.statuses) == 1
    source_id, status = registry.statuses[0]
    assert source_id == scenario.id
    assert status.last_error is None
    assert status.failure_count == 0
    assert status.item_count == 1
    assert status.content_hash is not None
    assert status.next_refresh_at is not None

    assert len(store.insight_batches) == 1
    insight_job, insights, evidence = store.insight_batches[0]
    assert insight_job.region.mission_type == scenario.mission_type
    assert insight_job.region.focus == scenario.title
    assert len(insights) == 1
    assert insights[0].type == scenario.insight_type
    assert insights[0].scene_tags == list(scenario.scene_tags)
    assert insights[0].photo_theme_tags == list(scenario.photo_theme_tags)
    assert evidence[0].publisher == "海宁市人民政府模拟订阅源"
    assert evidence[0].quality_tier == "A"
    assert evidence[0].license == "simulation-fixture-from-official-publication"
    assert str(evidence[0].url) == scenario.source_url

    assert len(store.candidate_batches) == 1
    candidate_job, admitted = store.candidate_batches[0]
    assert candidate_job.region.region_id == insight_job.region.region_id
    assert len(admitted) == scenario.expected_candidates

    if scenario.expected_candidates:
        candidate, linked_evidence = admitted[0]
        assert scenario.coordinate is not None
        assert candidate.coordinate is not None
        assert candidate.coordinate.latitude == scenario.coordinate[0]
        assert candidate.coordinate.longitude == scenario.coordinate[1]
        assert linked_evidence[0].source_id == scenario.id
        assert broker.resolve_calls == 0
    else:
        assert scenario.id == "haining-city-cultural-identity-only"
        assert broker.resolve_calls == 1
