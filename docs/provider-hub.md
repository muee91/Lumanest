> **文档权威级别：SUPPORTING DOCUMENT**
> 当前产品范围以 [`core-1.0-scope.md`](core-1.0-scope.md) 为准。若本文与 Core 1.0 冲突，本文只能作为历史/实现参考，不能重新启用已冻结能力。

# Provider Hub

The Provider Hub is the supplementary data lane for Explore. It is deliberately
separate from Context V5 and from Discovery evidence admission:

- Context remains the authoritative current environment and safety snapshot.
- Discovery continues to admit place and regional facts through source policy,
  geocoding and corroboration.
- Provider Hub adds bounded observations, references and candidate signals.
- Any provider may fail without blocking Today, Explore, Route or AI.
- Flutter hides the compact surface when no current signal is available.

## API

Authenticated application endpoint:

```http
GET /v1/environment/provider-facts?lat=30.25&lon=120.15&radiusKm=25&locale=zh-CN
Authorization: Bearer <LUMANEST_SERVICE_TOKEN>
```

Optional query fields:

- `at`: ISO-8601 instant within seven days of server time.
- `include`: comma-separated provider IDs for diagnostics or targeted refresh.

Contract version 1 returns one state per requested provider. Status values are
`ready`, `noData`, `unconfigured`, or `unavailable`. Only `ready` providers may
return signals, and every signal carries observation time, expiry, verification
class and an HTTPS source URL.

## Providers

| ID | Source | Runtime mode | Product boundary |
|---|---|---|---|
| `sentinel1` | Copernicus Data Space STAC | public HTTP | catalogue observation only; no automatic surface conclusion |
| `sentinel2` | Copernicus Data Space STAC | public HTTP | catalogue and cloud metadata; NDVI/NDSI/NDWI require Raster Worker |
| `cams` | CAMS normalized gateway | configured gateway | model atmospheric signal, never a fire-sky probability |
| `aeronet` | NASA AERONET V3 | public HTTP | nearby station observation, not exact on-site visibility |
| `officialNotices` | reviewed government/venue gateway | configured gateway | may emit authoritative closure or regulation signals |
| `osm` | OpenStreetMap Overpass | public HTTP | map semantics do not prove current access or safety |
| `wikidata` | Wikidata Query Service | public HTTP | entity discovery and disambiguation only |
| `wikimediaCommons` | Wikimedia Commons API | public HTTP | media availability only; media is not downloaded automatically |
| `gbif` | GBIF occurrence API | public HTTP | historical record density, not current animal presence |
| `ebird` | eBird API | API token | recent aggregate only; precise sensitive coordinates are not exposed |
| `firms` | NASA FIRMS Area API | MAP_KEY | thermal anomaly candidate, never an asserted wildfire |
| `copernicusMarine` | Copernicus Marine normalized gateway | configured gateway | regional marine model; not a replacement for official tide tables |
| `jplHorizons` | NASA JPL Horizons | public HTTP | external ephemeris verification; local astronomy remains primary |
| `noaaSwpc` | NOAA SWPC JSON | public HTTP | geomagnetic context; no routine aurora claim for low latitudes |

Protected Planet is intentionally not connected because its public API licence
is not suitable for a commercial application. Automated Xiaohongshu/Douyin
collection is also outside this system.

## Configuration

Direct providers work with the defaults unless an alternate reviewed endpoint
is required. Credentialed and gateway providers remain `unconfigured` until the
corresponding server variable exists:

```text
LUMANEST_SENTINEL_STAC_URL
LUMANEST_CAMS_GATEWAY_URL
LUMANEST_AERONET_BASE_URL
LUMANEST_OFFICIAL_NOTICE_GATEWAY_URL
LUMANEST_OVERPASS_URL
LUMANEST_WIKIDATA_SPARQL_URL
LUMANEST_COMMONS_API_URL
LUMANEST_GBIF_BASE_URL
LUMANEST_EBIRD_BASE_URL
LUMANEST_EBIRD_API_TOKEN
LUMANEST_FIRMS_BASE_URL
LUMANEST_FIRMS_MAP_KEY
LUMANEST_COPERNICUS_MARINE_GATEWAY_URL
LUMANEST_JPL_HORIZONS_URL
LUMANEST_SWPC_BASE_URL
```

CAMS, official notices and Copernicus Marine use a small normalized gateway
because their production access depends on credentials, local source registries
or toolbox jobs. The gateway response is intentionally narrow:

```json
{
  "signals": [
    {
      "kind": "closure",
      "title": "临时关闭",
      "summary": "来源中的简短事实",
      "verification": "authoritative",
      "observedAt": "2026-08-03T08:00:00Z",
      "expiresAt": "2026-08-03T18:00:00Z",
      "sourceUrl": "https://example.gov/notice"
    }
  ]
}
```

The gateway must not return credentials, raw bulk datasets, unrestricted HTML,
or fields outside this contract.

## Frontend behavior

Explore requests Provider Hub through the existing Broker token. Secrets never
reach Flutter. The Region Brief shows a compact card only when at least one
current signal exists. The map adds a data button under the same condition.
The detail sheet includes:

- current normalized signals ordered by evidence strength and freshness;
- provider availability and publisher attribution;
- observation and expiry times;
- a permanent disclaimer separating observation/reference data from verified
  opening, safety and route facts.

Unconfigured or failed providers remain visible only inside the detail status
list when another provider has produced a useful signal; they never create an
empty card or error page.


## Production operations closure

Provider endpoints and credentials are runtime-managed in the encrypted NAS
admin console. The shared ProviderFactsService reads a fresh immutable runtime
snapshot for every cache miss, so changing a provider endpoint or token does not
require rebuilding Flutter. The console exposes only masked secrets, health,
latency, signal count, cache statistics and sanitized trace IDs.

Sentinel-2 may be augmented by a configured Raster Gateway that returns bounded
NDVI/NDSI/NDWI or surface-change observations. CAMS, Marine and official notice
gateways are type allow-listed. Reviewed official RSS/Atom/JSON feeds may also
be registered with explicit geographic coverage and validity policy.

Only current authoritative closure, road-closure, fire-restriction and regulation
notices that pass the reviewed source and spatial gates are promoted into the
existing Context V5 official-warning lane. Other Provider Hub data remains
supplementary and cannot alter safety state.
