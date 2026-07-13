from __future__ import annotations

import hmac
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request

from .models import SceneEvidence, SnapshotRequest, SnapshotResponse, SourceStatus
from .rules import classify_scene, context_fingerprint, evaluate
from .store import ContextStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.store = ContextStore(os.getenv("DATABASE_URL"), os.getenv("REDIS_URL"))
    yield
    await app.state.store.close()


app = FastAPI(title="LumaNest Context Service", version="0.1.0", lifespan=lifespan)


def require_internal_token(x_internal_service_token: str | None = Header(default=None)) -> None:
    expected = os.getenv("CONTEXT_INTERNAL_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail="service_not_configured")
    if x_internal_service_token is None or not hmac.compare_digest(x_internal_service_token, expected):
        raise HTTPException(status_code=401, detail="unauthorized")


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz(request: Request) -> dict[str, object]:
    dependencies = await request.app.state.store.readiness()
    return {"status": "ok" if all(dependencies.values()) else "degraded", "dependencies": dependencies}


@app.post(
    "/internal/v1/evaluate",
    response_model=SnapshotResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def evaluate_context(body: SnapshotRequest, request: Request) -> SnapshotResponse:
    evidence = body.evidence
    if not any((evidence.urban, evidence.water_body, evidence.mountainous, evidence.arid_land, evidence.settlement)):
        evidence = await request.app.state.store.spatial_evidence(
            body.coordinate.latitude, body.coordinate.longitude
        )
    scene = classify_scene(body, evidence)
    fingerprint = context_fingerprint(body, scene)
    cached = await request.app.state.store.cached_snapshot(fingerprint)
    if cached is not None:
        return SnapshotResponse.model_validate(cached)
    snapshot = evaluate(body, evidence)
    await request.app.state.store.cache_snapshot(
        snapshot.fingerprint, snapshot.model_dump(mode="json", by_alias=True)
    )
    return snapshot


@app.get(
    "/internal/v1/sources",
    response_model=list[SourceStatus],
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def sources(request: Request) -> list[SourceStatus]:
    return await request.app.state.store.source_statuses()
