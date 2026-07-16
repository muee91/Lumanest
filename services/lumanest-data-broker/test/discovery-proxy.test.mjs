import assert from 'node:assert/strict';
import test from 'node:test';

import {
  forwardDiscovery,
  validDiscoveryRequest,
  validDiscoveryResponse,
} from '../src/discovery/proxy.mjs';

const request = {
  contractVersion: 1,
  coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
  locale: 'zh-CN',
  focus: 'photography',
};

const ready = {
  contractVersion: 1,
  status: 'ready',
  generatedAt: '2026-07-20T02:00:00Z',
  expiresAt: '2026-07-20T08:00:00Z',
  retryAfterSeconds: null,
  items: [{
    id: 'west-lake-viewpoint',
    kind: 'candidate_viewpoint',
    title: '湖畔观景点',
    subtitle: '有来源证据的候选观景点',
    placeStatus: 'candidate',
    coordinate: { latitude: 30.249, longitude: 120.151, system: 'wgs84' },
    distanceMeters: 180,
    address: '杭州',
    startsAt: null,
    endsAt: null,
    evidence: [{
      publisher: '审核目录',
      title: '西湖周边地点',
      url: 'https://example.test/places/west-lake',
      observedAt: '2026-07-20T01:00:00Z',
    }],
  }],
};

test('discovery request has an exact privacy-preserving public contract', () => {
  assert.equal(validDiscoveryRequest(request), true);
  for (const forbidden of ['deviceId', 'userId', 'preferences', 'searchQuery', 'fingerprint']) {
    assert.equal(validDiscoveryRequest({ ...request, [forbidden]: 'forbidden' }), false);
  }
  assert.equal(validDiscoveryRequest({ ...request, coordinate: {
    ...request.coordinate, system: 'gcj02',
  } }), false);
});

test('discovery proxy forwards only the bounded discovery contract', async () => {
  let captured;
  const result = await forwardDiscovery({
    body: request,
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify(ready), {
        status: 200, headers: { 'Content-Type': 'application/json' },
      });
    },
  });
  assert.deepEqual(result, { ok: true, body: ready });
  assert.equal(captured.url.toString(), 'http://discovery-api:8001/internal/v1/discover');
  assert.equal(captured.options.headers['X-Internal-Service-Token'], 'internal-discovery-token');
  assert.deepEqual(JSON.parse(captured.options.body), {
    contractVersion: 1,
    coordinate: request.coordinate,
    locale: 'zh-CN',
    focus: 'photography',
  });
  assert.equal(captured.options.body.includes('internal-discovery-token'), false);
});

test('discovery response rejects schema expansion and pending response stays empty', () => {
  assert.equal(validDiscoveryResponse(ready), true);
  assert.equal(validDiscoveryResponse({ ...ready, userLocation: 'forbidden' }), false);
  assert.equal(validDiscoveryResponse({
    ...ready,
    status: 'pending',
    expiresAt: null,
    retryAfterSeconds: 30,
    items: [],
  }), true);
  assert.equal(validDiscoveryResponse({
    ...ready,
    status: 'pending',
    expiresAt: null,
    retryAfterSeconds: null,
    items: [],
  }), false);
});

test('discovery proxy hides upstream errors and malformed bodies', async () => {
  const malformed = await forwardDiscovery({
    body: request,
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    fetcher: async () => new Response(JSON.stringify({ ...ready, evidence: [] }), { status: 200 }),
  });
  assert.deepEqual(malformed, { ok: false, error: 'upstream_unavailable' });
  const missing = await forwardDiscovery({ body: request, serviceUrl: '', internalToken: '' });
  assert.deepEqual(missing, { ok: false, error: 'not_configured' });
});
