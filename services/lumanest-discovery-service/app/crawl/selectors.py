from __future__ import annotations

from datetime import datetime, timezone
from urllib.parse import urlsplit

from ..models import BrokerSearchResult, MissionType


TIER_RANK = {"A": 4, "B": 3, "C": 2, "D": 1}
MISSION_TERMS: dict[str, tuple[str, ...]] = {
    "popularPlaces": ("地点", "摄影", "观景", "打卡", "热门"),
    "hiddenPlaces": ("小众", "地点", "摄影", "观景", "机位"),
    "humanityEvents": ("活动", "市集", "节庆", "展览", "演出"),
    "localStories": ("历史", "文化", "故事", "传统", "老街"),
    "seasonalSignals": ("季节", "花期", "候鸟", "云海", "秋色"),
    "localFoodAndSpecialties": ("小吃", "特产", "市场", "传统", "食物"),
    "culturalEtiquette": ("礼仪", "习俗", "参观", "拍摄", "文化"),
}


def select_evidence(
    evidence: list[BrokerSearchResult],
    *,
    mission_type: MissionType,
    focus: str,
    maximum: int = 8,
    max_per_domain: int = 2,
    source_tiers: dict[str, str] | None = None,
) -> list[BrokerSearchResult]:
    """Select a bounded, stable evidence set without using an LLM.

    ``source_tiers`` is deliberately supplied by the caller rather than guessed
    from publisher names. Until SourcePolicy carries tiers, all sources share
    the same tier rank and the remaining deterministic keys decide the order.
    """
    if maximum < 1 or max_per_domain < 1:
        return []
    tiers = source_tiers or {}
    focus_terms = _terms(focus)
    mission_terms = set(MISSION_TERMS.get(mission_type, ()))

    ranked = sorted(
        evidence,
        key=lambda item: _sort_key(item, focus_terms, mission_terms, tiers),
    )
    selected: list[BrokerSearchResult] = []
    domain_counts: dict[str, int] = {}
    seen_urls: set[str] = set()
    for item in ranked:
        url = str(item.url)
        if url in seen_urls:
            continue
        domain = _domain(item)
        if domain_counts.get(domain, 0) >= max_per_domain:
            continue
        selected.append(item)
        seen_urls.add(url)
        domain_counts[domain] = domain_counts.get(domain, 0) + 1
        if len(selected) >= maximum:
            break
    return selected


def _sort_key(
    item: BrokerSearchResult,
    focus_terms: set[str],
    mission_terms: set[str],
    source_tiers: dict[str, str],
) -> tuple[int, float, int, int, str, str]:
    text = f"{item.title} {item.snippet}".casefold()
    tier = TIER_RANK.get(source_tiers.get(item.source_id, ""), 0)
    published = item.published_at or datetime.min.replace(tzinfo=timezone.utc)
    freshness = published.timestamp()
    focus_hits = sum(1 for term in focus_terms if term.casefold() in text)
    mission_hits = sum(1 for term in mission_terms if term.casefold() in text)
    metadata_hits = sum(
        marker in text for marker in ("地址", "坐标", "时间", "日期", "开放", "报名", "公里", "米")
    )
    # Python sorts ascending; negate descending scores and use URL as the
    # final stable tie-breaker. Source ID prevents same-content ties drifting.
    return (-tier, -freshness, -focus_hits, -(mission_hits + metadata_hits), url_host(item), str(item.url))


def _terms(value: str) -> set[str]:
    return {part for part in value.replace("，", " ").replace(",", " ").split() if part}


def _domain(item: BrokerSearchResult) -> str:
    return url_host(item)


def url_host(item: BrokerSearchResult) -> str:
    return (urlsplit(str(item.url)).hostname or "").casefold()
