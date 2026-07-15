import assert from 'node:assert/strict';
import test from 'node:test';

import {
  fetchAmapSceneEvidence,
  parseAmapSceneEvidence,
  wgs84ToGcj02,
} from '../src/context/amap-evidence.mjs';

test('converts canonical WGS84 to GCJ-02 only for the AMap request', () => {
  const converted = wgs84ToGcj02({ latitude: 31.2304, longitude: 121.4737 });
  assert.ok(Math.abs(converted.latitude - 31.22846) < 0.0001);
  assert.ok(Math.abs(converted.longitude - 121.47822) < 0.0001);
  assert.deepEqual(
    wgs84ToGcj02({ latitude: 35.6762, longitude: 139.6503 }),
    { latitude: 35.6762, longitude: 139.6503 },
  );
});

test('parses five scene evidence classes without returning source entities', () => {
  const body = (name, type = '风景名胜') => ({
    status: '1',
    regeocode: {
      addressComponent: { citycode: '0571' },
      aois: [{ name, type }],
      pois: Array.from({ length: 12 }, (_, index) => ({ name: `地点${index}`, type })),
    },
  });
  assert.equal(parseAmapSceneEvidence(body('西湖')).waterBody, true);
  assert.equal(parseAmapSceneEvidence(body('天山 山峰')).mountainous, true);
  assert.equal(parseAmapSceneEvidence(body('雅丹戈壁')).aridLand, true);
  assert.equal(parseAmapSceneEvidence(body('传统古村')).settlement, true);
  const city = parseAmapSceneEvidence(body('城市中心', '商务住宅'));
  assert.equal(city.urban, true);
  assert.deepEqual(Object.keys(city).sort(), [
    'aridLand', 'mountainous', 'settlement', 'urban', 'waterBody',
  ]);
});

test('fetches only bounded AMap regeo parameters and returns sanitized evidence', async () => {
  let request;
  const result = await fetchAmapSceneEvidence({
    coordinate: { latitude: 31.2304, longitude: 121.4737 },
    apiKey: 'test-amap-key',
    fetcher: async (url, options) => {
      request = { url, options };
      return new Response(JSON.stringify({
        status: '1',
        regeocode: {
          addressComponent: { citycode: '021' },
          aois: [{ name: '城市中心', type: '商务住宅' }],
          pois: Array.from({ length: 10 }, () => ({ name: '地点', type: '商务住宅' })),
        },
      }), { status: 200 });
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.evidence.urban, true);
  assert.equal(request.url.pathname, '/v3/geocode/regeo');
  assert.match(request.url.searchParams.get('location'), /^121\.478/);
  assert.equal(request.url.searchParams.get('radius'), '3000');
  assert.equal(request.url.searchParams.get('extensions'), 'all');
  assert.equal(request.url.searchParams.get('key'), 'test-amap-key');
  assert.equal(Object.hasOwn(result.evidence, 'pois'), false);
  assert.equal(Object.hasOwn(result.evidence, 'coordinate'), false);
});
