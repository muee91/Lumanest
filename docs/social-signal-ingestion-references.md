# Social signal ingestion references

Reviewed against GitHub source on 2026-08-03.

This note records the GitHub projects reviewed for LumaNest social-data discovery.
It is an implementation reference, not permission to bypass platform controls.
Social content is a lead source only and never becomes a user-facing fact without
normal source admission and corroboration.

## Projects reviewed

### DIYgod/RSSHub

- Repository: https://github.com/DIYgod/RSSHub
- Useful pattern: isolated route adapters normalize heterogeneous websites into
  RSS/Atom; self-hosted instances, route health, caching and feed-level failure
  isolation fit the existing LumaNest feed worker.
- Constraint: AGPL-3.0. Do not copy route implementation into the proprietary
  service. Consume a separately deployed instance or independently implement a
  clean-room adapter against public/official interfaces.
- Decision: primary mechanism for reviewed public accounts and institution feeds.

### xpzouying/xiaohongshu-mcp

- Repository: https://github.com/xpzouying/xiaohongshu-mcp
- Useful pattern: browser-session gateway exposes login state, keyword search,
  feed listing, post details and user pages through HTTP/MCP; post detail uses
  identifiers returned by search/feed rather than guessing URLs.
- Operational reality: manual login, persisted browser cookies, xsec tokens and
  single-web-session constraints. The repository itself documents cookie expiry
  and account/session risks.
- License: Apache-2.0, but platform terms and account authorization remain
  separate constraints.
- Decision: do not run a shared LumaNest account. Support user-submitted links
  first; an optional isolated connector may use a dedicated, explicitly
  authorized session and must never enter the authoritative evidence tier.

### dataabc/weiboSpider

- Repository: https://github.com/dataabc/weiboSpider
- Useful pattern: incremental per-account collection, configurable date cursor,
  normalized post/user fields and multiple storage sinks.
- Operational reality: cookie-backed access for the main mode; it is optimized
  for known account IDs rather than geographic discovery.
- License: no top-level LICENSE file was found during review, so no source code
  should be copied.
- Decision: reproduce only the architecture: reviewed-account registry,
  per-account cursor, idempotent post keys and bounded incremental refresh.

### Evil0ctal/Douyin_TikTok_Download_API

- Repository: https://github.com/Evil0ctal/Douyin_TikTok_Download_API
- Useful pattern: asynchronous FastAPI facade, platform-specific crawler module,
  explicit upstream health/failure handling and normalized API responses.
- Operational reality: the project documents browser cookies and anti-bot
  signatures. Those techniques are brittle and unsuitable for a low-supervision
  production evidence chain.
- License: Apache-2.0.
- Decision: borrow the provider boundary and observability pattern only. Do not
  implement signature emulation or automated cookie acquisition in LumaNest.

### SocialSisterYi/bilibili-API-collect

- Repository: https://github.com/SocialSisterYi/bilibili-API-collect
- Status: archived, default branch marked deprecated.
- Useful pattern: endpoint taxonomy and field naming can inform normalization.
- Decision: no runtime dependency. Prefer RSSHub for reviewed UP accounts and
  official Bilibili/open-platform interfaces where authorization exists.

## LumaNest target architecture

```text
Reviewed account/feed registry
        |-- RSS/Atom/RSSHub provider
        |-- official API provider
        |-- optional isolated browser-session provider
        |-- user-submitted public link provider
                         |
                         v
                 social_signal_staging
                         |
        normalize, dedupe, expiry, geo/name hints
                         |
                         v
          official web / map / multi-source check
                         |
                         v
        existing Discovery evidence and admission
                         |
                         v
        Region Brief / candidate / no publication
```

## Provider contract

A future provider should return bounded public signals rather than UI cards:

```python
class SocialSignalProvider(Protocol):
    async def collect(self, request: SocialSignalRequest) -> list[SocialSignal]: ...
```

Minimum normalized fields:

- `platform`, `external_id`, `canonical_url`
- `author_id`, `author_name`, `account_policy_id`
- `published_at`, `observed_at`, `expires_at`
- bounded `title` and `text_excerpt`
- `place_names`, `region_hints`, optional public coordinates
- engagement snapshot as untrusted metadata, never a popularity claim
- `auth_mode`: public, official_oauth, user_session, or rss_proxy
- source license/terms policy and collection status

## Admission rules

1. Social engagement cannot produce “热门、人气、必去” facts.
2. A social post may trigger verification but cannot establish opening status,
   safety, route conditions or event time by itself.
3. Government, venue and organizer accounts can receive a higher source-policy
   tier, but account identity must be reviewed first.
4. Browser sessions are isolated per connector, encrypted at rest and disabled
   by default; no shared consumer account.
5. A provider failure never blocks Explore; it only removes that signal source.
6. Store excerpts and canonical links, not bulk media downloads or comments.

## Recommended implementation order

1. RSSHub reviewed-account adapter using the feed worker already in production.
2. Weibo reviewed-account incremental provider with public/official interfaces.
3. Bilibili reviewed-UP feed adapter.
4. User-submitted Xiaohongshu/Douyin link resolver.
5. Optional user-authorized browser connector only after policy and operations
   review; never use it for background regional crawling.
