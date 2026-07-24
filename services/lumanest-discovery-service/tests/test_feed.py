from __future__ import annotations

import json
from datetime import datetime, timezone

import pytest

from app.feed import (
    FEED_SOURCE_HASH,
    FEED_STATUS_HASH,
    FeedFetchState,
    FeedRegistry,
    FeedSourceDefinition,
    parse_feed_document,
)


def source(**overrides) -> FeedSourceDefinition:
    value = {
        "id": "hangzhou-culture",
        "title": "杭州人文活动",
        "publisher": "杭州文旅",
        "feedUrl": "https://feeds.example.test/hangzhou.xml",
        "itemDomains": ["culture.example.test"],
        "sourceId": "hangzhou-culture",
        "sourceVersion": "2026-07",
        "license": "official-publication",
        "qualityTier": "A",
        "locale": "zh-CN",
        "region": {
            "latitude": 30.25,
            "longitude": 120.15,
            "radiusMeters": 10000,
        },
        "missionTypes": ["humanityEvents", "localStories"],
        "refreshIntervalSeconds": 3600,
        "enabled": True,
    }
    value.update(overrides)
    return FeedSourceDefinition.model_validate(value)


def test_rss_entries_become_strict_broker_evidence():
    payload = b"""<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Hangzhou</title>
        <item>
          <title>Weekend heritage market</title>
          <link>https://culture.example.test/events/market</link>
          <description><![CDATA[<p>The market opens Saturday at 10:00.</p>]]></description>
          <pubDate>Thu, 23 Jul 2026 08:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>"""

    evidence = parse_feed_document(payload, source())

    assert len(evidence) == 1
    assert evidence[0].source_id == "hangzhou-culture"
    assert evidence[0].quality_tier == "A"
    assert evidence[0].title == "Weekend heritage market"
    assert evidence[0].snippet == "The market opens Saturday at 10:00."
    assert str(evidence[0].url) == "https://culture.example.test/events/market"
    assert evidence[0].published_at == datetime(2026, 7, 23, 8, tzinfo=timezone.utc)


def test_atom_entries_and_namespaced_content_are_supported():
    payload = b"""<?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Culture</title>
      <entry>
        <title>Old town exhibition</title>
        <link rel="alternate" href="https://culture.example.test/exhibitions/old-town"/>
        <updated>2026-07-23T12:00:00Z</updated>
        <content type="html">&lt;p&gt;An exhibition about traditional streets.&lt;/p&gt;</content>
      </entry>
    </feed>"""

    evidence = parse_feed_document(payload, source())

    assert [item.title for item in evidence] == ["Old town exhibition"]
    assert evidence[0].snippet == "An exhibition about traditional streets."


def test_feed_rejects_item_urls_outside_reviewed_domains():
    payload = b"""<rss><channel><item>
      <title>Unreviewed mirror</title>
      <link>https://untrusted.example/entry</link>
      <description>Do not ingest this item.</description>
    </item></channel></rss>"""

    assert parse_feed_document(payload, source()) == []


def test_source_contract_rejects_deterministic_missions_and_duplicate_domains():
    with pytest.raises(ValueError):
        source(missionTypes=["openingAndClosure"])
    with pytest.raises(ValueError):
        source(itemDomains=["culture.example.test", "culture.example.test"])


class FakeRedis:
    def __init__(self):
        self.hashes: dict[str, dict[str, str]] = {}
        self.messages: list[tuple[str, str]] = []

    async def hset(self, name, key, value):
        self.hashes.setdefault(name, {})[key] = value
        return 1

    async def hget(self, name, key):
        return self.hashes.get(name, {}).get(key)

    async def hgetall(self, name):
        return dict(self.hashes.get(name, {}))

    async def hdel(self, name, key):
        return 1 if self.hashes.get(name, {}).pop(key, None) is not None else 0

    async def publish(self, channel, value):
        self.messages.append((channel, value))
        return 1


@pytest.mark.asyncio
async def test_registry_round_trip_and_manual_refresh():
    redis = FakeRedis()
    registry = FeedRegistry(redis)

    created = await registry.upsert(source())
    assert created.source.id == "hangzhou-culture"
    assert "hangzhou-culture" in redis.hashes[FEED_SOURCE_HASH]

    await registry.set_status(
        "hangzhou-culture",
        FeedFetchState(
            etag='"abc"',
            content_hash="hash",
            last_success_at=datetime(2026, 7, 23, tzinfo=timezone.utc),
            next_refresh_at=datetime(2026, 7, 24, tzinfo=timezone.utc),
            item_count=4,
            failure_count=2,
        ),
    )
    listed = await registry.list()
    assert listed.sources[0].item_count == 4

    due = await registry.mark_due("hangzhou-culture")
    assert due is not None
    assert due.next_refresh_at == datetime(1970, 1, 1, tzinfo=timezone.utc)
    raw_status = json.loads(redis.hashes[FEED_STATUS_HASH]["hangzhou-culture"])
    assert raw_status["etag"] is None
    assert raw_status["failureCount"] == 0

    assert await registry.delete("hangzhou-culture") is True
    assert await registry.get("hangzhou-culture") is None
