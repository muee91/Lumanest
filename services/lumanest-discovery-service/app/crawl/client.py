from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone
from typing import Protocol

from .url_guard import UrlPolicy, guard_url


class PageCrawler(Protocol):
    async def crawl(self, url: str, policy: UrlPolicy) -> dict: ...


class Crawl4AIPageCrawler:
    def __init__(self, *, timeout_ms: int = 12_000) -> None:
        self.timeout_ms = timeout_ms

    async def crawl(self, url: str, policy: UrlPolicy) -> dict:
        requested_url = guard_url(url, policy)
        from crawl4ai import AsyncWebCrawler, BrowserConfig, CacheMode, CrawlerRunConfig

        browser = BrowserConfig(
            browser_type="chromium",
            headless=True,
            java_script_enabled=False,
            text_mode=True,
            light_mode=True,
            avoid_ads=True,
            ignore_https_errors=False,
            accept_downloads=False,
        )
        run = CrawlerRunConfig(
            word_count_threshold=20,
            excluded_tags=["script", "style", "noscript", "nav", "footer", "form", "aside"],
            remove_forms=True,
            exclude_external_links=True,
            wait_until="domcontentloaded",
            page_timeout=self.timeout_ms,
            wait_for_images=False,
            cache_mode=CacheMode.BYPASS,
        )
        async with AsyncWebCrawler(config=browser) as crawler:
            result = await crawler.arun(url=requested_url, config=run)
        final_url = guard_url(str(getattr(result, "url", requested_url)), policy)
        markdown = _normalize_markdown(getattr(result, "markdown", None))
        if len(markdown.encode("utf-8")) > 256 * 1024:
            return {"requestedUrl": requested_url, "finalUrl": final_url, "status": "oversized", "fetchedAt": _now(), "cleanedMarkdown": None, "contentHash": None}
        status = "success" if getattr(result, "success", False) else "failed"
        return {"requestedUrl": requested_url, "finalUrl": final_url, "status": status, "fetchedAt": _now(), "cleanedMarkdown": markdown or None, "contentHash": hashlib.sha256(markdown.encode()).hexdigest() if markdown else None}


def _normalize_markdown(value: object) -> str:
    if not isinstance(value, str):
        return ""
    value = re.sub(r"\r\n?", "\n", value)
    value = re.sub(r"[ \t]+", " ", value)
    return re.sub(r"\n{3,}", "\n\n", value).strip()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
