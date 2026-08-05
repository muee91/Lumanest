import assert from 'node:assert/strict';
import test from 'node:test';

import { buildRouteCorridorIntelligence } from '../src/context/route-corridor-intelligence.mjs';

test('builds bounded route corridor evidence without coordinates or raw notice text', () => {
  const body = {
    samples: [
      { progress: 0, expectedAt: '2026-08-05T06:00:00Z' },
      { progress: 1, expectedAt: '2026-08-05T07:00:00Z' },
    ],
  };
  const result = buildRouteCorridorIntelligence({
    body,
    generatedAt: new Date('2026-08-05T05:55:00Z'),
    providerResults: [
      {
        providers: [
          {
            id: 'osm', status: 'ready',
            source: { id: 'osm', title: 'OSM', publisher: 'OSM contributors', url: 'https://www.openstreetmap.org/copyright' },
            signals: [{ id: 'map-1', kind: 'outdoorMapInventory', verification: 'reference', attributes: { parking: 2, fuel: 1, viewpoint: 3 } }],
          },
          {
            id: 'officialNotices', status: 'ready',
            source: { id: 'official', title: 'Official', publisher: 'Authority', url: 'https://example.gov/notices' },
            signals: [{ id: 'notice-1', kind: 'roadClosure', verification: 'authoritative', title: 'secret raw title', summary: 'secret raw detail' }],
          },
        ],
      },
      { providers: [{ id: 'osm', status: 'noData', signals: [] }, { id: 'officialNotices', status: 'noData', signals: [] }] },
    ],
  });
  assert.equal(result.coverage, 'full');
  assert.equal(result.segments[0].facilities.parking, 2);
  assert.equal(result.segments[0].restrictions.status, 'present');
  assert.equal(result.segments[1].restrictions.status, 'noneObserved');
  const serialized = JSON.stringify(result);
  assert.doesNotMatch(serialized, /latitude|longitude|secret raw|routeId/);
  assert.match(serialized, /notice-1/);
});
