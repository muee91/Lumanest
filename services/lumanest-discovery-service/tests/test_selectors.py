from datetime import datetime, timezone

from app.crawl.selectors import select_evidence
from app.models import BrokerSearchResult


def evidence(index: int, domain: str, *, title: str = "资料", published: str | None = None) -> BrokerSearchResult:
    return BrokerSearchResult.model_validate({
        "sourceId": f"source-{domain}",
        "publisher": domain,
        "license": "public-web-reference",
        "version": "2026-07-19",
        "title": f"{title}-{index}",
        "snippet": "杭州活动 地址 时间 坐标",
        "url": f"https://{domain}/article/{index}",
        **({"publishedAt": published} if published else {}),
    })


def test_selector_caps_24_results_and_keeps_at_most_two_per_domain():
    values = [evidence(index, "same.example") for index in range(20)]
    values.extend(evidence(index, f"other-{index}.example") for index in range(4))

    selected = select_evidence(values, mission_type="humanityEvents", focus="杭州活动")

    assert len(selected) == 6
    assert sum("same.example" in str(item.url) for item in selected) == 2


def test_selector_order_is_stable_and_prefers_tier_then_freshness():
    values = [
        evidence(2, "older.example", published="2026-07-10T00:00:00Z"),
        evidence(1, "tier-b.example", title="杭州活动", published="2026-07-12T00:00:00Z"),
        evidence(1, "tier-a.example", title="杭州活动", published="2026-07-11T00:00:00Z"),
    ]
    selected = select_evidence(
        values,
        mission_type="humanityEvents",
        focus="杭州活动",
        source_tiers={"source-tier-a.example": "A", "source-tier-b.example": "B"},
    )

    assert [item.source_id for item in selected] == [
        "source-tier-a.example", "source-tier-b.example", "source-older.example",
    ]


def test_selector_uses_url_as_final_tie_breaker():
    values = [evidence(2, "z.example"), evidence(1, "a.example")]
    selected = select_evidence(values, mission_type="localStories", focus="文化")

    assert [str(item.url) for item in selected] == sorted(str(item.url) for item in values)
