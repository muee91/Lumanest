import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

function upstream(product) {
  return new Response(JSON.stringify({
    product,
    init: '2026071900',
    dataseries: [{ timepoint: product === 'two' ? 204 : 3, cloudcover: 2 }],
  }), { headers: { 'Content-Type': 'text/plain' } });
}

async function withServer(run, { settings, fetcher = async (url) => upstream(url.searchParams.get('product')) } = {}) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'key',
    projectId: 'project',
    serviceToken: 'service-token',
    amapWebKey: 'amap-key',
    settings,
    fetcher,
    now: () => new Date('2026-07-19T06:00:00Z'),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function request(baseUrl, body, { token = 'service-token' } = {}) {
  return fetch(`${baseUrl}/v1/weather/7timer`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

test('7Timer API authenticates, validates and returns all supported products', async () => {
  await withServer(async (baseUrl) => {
    assert.equal((await fetch(`${baseUrl}/v1/weather/7timer`, { method: 'POST' })).status, 401);
    assert.equal((await request(baseUrl, {
      latitude: 91, longitude: 120, product: 'astro',
    })).status, 400);
    assert.equal((await request(baseUrl, {
      latitude: 30, longitude: 120, product: 'astro', extra: true,
    })).status, 400);
    for (const product of ['astro', 'meteo', 'two']) {
      const response = await request(baseUrl, { latitude: 30.274, longitude: 120.155, product });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.source, '7timer');
      assert.equal(body.product, product);
      assert.equal(Array.isArray(body.points), true);
    }
    const metrics = await fetch(`${baseUrl}/metrics`, { headers: { Authorization: 'Bearer service-token' } });
    const text = await metrics.text();
    assert.match(text, /seven_timer_request_success_total\{product="astro"\} 1/);
    assert.match(text, /seven_timer_request_duration_p95_ms\{product="two"\} \d+/);
  });
});

test('7Timer API distinguishes disabled and unavailable providers', async () => {
  await withServer(async (baseUrl) => {
    const response = await request(baseUrl, { latitude: 30, longitude: 120, product: 'astro' });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'seven_timer_disabled' });
  }, { settings: { sevenTimerProviderEnabled: false } });

  await withServer(async (baseUrl) => {
    const response = await request(baseUrl, { latitude: 30, longitude: 120, product: 'astro' });
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: 'seven_timer_unavailable' });
  }, {
    settings: { sevenTimerMaxAttempts: 1 },
    fetcher: async () => new Response('down', { status: 503 }),
  });
});
