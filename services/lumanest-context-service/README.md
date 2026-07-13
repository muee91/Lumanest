# LumaNest Context Service

FastAPI internal service for deterministic scene classification, context events,
PostGIS spatial evidence, and Redis snapshot TTLs. It is not a public App API.
The Node broker validates App authorization and forwards only the bounded v2
context contract over the private Compose network.

## Reviewed dataset imports

The internal `POST /internal/v1/imports` endpoint accepts two replacement-style
datasets: bounded GeoJSON `spatialFeatures` and traceable `astronomyEvents`.
Every import includes a source ID, license status, attribution, version, and an
explicit enabled flag. A source can be enabled only when its license status is
`approved`; pending or disabled sources remain inert in spatial rules.

Imports are transactional per source and invalidate `context:v2:*` Redis
snapshots after commit. Sensitive spatial records must be coarse polygons;
exact points and polygons smaller than 0.01 degrees in either dimension are
rejected. Astronomy records require timezone-aware intervals and HTTPS source
URLs. The endpoint is available only through the internal service token and is
forwarded to LAN administrators by the Node Broker.

## Local verification

```bash
python3 -m pytest
```

Production requires `DATABASE_URL`, `REDIS_URL`, and a separate
`CONTEXT_INTERNAL_TOKEN`. The token must stay in the NAS environment file and
must never be passed to Flutter.
