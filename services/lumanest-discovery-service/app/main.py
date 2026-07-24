from __future__ import annotations

import hmac
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response

from .feed import (
    FeedRegistry,
    FeedSourceDefinition,
    FeedSourceListResponse,
    FeedSourceState,
)
from .models import DiscoveryRequest, DiscoveryResponse, RegionBriefRequest, RegionBriefResponse
from .store import DiscoveryStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.store = DiscoveryStore(os.getenv("DATABASE_URL"), os.getenv("REDIS_URL"))
    yield
    await app.state.store.close()


app = FastAPI(title="LumaNest Discovery Service", version="0.2.0", lifespan=lifespan)


def require_internal_token(x_internal_service_token: str | None = Header(default=None)) -> None:
    expected = os.getenv("DISCOVERY_INTERNAL_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail="service_not_configured")
    if x_internal_service_token is None or not hmac.compare_digest(x_internal_service_token, expected):
        raise HTTPException(status_code=401, detail="unauthorized")


def _feed_registry(request: Request) -> FeedRegistry:
    return FeedRegistry(request.app.state.store.redis)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz(request: Request, response: Response) -> dict[str, object]:
    dependencies = await request.app.state.store.readiness()
    ready = all(dependencies.values())
    response.status_code = 200 if ready else 503
    return {"status": "ok" if ready else "degraded", "dependencies": dependencies}


@app.post(
    "/internal/v1/discover",
    response_model=DiscoveryResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def discover(body: DiscoveryRequest, request: Request, response: Response) -> DiscoveryResponse:
    try:
        result, status_code = await request.app.state.store.response_for(body)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error
    response.status_code = status_code
    return result


@app.post(
    "/internal/v1/explore/brief",
    response_model=RegionBriefResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def region_brief(
    body: RegionBriefRequest,
    request: Request,
    response: Response,
) -> RegionBriefResponse:
    try:
        result, status_code = await request.app.state.store.region_brief_for(body)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="storage_unavailable") from error
    response.status_code = status_code
    return result


@app.get(
    "/internal/v1/feeds",
    response_model=FeedSourceListResponse,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def list_feed_sources(request: Request) -> FeedSourceListResponse:
    try:
        return await _feed_registry(request).list()
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="feed_registry_unavailable") from error


@app.put(
    "/internal/v1/feeds/{source_id}",
    response_model=FeedSourceState,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def upsert_feed_source(
    source_id: str,
    body: FeedSourceDefinition,
    request: Request,
) -> FeedSourceState:
    if source_id != body.id:
        raise HTTPException(status_code=400, detail="feed_source_id_mismatch")
    try:
        return await _feed_registry(request).upsert(body)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="feed_registry_unavailable") from error


@app.delete(
    "/internal/v1/feeds/{source_id}",
    dependencies=[Depends(require_internal_token)],
)
async def delete_feed_source(source_id: str, request: Request) -> dict[str, bool]:
    try:
        removed = await _feed_registry(request).delete(source_id)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="feed_registry_unavailable") from error
    if not removed:
        raise HTTPException(status_code=404, detail="feed_source_not_found")
    return {"deleted": True}


@app.post(
    "/internal/v1/feeds/{source_id}/refresh",
    response_model=FeedSourceState,
    response_model_by_alias=True,
    dependencies=[Depends(require_internal_token)],
)
async def refresh_feed_source(source_id: str, request: Request) -> FeedSourceState:
    try:
        state = await _feed_registry(request).mark_due(source_id)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="feed_registry_unavailable") from error
    if state is None:
        raise HTTPException(status_code=404, detail="feed_source_not_found")
    return state
