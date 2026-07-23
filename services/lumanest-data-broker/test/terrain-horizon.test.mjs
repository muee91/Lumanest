import assert from 'node:assert/strict';
import test from 'node:test';

import { fetchTerrainHorizon } from '../src/environment/terrain-horizon.mjs';

function payload() {
  return {
    status: 'ready',
    algorithmVersion: 'terrain-horizon-radial.1',
    datasetRevision: 'dem-r1',
    resolutionMeters: 30,
    sourceId: 'copernicus-dem-glo30',
    attribution: 'Copernicus DEM',
    observer: {
      elevationMeters: 120,
      sampledLatitude: 30.25,
      sampledLongitude: 120.15,
      heightMeters: 1.7,
    },
    azimuthStepDegrees: 5,
    maximumDistanceKm: 40,
    sampleSpacingMeters: 60,
    refractionCoefficient: 0.13,
    coverageRatio: 0.95,
    samples: Array.from({ length: 72 }, (_, index) => ({
      azimuthDegrees: index * 5,
      horizonAltitudeDegrees: 3,
      obstructionDistanceKm: 4,
      obstructionElevationMeters: 300,
      coverageRatio: 0.95,
    })),
  };
}

test('terrain client authenticates and validates the fixed horizon contract', async () => {
  const calls = [];
  const fact = await fetchTerrainHorizon({
    point: { latitude: 30.25, longitude: 120.15 },
    serviceUrl: 'http://terrain.internal:8793',
    serviceToken: 'secret',
    expectedDatasetRevision: 'dem-r1',
    fetcher: async (url, options) => {
      calls.push({ url, options });
      return new Response(JSON.stringify(payload()));
    },
    timeoutMs: 1_000,
    instant: new Date('2026-07-23T12:00:00Z'),
  });
  assert.equal(fact.status, 'ready');
  assert.equal(fact.samples.length, 72);
  assert.equal(fact.source.revision, 'dem-r1');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer secret');
});

test('terrain client rejects a mismatched dataset revision', async () => {
  const fact = await fetchTerrainHorizon({
    point: { latitude: 30.25, longitude: 120.15 },
    serviceUrl: 'http://terrain.internal:8793',
    serviceToken: 'secret',
    expectedDatasetRevision: 'dem-r2',
    fetcher: async () => new Response(JSON.stringify(payload())),
    timeoutMs: 1_000,
    instant: new Date('2026-07-23T12:00:00Z'),
  });
  assert.equal(fact.status, 'unavailable');
  assert.equal(fact.samples.length, 0);
});
