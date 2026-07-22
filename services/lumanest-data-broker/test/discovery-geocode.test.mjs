import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseAmapRegionIdentity,
  regionIdentityQuery,
  resolvePlace,
  validResolvePlaceRequest,
} from '../src/discovery/geocode.mjs';

const request = {
  query: '飞来寺观景台', addressHint: '云南省迪庆州德钦县',
  region: { latitude: 28.475, longitude: 98.875, radiusMeters: 50_000 }, locale: 'zh-CN',
};

test('resolve-place accepts only the bounded internal contract', () => {
  assert.equal(validResolvePlaceRequest(request), true);
  assert.equal(validResolvePlaceRequest({ ...request, url: 'https://internal.test' }), false);
  assert.equal(validResolvePlaceRequest({ ...request, region: { ...request.region, radiusMeters: 60_000 } }), false);
});

test('resolve-place converts the unique nearby AMap POI to WGS84 and returns evidence', async () => {
  const result = await resolvePlace({
    body: request, amapWebKey: 'amap-secret', now: () => new Date('2026-07-19T08:00:00Z'),
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
    body: request, amapWebKey: 'amap-secret',
    fetcher: async () => new Response(JSON.stringify({ status: '1', pois: [
      { name: '飞来寺观景台', address: '德钦县', location: '98.87634,28.44512' },
      { name: '飞来寺观景台', address: '德钦县', location: '98.87734,28.44612' },
    ] }), { status: 200 }),
  });
  assert.deepEqual(result, { status: 'ambiguous' });
});

test('region identity prefers a containing AOI and retains administrative search names', () => {
  const parsed = parseAmapRegionIdentity({
    status: '1', regeocode: {
      addressComponent: { township: '北山街道', district: '西湖区', city: '杭州市', province: '浙江省' },
      aois: [{ name: '西湖风景名胜区', type: '风景名胜;旅游景点', distance: '20' }],
      pois: [{ name: '北山街历史文化街区', type: '地名地址;街道级地名', distance: '120' }],
    },
  });
  assert.equal(parsed?.displayName, '西湖风景名胜区');
  assert.deepEqual(parsed?.searchNames, ['西湖风景名胜区', '北山街历史文化街区', '北山街道', '西湖区', '杭州市']);
});

test('the internal region identity mode uses reverse geocoding at the coarse worker point', async () => {
  const result = await resolvePlace({
    body: { ...request, query: regionIdentityQuery, addressHint: null }, amapWebKey: 'amap-secret',
    regionIdentityCache: new Map(),
    fetcher: async (url) => {
      assert.equal(url.pathname, '/v3/geocode/regeo');
      assert.equal(url.searchParams.get('radius'), '3000');
      return new Response(JSON.stringify({ status: '1', regeocode: {
        addressComponent: { district: '西湖区', city: '杭州市', province: '浙江省' }, aois: [], pois: [],
      } }));
    },
  });
  assert.equal(result.status, 'resolved');
  assert.deepEqual(result.region.searchNames, ['西湖区', '杭州市', '浙江省']);
});

test('region identity cache prevents repeated reverse-geocoding for the same coarse cell', async () => {
  const cache = new Map();
  let calls = 0;
  const body = {
    ...request,
    query: regionIdentityQuery,
    addressHint: null,
    region: { latitude: 30.275, longitude: 120.125, radiusMeters: 5_000 },
  };
  const fetcher = async () => {
    calls += 1;
    return new Response(JSON.stringify({ status: '1', regeocode: {
      addressComponent: { district: '西湖区', city: '杭州市', province: '浙江省' }, aois: [], pois: [],
    } }));
  };

  const first = await resolvePlace({
    body, amapWebKey: 'amap-secret', fetcher, regionIdentityCache: cache,
    now: () => new Date('2026-07-22T00:00:00Z'),
  });
  const second = await resolvePlace({
    body, amapWebKey: 'amap-secret', fetcher, regionIdentityCache: cache,
    now: () => new Date('2026-07-22T01:00:00Z'),
  });

  assert.equal(calls, 1);
  assert.deepEqual(second, first);
});
