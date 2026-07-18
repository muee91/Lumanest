import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function withServer(fetcher, run) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'key',
    projectId: 'project',
    serviceToken: 'service-token',
    amapWebKey: 'amap-key',
    fetcher,
    now: () => new Date('2026-07-18T09:10:00Z'),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('daily API authenticates, validates, caches and never sends coordinates to SunsetBot', async () => {
  let providerCalls = 0;
  const providerUrls = [];
  const fetcher = async (url) => {
    if (url.hostname === 'restapi.amap.com') {
      return json({
        status: '1',
        regeocode: { addressComponent: { province: '浙江省', city: '杭州市', district: '西湖区' } },
      });
    }
    providerCalls += 1;
    providerUrls.push(url);
    const eventDay = url.searchParams.get('event')?.endsWith('_2')
      ? '2026-07-19'
      : '2026-07-18';
    return json({
      status: 'ok',
      tb_event_time: `${eventDay} 18:59:55`,
      tb_quality: url.searchParams.get('model') === 'GFS' ? '.291<br>（小烧到中烧）' : '.429<br>（中烧）',
      tb_aod: '.244<br>（还不错）',
    });
  };
  await withServer(fetcher, async (baseUrl) => {
    const path = '/v1/sky-opportunities/daily?lat=30.2741&lon=120.1551&locale=zh-CN&focus=next';
    assert.equal((await fetch(`${baseUrl}${path}`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/v1/sky-opportunities?lat=x`, {
      headers: { Authorization: 'Bearer service-token' },
    })).status, 400);
    const first = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: 'Bearer service-token' },
    });
    assert.equal(first.status, 200);
    const body = await first.json();
    assert.equal(body.status, 'ok');
    assert.equal(body.todaySunset.data.summary.level, 'moderate');
    assert.equal(body.todaySunset.data.presentation.proactiveEligible, true);
    assert.equal('score' in body.todaySunset.data.summary, false);
    assert.equal('normalizedScore' in body.todaySunset.data.summary, false);
    assert.equal('confidenceScore' in body.todaySunset.data.summary, false);
    assert.equal('aod' in body.todaySunset.data.atmosphere, false);
    assert.equal('score' in body.todaySunset.data.models[0], false);
    assert.equal('aod' in body.todaySunset.data.models[0], false);
    assert.equal(body.tomorrowSunset.status, 'unavailable');
    assert.equal(providerCalls, 4);
    await fetch(`${baseUrl}${path}`, { headers: { Authorization: 'Bearer service-token' } });
    assert.equal(providerCalls, 4);
  });
  assert.equal(providerUrls.every((url) => url.hostname === 'sunsetbot.top'), true);
  assert.equal(providerUrls.every((url) => !url.search.includes('30.2741') && !url.search.includes('120.1551')), true);
  assert.equal(providerUrls.every((url) => ['GFS', 'EC'].includes(url.searchParams.get('model'))), true);
  assert.equal(providerUrls.every((url) => /^\d+$/.test(url.searchParams.get('query_id'))), true);
});

test('daily API requires an explicit focus rather than silently preserving the old default', async () => {
  await withServer(async () => json({}), async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/sky-opportunities/daily?lat=30.2741&lon=120.1551`,
      { headers: { Authorization: 'Bearer service-token' } },
    );
    assert.equal(response.status, 400);
  });
});

test('provider failure returns 200 unavailable and leaves metrics observable', async () => {
  const fetcher = async (url) => url.hostname === 'restapi.amap.com'
    ? json({ status: '1', regeocode: { addressComponent: { city: '杭州市', province: '浙江省' } } })
    : json({ error: 'down' }, 503);
  await withServer(fetcher, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/sky-opportunities?lat=30.2&lon=120.1&event=sunset&dayOffset=0`,
      { headers: { Authorization: 'Bearer service-token' } },
    );
    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).data, null);
    const metrics = await fetch(`${baseUrl}/metrics`, {
      headers: { Authorization: 'Bearer service-token' },
    });
    assert.match(await metrics.text(), /sunsetbot_request_failure_total [1-9]/);
  });
});
