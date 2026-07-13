# LumaNest Context Service

FastAPI internal service for deterministic scene classification, context events,
PostGIS spatial evidence, and Redis snapshot TTLs. It is not a public App API.
The Node broker validates App authorization and forwards only the bounded v2
context contract over the private Compose network.

## Local verification

```bash
python3 -m pytest
```

Production requires `DATABASE_URL`, `REDIS_URL`, and a separate
`CONTEXT_INTERNAL_TOKEN`. The token must stay in the NAS environment file and
must never be passed to Flutter.
