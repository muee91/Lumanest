from __future__ import annotations

import hmac
import os
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from sqlalchemy.exc import SQLAlchemyError

from .models import (
    ContextImportRequest,
    ContextImportResult,
    SceneEvidence,
    ShootingTarget,
    ShootingTargetResolveRequest,
    ShootingSessionFeedbackReceipt,
    ShootingSessionFeedbackRequest,
    ShootingFeedbackCalibrationResponse,
    SnapshotRequest,
    SnapshotResponse,
    SourceStatus,
    WildlifeLayerResponse,
)
from .rules import classify_scene, context_fingerprint, evaluate
from .solar import next_evening_window, next_morning_window, solar_state
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
async def evaluate_context(
    body: SnapshotRequest, request: Request
) -> SnapshotResponse:
    stored = await request.app.state.store.spatial_evidence(
        body.coordinate.latitude, body.coordinate.longitude
    )
    evidence = SceneEvidence(
        urban=body.evidence.urban or stored.urban,
        waterBody=body.evidence.water_body or stored.water_body,
        mountainous=body.evidence.mountainous or stored.mountainous,
        aridLand=body.evidence.arid_land or stored.arid_land,
        settlement=body.evidence.settlement or stored.settlement,
        wildlifeOpportunity=(
            body.evidence.wildlife_opportunity or stored.wildlife_opportunity
        ),
        wildlifeSafety=body.evidence.wildlife_safety or stored.wildlife_safety,
        plateau=body.evidence.plateau,
        forest=body.evidence.forest,
        coast=body.evidence.coast,
        wetland=body.evidence.wetland,
        sceneFacets=body.evidence.scene_facets,
        reviewedPrimaryScene=body.evidence.reviewed_primary_scene,
    )
    scene = classify_scene(body, evidence)
    astronomy_events = await request.app.state.store.active_astronomy_events(body.observed_at)
    target = None
    shooting_targets = []
    targets_by_id = {}
    morning = next_morning_window(body.coordinate, body.observed_at)
    if morning is not None:
        direction = solar_state(body.coordinate, morning.sunrise).azimuth_degrees
        if direction is not None:
            for item in await request.app.state.store.shooting_targets(
                body.coordinate.latitude,
                body.coordinate.longitude,
                direction,
                "waterMorning",
            ):
                targets_by_id[item.id] = item
    evening = next_evening_window(body.coordinate, body.observed_at)
    if evening is not None:
        direction = solar_state(body.coordinate, evening.sunset).azimuth_degrees
        if direction is not None:
            for item in await request.app.state.store.shooting_targets(
                body.coordinate.latitude,
                body.coordinate.longitude,
                direction,
                "waterEvening",
            ):
                targets_by_id[item.id] = item
    shooting_targets = list(targets_by_id.values())
    fingerprint = context_fingerprint(
        body, scene, evidence, astronomy_events, target, shooting_targets
    )
    cached = await request.app.state.store.cached_snapshot(fingerprint)
    if cached is not None:
        return SnapshotResponse.model_validate(cached)
    snapshot = evaluate(
        body, evidence, astronomy_events, target, shooting_targets
    )
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


@app.post(
    "/internal/v1/shooting-targets/resolve",
    response_model=ShootingTarget,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def resolve_shooting_target(
    body: ShootingTargetResolveRequest, request: Request
) -> ShootingTarget:
    """Verify an opaque target ID against its already-public map coordinate."""
    target = await request.app.state.store.resolve_shooting_target(
        body.target_id,
        body.coordinate.latitude,
        body.coordinate.longitude,
    )
    if target is None:
        raise HTTPException(status_code=404, detail="shooting_target_not_found")
    return target


@app.post(
    "/internal/v1/shooting-feedback",
    response_model=ShootingSessionFeedbackReceipt,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def record_shooting_feedback(
    body: ShootingSessionFeedbackRequest, request: Request
) -> ShootingSessionFeedbackReceipt:
    try:
        await request.app.state.store.record_shooting_feedback(body)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error
    return ShootingSessionFeedbackReceipt()


@app.get(
    "/internal/v1/wildlife/layers",
    response_model=WildlifeLayerResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def wildlife_layers(
    request: Request,
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    radius_km: int = Query(20, alias="radiusKm", ge=5, le=50),
) -> WildlifeLayerResponse:
    try:
        areas = await request.app.state.store.wildlife_layers(
            latitude, longitude, radius_km
        )
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error
    return WildlifeLayerResponse(
        generatedAt=datetime.now(timezone.utc),
        radiusKm=radius_km,
        areas=areas,
    )


@app.post(
    "/internal/v1/imports",
    response_model=ContextImportResult,
    response_model_by_alias=True,
    status_code=201,
    dependencies=[Depends(require_internal_token)],
)
async def import_context_dataset(
    body: ContextImportRequest, request: Request
) -> ContextImportResult:
    try:
        return await request.app.state.store.import_dataset(body)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="invalid_import") from error
    except (RuntimeError, SQLAlchemyError) as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error


@app.get(
    "/internal/v1/shooting-feedback/calibration",
    response_model=ShootingFeedbackCalibrationResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def shooting_feedback_calibration(
    request: Request,
    days: int = Query(90, ge=30, le=365),
    minimum_samples: int = Query(5, alias="minimumSamples", ge=5, le=100),
) -> ShootingFeedbackCalibrationResponse:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    try:
        return await request.app.state.store.shooting_feedback_calibration(
            since,
            minimum_samples,
        )
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error
