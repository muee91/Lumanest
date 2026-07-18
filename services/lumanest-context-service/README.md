# LumaNest Context Service

FastAPI internal service for deterministic scene classification, context events,
PostGIS spatial evidence, and Redis snapshot TTLs. It is not a public App API.
The Node broker validates App authorization, replaces all client weather with
server-fetched QWeather data, and forwards only the bounded v2 internal context
contract over the private Compose network. The service computes sun position
and moon phase deterministically; official weather warnings remain rule-owned
safety events and are never delegated to a model.

## Reviewed dataset imports

The internal `POST /internal/v1/imports` endpoint accepts two replacement-style
datasets: bounded GeoJSON `spatialFeatures` and traceable `astronomyEvents`.
Every import includes a source ID, license status, attribution, version, and an
explicit enabled flag. A source can be enabled only when its license status is
`approved`; pending or disabled sources remain inert in spatial rules.

Imports are transactional per source and invalidate `context:v5:*` Redis
snapshots after commit. Sensitive spatial records must be coarse polygons;
exact points and polygons smaller than 0.01 degrees in either dimension are
rejected. Astronomy records require timezone-aware intervals and HTTPS source
URLs. The endpoint is available only through the internal service token and is
forwarded to LAN administrators by the Node Broker.

At evaluation time, only currently active astronomy records from enabled,
`approved` sources become creative events. Their bounded catalog title and
HTTPS authority URL are carried through the Broker as an `openAuthority`
action. The catalog proves that an event is scheduled; it does not claim local
visibility, which still depends on weather and the observer's horizon.

Migration `0004_nasa_meteor_catalog_2026` installs four reviewed 2026 annual
meteor-shower windows from NASA Science. The windows are intentionally broad
and are not presented as precise peak-time predictions. Each event links to
its NASA guide; local visibility still depends on daylight, weather and the
observer's horizon.

## Local verification

```bash
python3 -m pytest
```

Production requires `DATABASE_URL`, `REDIS_URL`, and a separate
`CONTEXT_INTERNAL_TOKEN`. The token must stay in the NAS environment file and
must never be passed to Flutter.
