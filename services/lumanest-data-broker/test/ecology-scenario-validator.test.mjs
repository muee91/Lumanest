import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertEcologyResponse,
  evaluateEcologyReachability,
  runEcologyValidation,
} from '../scripts/validate-ecology-providers.mjs';

const instant = new Date('2026-08-06T00:00:00.000Z');

function response({ gbif = 'ready', inaturalist = 'noData', leak = null } = {}) {
  const provider = (id, status, kind) => ({
    id,
    category: 'wildlife',
    status,
    observedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
    source: status === 'ready' ? {
      id: `${id}-source`, title: id, publisher: id,
      url: `https://${id}.example/reference`, license: 'open', version: 'v1',
    } : null,
    signals: status === 'ready' ? [{
      id: `${id}-signal`, kind, category: 'wildlife', title: id,
      summary: 'bounded aggregate only', verification: 'reference',
      observedAt: instant.toISOString(),
      expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
      sourceUrl: `https://${id}.example/reference`,
      ...(leak == null ? {} : leak),
    }] : [],
    message: status === 'ready' ? null : 'bounded state',
  });
  return {
    contractVersion: 1,
    requestedCoordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    radiusKm: 20,
    generatedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
    status: gbif === 'ready' || inaturalist === 'ready' ? 'partial' : 'unavailable',
    cacheStatus: 'miss',
    providers: [
      provider('gbif', gbif, 'historicalOccurrenceInventory'),
      provider('inaturalist', inaturalist, 'recentCommunityBirdSummary'),
    ],
  };
}

test('scenario validator reports only aggregate provider outcomes', async () => {
  const queries = [];
  const service = {
    facts: async (query) => {
      queries.push(query);
      return response();
    },
  };
  const report = await runEcologyValidation({
    service,
    scenarios: [
      { id: 'a', label: '场景 A', latitude: 30.1, longitude: 120.1, radiusKm: 20 },
      { id: 'b', label: '场景 B', latitude: 37.3, longitude: 97.3, radiusKm: 30 },
    ],
    now: () => instant,
  });
  assert.equal(report.ok, true);
  assert.deepEqual(queries.map((item) => item.providerIds), [
    ['gbif', 'inaturalist'],
    ['gbif', 'inaturalist'],
  ]);
  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('latitude'), false);
  assert.equal(serialized.includes('longitude'), false);
  assert.equal(serialized.includes('30.1'), false);
  assert.equal(report.privacy.coordinatesPrinted, false);
});

test('scenario validator rejects leaked observation payloads', () => {
  assert.throws(
    () => assertEcologyResponse(response({ leak: { geojson: { coordinates: [120.1, 30.2] } } })),
    /privacy_violation/,
  );
});

test('reachability gate distinguishes no-data from upstream failure', () => {
  const healthy = evaluateEcologyReachability([
    response({ gbif: 'ready', inaturalist: 'noData' }),
    response({ gbif: 'noData', inaturalist: 'ready' }),
  ], 0.5);
  assert.equal(healthy.ok, true);

  const failed = evaluateEcologyReachability([
    response({ gbif: 'unavailable', inaturalist: 'ready' }),
    response({ gbif: 'unavailable', inaturalist: 'noData' }),
  ], 0.5);
  assert.equal(failed.ok, false);
  assert.deepEqual(failed.failures, ['gbif']);
});
