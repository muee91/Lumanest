import assert from 'node:assert/strict';
import test from 'node:test';

import { ProviderFactsService } from '../src/environment/provider-facts-service.mjs';

const instant = new Date('2026-08-06T00:00:00.000Z');
const json = (body) => new Response(JSON.stringify(body), {
  status: 200,
  headers: { 'Content-Type': 'application/json' },
});
const query = (providerId, latitude) => ({
  latitude,
  longitude: 120.15,
  radiusKm: 20,
  locale: 'zh-CN',
  observedAt: instant.toISOString(),
  providerIds: [providerId],
});

test('provider health and Prometheus distinguish ready, no-data and unavailable outcomes', async () => {
  let inaturalistCalls = 0;
  const service = new ProviderFactsService({
    now: () => instant,
    gbifBaseUrl: 'https://gbif.test',
    inaturalistBaseUrl: 'https://inaturalist.test',
    fetcher: async (input) => {
      const url = new URL(input);
      if (url.hostname === 'gbif.test') return json({ count: 7 });
      if (url.hostname === 'inaturalist.test') {
        inaturalistCalls += 1;
        if (inaturalistCalls === 1) return json({ total_results: 0, results: [] });
        throw new Error('upstream down');
      }
      throw new Error(`unexpected host ${url.hostname}`);
    },
  });

  await service.facts(query('gbif', 30.25));
  await service.facts(query('inaturalist', 30.25));
  await service.facts(query('inaturalist', 30.35));

  const health = service.healthSnapshot();
  const gbif = health.providers.find((item) => item.id === 'gbif');
  const inaturalist = health.providers.find((item) => item.id === 'inaturalist');
  assert.equal(gbif.readyTotal, 1);
  assert.equal(inaturalist.noDataTotal, 1);
  assert.equal(inaturalist.unavailableTotal, 1);
  assert.equal(inaturalist.requestTotal, 2);

  const metrics = service.toPrometheus();
  assert.match(metrics, /lumanest_provider_ready_total\{provider="gbif"\} 1/);
  assert.match(metrics, /lumanest_provider_no_data_total\{provider="inaturalist"\} 1/);
  assert.match(metrics, /lumanest_provider_unavailable_total\{provider="inaturalist"\} 1/);
  assert.match(metrics, /lumanest_provider_unconfigured_total\{provider="inaturalist"\} 0/);
  assert.match(metrics, /lumanest_provider_cache_coalesced_total 0/);
});
