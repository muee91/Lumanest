import assert from 'node:assert/strict';
import test from 'node:test';

import {
  forwardContextSnapshot,
  fetchWildlifeLayers,
  importContextDataset,
  validContextRequest,
} from '../src/context/proxy.mjs';

const wildlifeLayerResponse = {
  contractVersion: 1,
  generatedAt: '2026-07-16T02:00:00Z',
  radiusKm: 20,
  areas: [{
    id: 'a'.repeat(64),
    name: '历史观察区域',
    geometry: {
      type: 'Polygon',
      coordinates: [[[120, 30], [120.2, 30], [120.2, 30.2], [120, 30]]],
    },
    source: {
      attribution: 'Reviewed wildlife dataset',
      version: '2026.07',
      updatedAt: '2026-07-16T00:00:00Z',
    },
  }],
};

const minimalRequest = {
  contractVersion: 5,
  coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
  observedAt: '2026-07-14T10:00:00+08:00',
  locale: 'zh-CN',
  intent: 'photography',
  route: { mode: 'none', stage: 'none', routeId: null, corridorSamples: [] },
};

test('public context validator accepts only the current canonical contract', () => {
  assert.equal(validContextRequest(minimalRequest), true);
  assert.equal(validContextRequest({ ...minimalRequest, contractVersion: 3 }), false);
  assert.equal(validContextRequest({ ...minimalRequest, evidence: {} }), false);
  assert.equal(validContextRequest({ ...minimalRequest, deviceId: 'forbidden' }), false);
});

test('route invariant rejects none/active and driving/none but accepts planned/active/paused', () => {
  assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'none', stage: 'active', routeId: null, corridorSamples: [] } }), false);
  assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'driving', stage: 'none', routeId: null, corridorSamples: [] } }), false);
  for (const stage of ['planned', 'active', 'paused']) {
    assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'driving', stage, routeId: null, corridorSamples: [] } }), true);
  }
});

test('current contract accepts only bounded ordered WGS84 corridor samples', () => {
  const route = {
    mode: 'driving',
    stage: 'planned',
    routeId: 'client_route_hash_123',
    corridorSamples: [0, .5, 1].map((progress, index) => ({
      latitude: 30 + index / 100,
      longitude: 120 + index / 100,
      system: 'wgs84',
      expectedAt: ['2026-07-14T02:00:00Z', '2026-07-14T03:00:00Z', '2026-07-14T04:00:00Z'][index],
      progress,
    })),
  };
  assert.equal(validContextRequest({ ...minimalRequest, route }), true);
  assert.equal(validContextRequest({
    ...minimalRequest,
    route: { ...route, routeId: undefined },
  }), false);
  assert.equal(validContextRequest({
    ...minimalRequest,
    route: { ...route, corridorSamples: [...route.corridorSamples].reverse() },
  }), false);
  assert.equal(validContextRequest({
    ...minimalRequest,
    route: {
      ...route,
      corridorSamples: [{ ...route.corridorSamples[0], system: 'gcj02' }],
    },
  }), false);
});

test('current context response validates composite scene and route invariants', async () => {
  const base = {
    contractVersion: 5,
    snapshotRevision: 1,
    contextId: 'ctx_1234567890abcdef12345678',
    generatedAt: '2026-07-14T02:00:00Z',
    expiresAt: '2026-07-14T02:10:00Z',
    sourceRevisions: { weather: 1, solar: 1, astronomy: 1, scene: 1, route: 1 },
    scene: 'lake',
    sceneContext: {
      primaryScene: 'inlandWater', facets: ['lake', 'reflectiveSurface'],
      activity: 'stationary', scores: { inlandWater: 55 }, reviewedOverride: false,
    },
    fingerprint: '1234567890abcdef12345678',
    stale: false,
    dataFreshness: { context: 'fresh', weather: 'fresh', weatherObservedAt: '2026-07-14T02:00:00Z' },
    weather: {
      condition: 'clear', temperatureCelsius: 20, windSpeedMps: 2, windDirectionDegrees: 90,
      precipitationMm: 0, visibilityKm: 20, cloudCoverPercent: 10, thunder: false,
      airQualityIndex: 42, airQualityCategory: '优', primaryPollutant: null,
      airQualityObservedAt: '2026-07-14T02:00:00Z', airQualityStale: false,
    },
    sunMoon: {
      dayPhase: 'day', sunElevationDegrees: 60, sunAzimuthDegrees: 180,
      moonPhase: 'fullMoon', moonIllumination: 0.5,
    },
    astronomy: {
      status: 'geometryOnly', astronomicalNight: false,
      moonAltitudeDegrees: 18, moonAzimuthDegrees: 110,
      moonriseAt: '2026-07-14T10:30:00Z', moonsetAt: '2026-07-14T22:10:00Z',
      moonPhase: 'fullMoon', moonIllumination: .5,
      galacticCenterAltitudeDegrees: -20, galacticCenterAzimuthDegrees: 240,
      galacticCenterWindow: {
        startAt: '2026-07-14T15:00:00Z', peakAt: '2026-07-14T17:00:00Z',
        endAt: '2026-07-14T19:00:00Z', peakAltitudeDegrees: 32,
      },
    },
    route: { mode: 'driving', stage: 'planned', active: false },
    events: [], allowedActions: [],
    manifest: { layoutMode: 'quiet', primaryEventId: null, secondaryEventIds: [], safetyEventIds: [] },
    shootingSessions: [],
    environment: null,
    facts: null,
    entries: [],
    refreshHints: {
      weather: 'ttl:600', airQuality: 'ttl:2700', solar: 'phase-boundary',
      astronomy: 'ttl:3600', opportunities: 'solar-or-weather-delta',
    },
  };
  base.environment = {
    scene: base.scene, dataFreshness: base.dataFreshness, weather: base.weather,
    sunMoon: base.sunMoon, astronomy: base.astronomy,
    route: base.route, sceneContext: base.sceneContext,
    allowedActions: base.allowedActions,
  };
  base.facts = { events: base.events, shootingSessions: base.shootingSessions };
  delete base.scene; delete base.dataFreshness; delete base.weather; delete base.sunMoon;
  delete base.astronomy;
  delete base.route; delete base.sceneContext; delete base.allowedActions;
  delete base.events; delete base.manifest; delete base.shootingSessions; delete base.fingerprint;
  const accepted = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(base), { status: 200 }),
  });
  assert.equal(accepted.ok, true);

  for (const malformed of [
    {
      ...base,
      environment: {
        ...base.environment,
        astronomy: { ...base.environment.astronomy, moonAltitudeDegrees: 120 },
      },
    },
    {
      ...base,
      sourceRevisions: { weather: 1, solar: 1, scene: 1, route: 1 },
    },
  ]) {
    const invalid = await forwardContextSnapshot({
      body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
      fetcher: async () => new Response(JSON.stringify(malformed), { status: 200 }),
    });
    assert.equal(invalid.ok, false);
  }

  const rejected = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      ...base, environment: { ...base.environment, route: { mode: 'driving', stage: 'planned', active: true } },
    }), { status: 200 }),
  });
  assert.equal(rejected.ok, false);
});

