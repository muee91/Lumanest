import assert from 'node:assert/strict';
import test from 'node:test';

import {
  forwardContextSnapshot,
  importContextDataset,
  isLegacyContextRequest,
  validContextRequest,
} from '../src/context/proxy.mjs';

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
