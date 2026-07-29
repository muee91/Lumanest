from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from typing import Literal
from urllib.parse import urlsplit
from xml.etree import ElementTree

from pydantic import Field, HttpUrl, field_validator, model_validator
from redis.asyncio import Redis

from .models import BrokerSearchResult, DiscoveryRegion, MissionType, StrictModel


FEED_SOURCE_HASH = "discovery:feed:sources:v1"
FEED_STATUS_HASH = "discovery:feed:status:v1"
FEED_WAKEUP_CHANNEL = "discovery:feed:wakeup:v1"
MAX_FEED_BYTES = 2 * 1024 * 1024
MAX_FEED_ITEMS = 24
MAX_FEED_TEXT = 1200


class FeedSourceDefinition(StrictModel):
    id: str = Field(min_length=1, max_length=80, pattern=r"^[a-z0-9][a-z0-9._-]{0,79}$")
    title: str = Field(min_length=1, max_length=160)
    publisher: str = Field(min_length=1, max_length=80)
    # ``feedUrl`` remains the transport field for compatibility with RSS/Atom
    # sources. In document mode it is the one reviewed first-party document,
    # never a crawl seed or an open URL.
    content_kind: Literal["feed", "document"] = Field(default="feed", alias="contentKind")
    feed_url: HttpUrl = Field(alias="feedUrl")
    item_domains: list[str] = Field(alias="itemDomains", min_length=1, max_length=8)
    source_id: str = Field(alias="sourceId", min_length=1, max_length=80)
    source_version: str = Field(alias="sourceVersion", min_length=1, max_length=80)
    license: str = Field(min_length=1, max_length=160)
    quality_tier: str = Field(default="B", alias="qualityTier", pattern=r"^[SABC]$")
    locale: str = Field(min_length=2, max_length=16, pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
    region: DiscoveryRegion
    mission_types: list[MissionType] = Field(alias="missionTypes", min_length=1, max_length=7)
    refresh_interval_seconds: int = Field(
        default=21600,
        alias="refreshIntervalSeconds",
        ge=900,
        le=604800,
    )
    published_at: datetime | None = Field(default=None, alias="publishedAt")
    enabled: bool = True

    @field_validator("item_domains")
    @classmethod
    def normalize_item_domains(cls, value: list[str]) -> list[str]:
        normalized: list[str] = []
        for item in value:
            domain = item.strip().casefold().rstrip(".")
            labels = domain.split(".")
            if (
                not domain
                or len(domain) > 253
                or len(labels) < 2
                or any(
                    not label
                    or len(label) > 63
                    or label.startswith("-")
                    or label.endswith("-")
                    or not re.fullmatch(r"[a-z0-9-]+", label)
                    for label in labels
                )
            ):
                raise ValueError("invalid item domain")
            if domain not in normalized:
                normalized.append(domain)
        if len(normalized) != len(value):
            raise ValueError("item domains must be unique")
        return normalized

    @field_validator("mission_types")
    @classmethod
    def unique_missions(cls, value: list[MissionType]) -> list[MissionType]:
        if len(set(value)) != len(value):
            raise ValueError("missionTypes must be unique")
        unsupported = {"routeConditions", "openingAndClosure"}
        if any(item in unsupported for item in value):
            raise ValueError("deterministic missions cannot use feeds")
        return value

    @model_validator(mode="after")
    def require_https_feed(self) -> "FeedSourceDefinition":
        if self.feed_url.scheme != "https":
            raise ValueError("feedUrl must use https")
        return self


class FeedSourceState(StrictModel):
    source: FeedSourceDefinition
    last_success_at: datetime | None = Field(default=None, alias="lastSuccessAt")
    next_refresh_at: datetime | None = Field(default=None, alias="nextRefreshAt")
    last_error: str | None = Field(default=None, alias="lastError", max_length=160)
    item_count: int = Field(default=0, alias="itemCount", ge=0, le=MAX_FEED_ITEMS)


class FeedSourceListResponse(StrictModel):
    sources: list[FeedSourceState] = Field(max_length=500)


@dataclass(frozen=True)
class FeedFetchState:
    etag: str | None = None
    last_modified: str | None = None
    content_hash: str | None = None
    last_success_at: datetime | None = None
    next_refresh_at: datetime | None = None
    last_error: str | None = None
    item_count: int = 0
    failure_count: int = 0

    @classmethod
    def from_json(cls, raw: str | None) -> "FeedFetchState":
        if not raw:
            return cls()
        try:
            value = json.loads(raw)
        except (TypeError, ValueError, json.JSONDecodeError):
            return cls()
        if not isinstance(value, dict):
            return cls()

        def timestamp(name: str) -> datetime | None:
            candidate = value.get(name)
            if not isinstance(candidate, str):
                return None
            try:
                parsed = datetime.fromisoformat(candidate.replace("Z", "+00:00"))
            except ValueError:
                return None
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)

        return cls(
            etag=value.get("etag") if isinstance(value.get("etag"), str) else None,
            last_modified=value.get("lastModified") if isinstance(value.get("lastModified"), str) else None,
            content_hash=value.get("contentHash") if isinstance(value.get("contentHash"), str) else None,
            last_success_at=timestamp("lastSuccessAt"),
            next_refresh_at=timestamp("nextRefreshAt"),
            last_error=value.get("lastError") if isinstance(value.get("lastError"), str) else None,
            item_count=value.get("itemCount") if isinstance(value.get("itemCount"), int) else 0,
            failure_count=value.get("failureCount") if isinstance(value.get("failureCount"), int) else 0,
        )

    def to_json(self) -> str:
        def stamp(value: datetime | None) -> str | None:
            return value.astimezone(timezone.utc).isoformat() if value else None

        return json.dumps(
            {
                "etag": self.etag,
                "lastModified": self.last_modified,
                "contentHash": self.content_hash,
                "lastSuccessAt": stamp(self.last_success_at),
                "nextRefreshAt": stamp(self.next_refresh_at),
                "lastError": self.last_error,
                "itemCount": self.item_count,
                "failureCount": self.failure_count,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )


class FeedRegistry:
    def __init__(self, redis: Redis | None) -> None:
        self.redis = redis

    def _required(self) -> Redis:
        if self.redis is None:
            raise RuntimeError("feed_registry_not_configured")
        return self.redis

    async def upsert(self, source: FeedSourceDefinition) -> FeedSourceState:
        client = self._required()
        await client.hset(
            FEED_SOURCE_HASH,
            source.id,
            source.model_dump_json(by_alias=True),
        )
        status = FeedFetchState.from_json(await client.hget(FEED_STATUS_HASH, source.id))
        await client.publish(FEED_WAKEUP_CHANNEL, source.id)
        return _state(source, status)

    async def delete(self, source_id: str) -> bool:
        client = self._required()
        removed = await client.hdel(FEED_SOURCE_HASH, source_id)
        await client.hdel(FEED_STATUS_HASH, source_id)
        await client.publish(FEED_WAKEUP_CHANNEL, source_id)
        return bool(removed)

    async def get(self, source_id: str) -> FeedSourceState | None:
        client = self._required()
        raw = await client.hget(FEED_SOURCE_HASH, source_id)
        if not raw:
            return None
        source = FeedSourceDefinition.model_validate_json(raw)
        status = FeedFetchState.from_json(await client.hget(FEED_STATUS_HASH, source_id))
        return _state(source, status)

    async def list(self) -> FeedSourceListResponse:
        client = self._required()
        sources_raw = await client.hgetall(FEED_SOURCE_HASH)
        statuses_raw = await client.hgetall(FEED_STATUS_HASH)
        result: list[FeedSourceState] = []
        for source_id, raw in sources_raw.items():
            try:
                source = FeedSourceDefinition.model_validate_json(raw)
            except Exception:
                continue
            result.append(_state(source, FeedFetchState.from_json(statuses_raw.get(source_id))))
        result.sort(key=lambda item: (not item.source.enabled, item.source.title.casefold(), item.source.id))
        return FeedSourceListResponse(sources=result[:500])

    async def set_status(self, source_id: str, status: FeedFetchState) -> None:
        client = self._required()
        await client.hset(FEED_STATUS_HASH, source_id, status.to_json())

    async def mark_due(self, source_id: str) -> FeedSourceState | None:
        state = await self.get(source_id)
        if state is None:
            return None
        status = FeedFetchState(
            etag=None,
            last_modified=None,
            content_hash=None,
            last_success_at=state.last_success_at,
            next_refresh_at=datetime.fromtimestamp(0, tz=timezone.utc),
            last_error=None,
            item_count=state.item_count,
            failure_count=0,
        )
        await self.set_status(source_id, status)
        await self._required().publish(FEED_WAKEUP_CHANNEL, source_id)
        return _state(state.source, status)

    async def bootstrap(self, raw_json: str | None) -> int:
        if not raw_json:
            return 0
        try:
            values = json.loads(raw_json)
        except (TypeError, ValueError, json.JSONDecodeError) as error:
            raise RuntimeError("invalid_feed_bootstrap") from error
        if not isinstance(values, list) or len(values) > 500:
            raise RuntimeError("invalid_feed_bootstrap")
        count = 0
        for item in values:
            source = FeedSourceDefinition.model_validate(item)
            await self.upsert(source)
            count += 1
        return count


def _state(source: FeedSourceDefinition, status: FeedFetchState) -> FeedSourceState:
    return FeedSourceState(
        source=source,
        lastSuccessAt=status.last_success_at,
        nextRefreshAt=status.next_refresh_at,
        lastError=status.last_error,
        itemCount=status.item_count,
    )


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def _plain_text(value: str | None) -> str:
    if not value:
        return ""
    parser = _TextExtractor()
    try:
        parser.feed(value)
        parser.close()
        text = " ".join(parser.parts)
    except Exception:
        text = value
    return " ".join(text.split()).strip()[:MAX_FEED_TEXT]


class _DocumentExtractor(HTMLParser):
    """Extract script-free text from one reviewed static document.

    It does not interpret links, execute JavaScript, or discover child pages.
    Static official archives therefore gain a safe evidence path without
    turning the feed worker into a general crawler.
    """

    _ignored_tags = {"script", "style", "noscript", "svg", "template"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._ignored_depth = 0
        self._in_title = False
        self.title_parts: list[str] = []
        self.body_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        normalized = tag.casefold()
        if normalized in self._ignored_tags:
            self._ignored_depth += 1
            return
        if self._ignored_depth:
            return
        if normalized == "title":
            self._in_title = True
            return
        if normalized == "meta":
            metadata = {str(key).casefold(): value for key, value in attrs}
            name = (metadata.get("name") or metadata.get("property") or "").casefold()
            content = metadata.get("content")
            if name in {"description", "og:description"} and content:
                self.body_parts.append(content)

    def handle_endtag(self, tag: str) -> None:
        normalized = tag.casefold()
        if normalized in self._ignored_tags:
            self._ignored_depth = max(0, self._ignored_depth - 1)
            return
        if self._ignored_depth:
            return
        if normalized == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._ignored_depth:
            return
        if self._in_title:
            self.title_parts.append(data)
        self.body_parts.append(data)


def parse_static_document(
    payload: bytes,
    source: FeedSourceDefinition,
) -> list[BrokerSearchResult]:
    if not payload or len(payload) > MAX_FEED_BYTES:
        raise ValueError("feed_size_invalid")
    try:
        document = payload.decode("utf-8-sig")
    except UnicodeDecodeError:
        document = payload.decode("gb18030", errors="replace")
    parser = _DocumentExtractor()
    try:
        parser.feed(document)
        parser.close()
    except Exception as error:
        raise ValueError("document_html_invalid") from error
    title = " ".join(" ".join(parser.title_parts).split()).strip()
    snippet = " ".join(" ".join(parser.body_parts).split()).strip()[:MAX_FEED_TEXT]
    url = _allowed_item_url(str(source.feed_url), source.item_domains)
    if not title or len(title) > 300 or len(snippet) < 30 or url is None:
        raise ValueError("document_content_invalid")
    return [BrokerSearchResult.model_validate({
        "sourceId": source.source_id,
        "publisher": source.publisher,
        "license": source.license,
        "version": source.source_version,
        "qualityTier": source.quality_tier,
        "crawlEnabled": False,
        "crawlMode": "static",
        "allowedPathPrefixes": [],
        "deniedPathPatterns": [],
        "title": title,
        "snippet": snippet,
        "url": url,
        **({"publishedAt": source.published_at.isoformat()} if source.published_at else {}),
    })]


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].casefold()


def _children(node: ElementTree.Element, name: str) -> list[ElementTree.Element]:
    expected = name.casefold()
    return [child for child in list(node) if _local_name(child.tag) == expected]


def _first_text(node: ElementTree.Element, *names: str) -> str | None:
    for name in names:
        for child in _children(node, name):
            value = "".join(child.itertext()).strip()
            if value:
                return value
    return None


def _entry_link(node: ElementTree.Element) -> str | None:
    for child in _children(node, "link"):
        href = child.attrib.get("href")
        relation = child.attrib.get("rel", "alternate")
        if href and relation in {"alternate", ""}:
            return href.strip()
        value = "".join(child.itertext()).strip()
        if value:
            return value
    return None


def _published(value: str | None) -> datetime | None:
    if not value:
        return None
    candidate = value.strip()
    try:
        parsed = parsedate_to_datetime(candidate)
    except (TypeError, ValueError, OverflowError):
        parsed = None
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(candidate.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _allowed_item_url(value: str | None, domains: list[str]) -> str | None:
    if not value or len(value) > 1000:
        return None
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.username
        or parsed.password
        or parsed.port not in (None, 443)
    ):
        return None
    hostname = (parsed.hostname or "").casefold().rstrip(".")
    if not hostname or not any(hostname == domain or hostname.endswith(f".{domain}") for domain in domains):
        return None
    return parsed._replace(fragment="").geturl()


def parse_feed_document(
    payload: bytes,
    source: FeedSourceDefinition,
) -> list[BrokerSearchResult]:
    if not payload or len(payload) > MAX_FEED_BYTES:
        raise ValueError("feed_size_invalid")
    try:
        root = ElementTree.fromstring(payload)
    except ElementTree.ParseError as error:
        raise ValueError("feed_xml_invalid") from error

    root_name = _local_name(root.tag)
    if root_name == "feed":
        entries = _children(root, "entry")
    elif root_name == "rss":
        channels = _children(root, "channel")
        parent = channels[0] if channels else root
        entries = _children(parent, "item")
    elif root_name == "rdf":
        entries = _children(root, "item")
    else:
        raise ValueError("feed_format_unsupported")

    results: list[BrokerSearchResult] = []
    seen: set[str] = set()
    for entry in entries:
        title = _plain_text(_first_text(entry, "title"))
        link = _allowed_item_url(_entry_link(entry), source.item_domains)
        summary = _plain_text(
            _first_text(entry, "content", "encoded", "summary", "description")
        )
        if not title or link is None or not summary or link in seen:
            continue
        seen.add(link)
        published = _published(
            _first_text(entry, "published", "updated", "pubdate", "date")
        )
        results.append(
            BrokerSearchResult.model_validate(
                {
                    "sourceId": source.source_id,
                    "publisher": source.publisher,
                    "license": source.license,
                    "version": source.source_version,
                    "qualityTier": source.quality_tier,
                    "crawlEnabled": False,
                    "crawlMode": "static",
                    "allowedPathPrefixes": [],
                    "deniedPathPatterns": [],
                    "title": title[:300],
                    "snippet": summary,
                    "url": link,
                    **(
                        {"publishedAt": published.isoformat()}
                        if published is not None
                        else {}
                    ),
                }
            )
        )
        if len(results) >= MAX_FEED_ITEMS:
            break
    return results
