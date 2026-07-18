import assert from 'node:assert/strict';
import test from 'node:test';

import {
  gcj02ToWgs84,
  resolveDeterministicDiscovery,
  validDeterministicDiscoveryRequest,
  wgs84ToGcj02,
} from '../src/discovery/deterministic.mjs';

const request = {
  missionType: 'routeConditions',
  focus: '环湖路线',
  locale: 'zh-cn',
  region: { latitude: 30.275, longitude: 120.125, radiusMeters: 5_000 },
  evidence: [],
};

test('deterministic discovery accepts only route and opening missions', () => {
  assert.equal(validDeterministicDiscoveryRequest(request), true);
  assert.equal(validDeterministicDiscoveryRequest({ ...request, missionType: 'popularPlaces' }), false);
  assert.equal(validDeterministicDiscoveryRequest({ ...request, modelOutput: true }), false);
});

test('WGS84 and GCJ-02 conversion round trips within five decimal places', () => {
  const gcj = wgs84ToGcj02(30.275, 120.125);
  const wgs = gcj02ToWgs84(gcj.latitude, gcj.longitude);
  assert.equal(Math.abs(wgs.latitude - 30.275) < .00001, true);
  assert.equal(Math.abs(wgs.longitude - 120.125) < .00001, true);
});

test('route conditions come only from the AMap traffic response', async () => {
  let requested;
  const result = await resolveDeterministicDiscovery({
    body: request,
    amapWebKey: 'amap-secret',
    now: () => new Date('2026-07-18T10:00:00Z'),
    fetcher: async (url) => {
      requested = url;
      return new Response(JSON.stringify({
        status: '1',
        trafficinfo: { description: '当前环湖道路整体畅通。' },
      }), { status: 200 });
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.candidates.length, 1);
  assert.equal(result.candidates[0].summary, '当前环湖道路整体畅通。');
  assert.equal(result.evidence[0].sourceId, 'amap-traffic');
  assert.equal(result.evidence[0].url.includes('amap-secret'), false);
  assert.equal(requested.pathname, '/v3/traffic/status/circle');
  assert.equal(requested.searchParams.get('key'), 'amap-secret');
});

test('opening mission admits only POIs with explicit AMap opening hours', async () => {
  const result = await resolveDeterministicDiscovery({
    body: { ...request, missionType: 'openingAndClosure', focus: '博物馆' },
    amapWebKey: 'amap-secret',
    now: () => new Date('2026-07-18T10:00:00Z'),
    fetcher: async () => new Response(JSON.stringify({
      status: '1',
      pois: [
        {
          name: '城市博物馆', location: '120.131000,30.281000',
          biz_ext: { open_time: '09:00-17:00' },
        },
        {
          name: '没有明确时间的展馆', location: '120.132000,30.282000',
          biz_ext: {},
        },
      ],
    }), { status: 200 }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.candidates.length, 1);
  assert.equal(result.candidates[0].title, '城市博物馆');
  assert.match(result.candidates[0].summary, /09:00-17:00/);
  assert.equal(result.evidence[0].sourceId, 'amap-poi');
});

test('provider failure or absent explicit fields creates no discovery fact', async () => {
  const failed = await resolveDeterministicDiscovery({
    body: request,
    amapWebKey: 'amap-secret',
    fetcher: async () => new Response('{}', { status: 502 }),
  });
  assert.deepEqual(failed, { ok: true, candidates: [], evidence: [] });
});
