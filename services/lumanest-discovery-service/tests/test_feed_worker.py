from __future__ import annotations

import httpx
import pytest

from app.feed import FeedFetchState, FeedSourceDefinition
from app.feed_worker import _region_reference, fetch_feed


def source() -> FeedSourceDefinition:
    return FeedSourceDefinition.model_validate({
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
    })


def document_source() -> FeedSourceDefinition:
    return FeedSourceDefinition.model_validate({
        **source().model_dump(by_alias=True, mode="json"),
        "id": "hangzhou-history-document",
        "contentKind": "document",
        "feedUrl": "https://culture.example.test/history/town",
        "publishedAt": "2025-01-21T00:00:00Z",
        "missionTypes": ["localStories"],
    })


@pytest.mark.asyncio
async def test_fetch_feed_uses_conditional_headers_and_accepts_304():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["headers"] = dict(request.headers)
        return httpx.Response(
            304,
            headers={"etag": '"next"'},
            request=request,
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        evidence, content_hash, etag, last_modified = await fetch_feed(
            source(),
            FeedFetchState(etag='"current"', last_modified="Wed, 22 Jul 2026 00:00:00 GMT"),
            client=client,
            resolve_dns=False,
        )
    finally:
        await client.aclose()

    assert evidence is None
    assert content_hash is None
    assert etag == '"next"'
    assert last_modified == "Wed, 22 Jul 2026 00:00:00 GMT"
    assert captured["headers"]["if-none-match"] == '"current"'
    assert captured["headers"]["if-modified-since"] == "Wed, 22 Jul 2026 00:00:00 GMT"


@pytest.mark.asyncio
async def test_fetch_feed_parses_a_bounded_200_response():
    payload = b"""<rss><channel><item>
      <title>Night market</title>
      <link>https://culture.example.test/events/night-market</link>
      <description>Open Friday from 18:00.</description>
    </item></channel></rss>"""

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            content=payload,
            headers={"etag": '"v1"', "last-modified": "Thu, 23 Jul 2026 00:00:00 GMT"},
            request=request,
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        evidence, content_hash, etag, last_modified = await fetch_feed(
            source(),
            FeedFetchState(),
            client=client,
            resolve_dns=False,
        )
    finally:
        await client.aclose()

    assert evidence is not None
    assert [item.title for item in evidence] == ["Night market"]
    assert content_hash is not None and len(content_hash) == 64
    assert etag == '"v1"'
    assert last_modified == "Thu, 23 Jul 2026 00:00:00 GMT"


@pytest.mark.asyncio
async def test_fetch_document_admits_only_the_configured_reviewed_page_as_evidence():
    payload = b"""<!doctype html><html><head>
      <title>Historic riverside town</title><meta name="description" content="Official history." />
      <style>.ignored { color: red; }</style></head><body>
      <nav>Navigation</nav><article>The town preserves historic lanes and a waterfront market.</article>
      <script>never include this</script></body></html>"""

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["accept"].startswith("application/atom+xml")
        return httpx.Response(200, content=payload, request=request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        evidence, *_ = await fetch_feed(
            document_source(), FeedFetchState(), client=client, resolve_dns=False,
        )
    finally:
        await client.aclose()

    assert evidence is not None
    assert len(evidence) == 1
    assert evidence[0].title == "Historic riverside town"
    assert "never include this" not in evidence[0].snippet
    assert str(evidence[0].url) == "https://culture.example.test/history/town"
    assert evidence[0].published_at is not None


@pytest.mark.asyncio
async def test_fetch_feed_rejects_cross_domain_redirects():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            302,
            headers={"location": "https://attacker.example/feed.xml"},
            request=request,
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(ValueError, match="domain_not_allowed"):
            await fetch_feed(
                source(),
                FeedFetchState(),
                client=client,
                resolve_dns=False,
            )
    finally:
        await client.aclose()


def test_feed_jobs_use_the_same_coarse_region_grid_as_discovery():
    region = _region_reference(source(), "humanityEvents")

    assert region.region_id.startswith("g")
    assert region.latitude == 30.275
    assert region.longitude == 120.175
    assert region.mission_type == "humanityEvents"
