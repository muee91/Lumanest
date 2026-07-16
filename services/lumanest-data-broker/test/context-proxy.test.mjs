import assert from 'node:assert/strict';
import test from 'node:test';

import {
  forwardContextSnapshot,
  fetchWildlifeLayers,
  importContextDataset,
  isLegacyContextRequest,
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
  contractVersion: 2,
  coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
  observedAt: '2026-07-14T10:00:00+08:00',
  locale: 'zh-CN',
  intent: 'photography',
  route: { mode: 'none', stage: 'none' },
};

test('public context validator accepts canonical input and complete legacy input only', () => {
  assert.equal(validContextRequest(minimalRequest), true);
  assert.equal(validContextRequest({ ...minimalRequest, contractVersion: 3 }), true);
  assert.equal(isLegacyContextRequest(minimalRequest), false);
  const legacy = {
    ...minimalRequest,
    evidence: { urban: false, waterBody: false, mountainous: false, aridLand: false, settlement: false },
    weather: {
      observedAt: '2026-07-14T10:00:00+08:00', condition: 'clear', windSpeedMps: 2,
      precipitationMm: 0, visibilityKm: 20, thunder: false, stale: false,
      temperatureCelsius: 26, windDirectionDegrees: 90, cloudCoverPercent: null,
    },
    solar: { dayPhase: 'day', elevationDegrees: 60, azimuthDegrees: 180 },
  };
  assert.equal(validContextRequest(legacy), true);
  assert.equal(isLegacyContextRequest(legacy), true);
  assert.equal(validContextRequest({ ...minimalRequest, weather: legacy.weather }), false);
  assert.equal(validContextRequest({ ...minimalRequest, deviceId: 'forbidden' }), false);
});

test('route invariant rejects none/active and driving/none but accepts planned/active/paused', () => {
  assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'none', stage: 'active' } }), false);
  assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'driving', stage: 'none' } }), false);
  for (const stage of ['planned', 'active', 'paused']) {
    assert.equal(validContextRequest({ ...minimalRequest, route: { mode: 'driving', stage } }), true);
  }
});

test('V3 accepts only bounded ordered WGS84 corridor samples with an opaque route ID', () => {
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
  assert.equal(validContextRequest({ ...minimalRequest, contractVersion: 3, route }), true);
  assert.equal(validContextRequest({ ...minimalRequest, route }), false);
  assert.equal(validContextRequest({
    ...minimalRequest, contractVersion: 3,
    route: { ...route, routeId: undefined },
  }), false);
  assert.equal(validContextRequest({
    ...minimalRequest, contractVersion: 3,
    route: { ...route, corridorSamples: [...route.corridorSamples].reverse() },
  }), false);
  assert.equal(validContextRequest({
    ...minimalRequest, contractVersion: 3,
    route: {
      ...route,
      corridorSamples: [{ ...route.corridorSamples[0], system: 'gcj02' }],
    },
  }), false);
});

