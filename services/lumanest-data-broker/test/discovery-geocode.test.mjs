import assert from 'node:assert/strict';
import test from 'node:test';

import { resolvePlace, validResolvePlaceRequest } from '../src/discovery/geocode.mjs';

const request = {
  query: '飞来寺观景台',
  addressHint: '云南省迪庆州德钦县',
  region: { latitude: 28.475, longitude: 98.875, radiusMeters: 50_000 },
  locale: 'zh-CN',
};

test('resolve-place accepts only the bounded internal contract', () => {
  assert.equal(validResolvePlaceRequest(request), true);
  assert.equal(validResolvePlaceRequest({ ...request, url: 'https://internal.test' }), false);
  assert.equal(validResolvePlaceRequest({ ...request, region: { ...request.region, radiusMeters: 60_000 } }), false);
});

test('resolve-place converts the unique nearby AMap POI to WGS84 and returns evidence', async () => {
  const result = await resolvePlace({
    body: request,
    amapWebKey: 'amap-secret',
    now: () => new Date('2026-07-19T08:00:00Z'),
    fetcher: async (url) => {
      assert.equal(url.pathname, '/v3/place/text');
      assert.equal(url.searchParams.get('keywords'), '飞来寺观景台');
      return new Response(JSON.stringify({ status: '1', pois: [{
        name: '飞来寺观景台', address: '云南省迪庆州德钦县', location: '98.87634,28.44512',
      }] }), { status: 200 });
    },
  });
  assert.equal(result.status, 'resolved');
  assert.equal(result.place.name, '飞来寺观景台');
  assert.equal(result.evidence.sourceId, 'amap-poi');
  assert.match(result.evidence.snippet, /坐标：/);
});

test('resolve-place rejects equally plausible results instead of choosing the first', async () => {
  const result = await resolvePlace({
    body: request,
    amapWebKey: 'amap-secret',
    fetcher: async () => new Response(JSON.stringify({ status: '1', pois: [
      { name: '飞来寺观景台', address: '德钦县', location: '98.87634,28.44512' },
      { name: '飞来寺观景台', address: '德钦县', location: '98.87734,28.44612' },
    ] }), { status: 200 }),
  });
  assert.deepEqual(result, { status: 'ambiguous' });
});