test('context import uses only the internal service token and bounded endpoint', async () => {
  let request;
  const result = await importContextDataset({
    body: { datasetType: 'spatialFeatures' },
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async (url, options) => {
      request = { url: url.toString(), options };
      return new Response(JSON.stringify({
        sourceId: 'reviewed-source', datasetType: 'spatialFeatures',
        importedCount: 2, enabled: false, cacheInvalidated: true,
      }), { status: 201, headers: { 'Content-Type': 'application/json' } });
    },
  });

  assert.equal(result.ok, true);
  assert.equal(request.url, 'http://context-service:8000/internal/v1/imports');
  assert.equal(request.options.headers['X-Internal-Service-Token'], 'internal-secret');
  assert.equal(request.options.body.includes('internal-secret'), false);
});

test('wildlife layer proxy sends only bounded location parameters and internal token', async () => {
  let request;
  const result = await fetchWildlifeLayers({
    latitude: 30.25,
    longitude: 120.15,
    radiusKm: 20,
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async (url, options) => {
      request = { url, options };
      return new Response(JSON.stringify(wildlifeLayerResponse), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  });

  assert.equal(result.ok, true);
  assert.equal(request.url.pathname, '/internal/v1/wildlife/layers');
  assert.equal(request.url.searchParams.get('latitude'), '30.25');
  assert.equal(request.url.searchParams.get('longitude'), '120.15');
  assert.equal(request.url.searchParams.get('radiusKm'), '20');
  assert.equal(request.options.headers['X-Internal-Service-Token'], 'internal-secret');
});

test('wildlife layer proxy rejects points, unknown fields and invalid source dates', async () => {
  for (const body of [
    {
      ...wildlifeLayerResponse,
      areas: [{
        ...wildlifeLayerResponse.areas[0],
        geometry: { type: 'Point', coordinates: [120.1, 30.1] },
      }],
    },
    { ...wildlifeLayerResponse, preciseCoordinates: true },
    {
      ...wildlifeLayerResponse,
      areas: [{
        ...wildlifeLayerResponse.areas[0],
        source: { ...wildlifeLayerResponse.areas[0].source, updatedAt: 'not-a-date' },
      }],
    },
  ]) {
    const result = await fetchWildlifeLayers({
      latitude: 30.25,
      longitude: 120.15,
      radiusKm: 20,
      serviceUrl: 'http://context-service:8000',
      internalToken: 'internal-secret',
      fetcher: async () => new Response(JSON.stringify(body), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    });
    assert.deepEqual(result, { ok: false, error: 'upstream_contract_mismatch' });
  }
});

test('context import converts validation details into a safe error', async () => {
  const result = await importContextDataset({
    body: { datasetType: 'spatialFeatures' },
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      detail: [{ loc: ['body', 'featureCollection'], msg: 'private upstream detail' }],
    }), { status: 422, headers: { 'Content-Type': 'application/json' } }),
  });

  assert.deepEqual(result, { ok: false, error: 'invalid_import' });
});

test('context snapshot refuses an incomplete current response', async () => {
  const result = await forwardContextSnapshot({
    body: {},
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      contractVersion: 2,
      contextId: 'ctx_1234567890abcdef12345678',
      generatedAt: '2026-07-14T02:00:00Z',
      expiresAt: '2026-07-14T02:15:00Z',
      scene: 'lake',
      fingerprint: '1234567890abcdef12345678',
      stale: false,
      events: [],
      manifest: { layoutMode: 'quiet', primaryEventId: null, secondaryEventIds: [], safetyEventIds: [] },
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });

  assert.deepEqual(result, { ok: false, error: 'upstream_contract_mismatch' });
});

test('a transport failure stays an availability failure, not a contract mismatch', async () => {
  for (const [label, fetcher] of [
    ['non-2xx', async () => new Response('{}', { status: 503 })],
    ['thrown fetcher', async () => { throw new Error('connection refused'); }],
  ]) {
    const result = await forwardContextSnapshot({
      body: { contractVersion: 5 },
      serviceUrl: 'http://context-service:8000',
      internalToken: 'internal-secret',
      fetcher,
    });
    assert.deepEqual(result, { ok: false, error: 'upstream_unavailable' }, label);
  }
});