test('context snapshot rejects a response where active disagrees with stage', async () => {
  const base = {
    contractVersion: 2,
    contextId: 'ctx_1234567890abcdef12345678',
    generatedAt: '2026-07-14T02:00:00Z',
    expiresAt: '2026-07-14T02:15:00Z',
    scene: 'lake',
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
    route: { mode: 'driving', stage: 'planned', active: false },
    events: [],
    allowedActions: [],
    manifest: { layoutMode: 'quiet', primaryEventId: null, secondaryEventIds: [], safetyEventIds: [] },
  };

  const ok = await forwardContextSnapshot({
    body: {},
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(base), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(ok.ok, true);

  const v3 = {
    ...base, contractVersion: 3, allowedActions: ['openExplore', 'openShootingWindow'], opportunities: [{
      id: 'photo-reflection-2026071410', kind: 'reflection',
      startAt: '2026-07-14T02:00:00Z', peakAt: '2026-07-14T02:15:00Z', endAt: '2026-07-14T02:35:00Z',
      score: 74, confidence: .76, geoScope: 'point', directionDegrees: null,
      evidence: [{ label: '风速', value: '1.5m/s' }], primaryAction: 'openExplore',
      fallbackAction: 'openShootingWindow', equipmentHints: ['偏振镜'],
    }],
  };
  const acceptedV3 = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(v3), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(acceptedV3.ok, true);

  const v3WithReviewedTarget = {
    ...v3,
    opportunities: [{ ...v3.opportunities[0], target: {
      id: 'target_0123456789abcdef01234567', name: '东岸观景台', kind: 'lakeshore',
      coordinate: { latitude: 30.251, longitude: 120.151, system: 'wgs84' },
      arrivalDeadline: '2026-07-14T02:00:00Z',
    } }],
  };
  const acceptedTarget = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(v3WithReviewedTarget), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(acceptedTarget.ok, true);

  const v3WithCorridor = {
    ...v3,
    opportunities: [{ ...v3.opportunities[0], geoScope: 'regional', corridor: {
      routeId: 'client_route_hash_123',
      observations: [{
        progress: .5, expectedAt: '2026-07-14T02:30:00Z', condition: 'clear',
        cloudCoverPercent: 25, windSpeedMps: 1.5, precipitationMm: 0,
        thunder: false, sunAzimuthDegrees: 240,
        opportunityId: v3.opportunities[0].id,
      }],
    } }],
  };
  const acceptedCorridor = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(v3WithCorridor), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(acceptedCorridor.ok, true);

  const rejectedPointCorridor = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      ...v3WithCorridor,
      opportunities: [{ ...v3WithCorridor.opportunities[0], geoScope: 'point' }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });
  assert.equal(rejectedPointCorridor.ok, false);

  const rejectedTarget = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      ...v3WithReviewedTarget,
      opportunities: [{ ...v3WithReviewedTarget.opportunities[0], target: {
        ...v3WithReviewedTarget.opportunities[0].target,
        coordinate: { latitude: 30.251, longitude: 120.151, system: 'gcj02' },
      } }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });
  assert.equal(rejectedTarget.ok, false);

  const unapprovedOpportunityAction = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({ ...v3, allowedActions: [] }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(unapprovedOpportunityAction.ok, false);

  const astronomyEvent = {
    id: 'astronomy-123456789abc', channel: 'opportunity', source: 'astronomyCatalog',
    observedAt: '2026-07-14T01:00:00Z', expiresAt: '2026-07-14T04:00:00Z',
    confidence: 1, geoScope: 'regional', severity: 'info', allowedAction: 'openAuthority',
    title: '英仙座流星雨极大期', sourceUrl: 'https://science.nasa.gov/meteor-showers/',
  };
  const astronomy = {
    ...base,
    events: [astronomyEvent],
    allowedActions: ['openAuthority'],
    manifest: {
      layoutMode: 'opportunity', primaryEventId: astronomyEvent.id,
      secondaryEventIds: [], safetyEventIds: [],
    },
  };
  const acceptedAstronomy = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(astronomy), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }),
  });
  assert.equal(acceptedAstronomy.ok, true);

  const rejectedHttpAuthority = await forwardContextSnapshot({
    body: {}, serviceUrl: 'http://context-service:8000', internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      ...astronomy,
      events: [{ ...astronomyEvent, sourceUrl: 'http://example.test/catalog' }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });
  assert.deepEqual(rejectedHttpAuthority, { ok: false, error: 'upstream_unavailable' });

  const bad = await forwardContextSnapshot({
    body: {},
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify({
      ...base, route: { mode: 'driving', stage: 'planned', active: true },
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });
  assert.deepEqual(bad, { ok: false, error: 'upstream_unavailable' });
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
    assert.deepEqual(result, { ok: false, error: 'upstream_unavailable' });
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

test('context snapshot refuses an incomplete internal v2 response', async () => {
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

  assert.deepEqual(result, { ok: false, error: 'upstream_unavailable' });
});
