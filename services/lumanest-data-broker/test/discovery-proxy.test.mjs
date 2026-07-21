import assert from 'node:assert/strict';
import test from 'node:test';

import {
  forwardDiscovery,
  validDiscoveryRequest,
  validDiscoveryResponse,
} from '../src/discovery/proxy.mjs';
import {
  nearbyPrewarmRequest,
  prewarmNearbyDiscovery,
  prewarmRegionBriefDiscovery,
  regionBriefPrewarmRequests,
} from '../src/discovery/prewarm.mjs';

const request = {
  activationType: 'user_manual',
  missionType: 'humanityEvents',
  focus: '早市 夜市 展览',
  locale: 'zh-CN',
  region: { latitude: 30.25, longitude: 120.15, radiusMeters: 5000 },
  timeRange: { startsAt: '2026-07-18T00:00:00Z', endsAt: '2026-07-25T00:00:00Z' },
  routeCorridor: null,
  interests: ['humanityStreet'],
};

const ready = {
  missionType: 'humanityEvents',
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
  assert.equal(validDiscoveryRequest({ ...request, region: {
    ...request.region, radiusMeters: 50,
  } }), false);
  assert.equal(validDiscoveryRequest({ ...request, missionType: 'routeConditions' }), false);
});

test('discovery proxy forwards only the bounded discovery contract', async () => {
  let captured;
  const result = await forwardDiscovery({
    body: request,
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    sourcePolicies: [
      { id: 'official-source', version: '2026-07', enabled: true, apiKey: 'must-not-forward' },
      { id: 'revoked-source', version: '2026-06', enabled: false },
    ],
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
    ...request,
    sourcePolicies: [{ id: 'official-source', version: '2026-07' }],
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

test('location refresh prewarm resolves a city transiently and only queues coarse discovery work', async () => {
  const calls = [];
  const result = await prewarmNearbyDiscovery({
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    locale: 'zh-CN',
    amapWebKey: 'amap-key',
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    sourcePolicies: [{ id: 'official-source', version: '2026-07', enabled: true }],
    searchEnabled: true,
    now: () => new Date('2026-07-19T00:00:00Z'),
    fetcher: async (url, options = {}) => {
      calls.push({ url, options });
      if (url.hostname === 'restapi.amap.com') {
        return new Response(JSON.stringify({
          status: '1', regeocode: { addressComponent: { city: '杭州市', province: '浙江省' } },
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        missionType: 'popularPlaces', status: 'pending', generatedAt: '2026-07-19T00:00:00Z',
        expiresAt: null, retryAfterSeconds: 30, items: [],
      }), { status: 202, headers: { 'Content-Type': 'application/json' } });
    },
  });
  assert.deepEqual(result, { queued: true, status: 'pending' });
  assert.equal(calls.length, 2);
  const queued = JSON.parse(calls[1].options.body);
  assert.equal(queued.activationType, 'foreground_opportunistic');
  assert.equal(queued.missionType, 'popularPlaces');
  assert.equal(queued.focus, '杭州周边近期值得了解的摄影地点与观景地');
  assert.equal(queued.region.radiusMeters, 15_000);
  assert.deepEqual(queued.sourcePolicies, [{ id: 'official-source', version: '2026-07' }]);
});

test('location refresh prewarm can be disabled before any external request', async () => {
  let calls = 0;
  const result = await prewarmNearbyDiscovery({
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    locale: 'zh-CN', amapWebKey: 'amap-key', serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token', sourcePolicies: [{ id: 'source', version: '1', enabled: true }],
    enabled: false, searchEnabled: true, fetcher: async () => { calls += 1; throw new Error('must not request'); },
  });
  assert.deepEqual(result, { queued: false, reason: 'not_configured' });
  assert.equal(calls, 0);
  assert.equal(nearbyPrewarmRequest({
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' }, locale: 'zh-CN', city: '',
  }), null);
});

test('context refresh prewarms the complete regional brief mission bundle', async () => {
  const queuedMissions = [];
  const result = await prewarmRegionBriefDiscovery({
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    locale: 'zh-CN',
    amapWebKey: 'amap-key',
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    sourcePolicies: [{ id: 'official-source', version: '2026-07', enabled: true }],
    searchEnabled: true,
    now: () => new Date('2026-07-19T00:00:00Z'),
    fetcher: async (url, options = {}) => {
      if (url.hostname === 'restapi.amap.com') {
        return new Response(JSON.stringify({
          status: '1', regeocode: { addressComponent: { city: '杭州市', province: '浙江省' } },
        }), { status: 200 });
      }
      const body = JSON.parse(options.body);
      queuedMissions.push(body.missionType);
      return new Response(JSON.stringify({
        missionType: body.missionType,
        status: 'pending',
        generatedAt: '2026-07-19T00:00:00Z',
        expiresAt: null,
        retryAfterSeconds: 30,
        items: [],
      }), { status: 202, headers: { 'Content-Type': 'application/json' } });
    },
  });

  assert.deepEqual(result, { queued: true, acceptedMissions: 8 });
  assert.deepEqual(queuedMissions.sort(), [
    'culturalEtiquette',
    'hiddenPlaces',
    'humanityEvents',
    'localFoodAndSpecialties',
    'localStories',
    'openingAndClosure',
    'popularPlaces',
    'seasonalSignals',
  ]);
  const requests = regionBriefPrewarmRequests({
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    locale: 'zh-CN',
    city: '杭州',
    now: new Date('2026-07-19T00:00:00Z'),
  });
  assert.equal(requests.length, 8);
  assert.equal(requests.every((item) => item.activationType === 'foreground_opportunistic'), true);
});
