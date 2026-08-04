import assert from 'node:assert/strict';
import test from 'node:test';

import { SkyWindowService, validSkyWindowQuery } from '../src/environment/sky-window-service.mjs';

const directions = [
  ['north', 0], ['northeast', 45], ['east', 90], ['southeast', 135],
  ['south', 180], ['southwest', 225], ['west', 270], ['northwest', 315],
];

function horizon() {
  return {
    status: 'ready',
    algorithmVersion: 'terrain-horizon-radial.1',
    datasetRevision: 'dem-r1',
    observer: { elevationMeters: 2500 },
    azimuthStepDegrees: 5,
    coverageRatio: 1,
    samples: Array.from({ length: 72 }, (_, index) => ({
      azimuthDegrees: index * 5,
      horizonAltitudeDegrees: -1,
      obstructionDistanceKm: 5,
      obstructionElevationMeters: 2200,
      coverageRatio: 1,
    })),
    source: { id: 'dem', revision: 'dem-r1', attribution: 'DEM' },
  };
}

function nightSky() {
  return {
    status: 'ready',
    spatialAnalysis: {
      lightDomes: {
        dominantDirection: 'east',
        dominantAzimuthDegrees: 90,
        sectors: directions.map(([direction, azimuthCenterDegrees]) => ({
          direction,
          azimuthCenterDegrees,
          p90: 0.1,
          coverageRatio: 1,
        })),
      },
    },
    source: { id: 'viirs', revision: 'viirs-r1', attribution: 'VIIRS' },
  };
}

function weatherPoints({ cloud = 5, precipitation = 0, probability = 0 } = {}) {
  return Array.from({ length: 10 }, (_, index) => ({
    validAt: new Date(Date.parse('2026-07-23T15:00:00Z') + index * 60 * 60 * 1000).toISOString(),
    totalCloudCoverPercent: cloud,
    lowCloudCoverPercent: cloud,
    middleCloudCoverPercent: 0,
    highCloudCoverPercent: 0,
    visibilityMeters: 30000,
    precipitationProbabilityPercent: probability,
    precipitationMm: precipitation,
    relativeHumidityPercent: 50,
    windSpeedKmh: 5,
    windGustKmh: 10,
  }));
}

function service(options = {}) {
  return new SkyWindowService({
    siteEnvironmentService: {
      facts: async () => ({ terrainHorizon: horizon(), nightSkyBackground: nightSky() }),
    },
    openMeteoForecast: {
      forecast: async () => ({
        ok: true,
        body: {
          source: 'open-meteo-best-match',
          fetchedAt: '2026-07-23T15:00:00Z',
          expiresAt: '2026-07-23T15:15:00Z',
          cacheStatus: 'miss',
          attribution: 'Open-Meteo',
          license: 'CC-BY-4.0',
          points: weatherPoints(options.weather),
        },
      }),
    },
    sevenTimerService: {
      forecast: async () => ({ ok: false, error: 'disabled' }),
    },
    calibrationStore: {
      lookup: () => ({ status: 'unconfigured', sampleCount: 0, source: null }),
    },
    now: () => new Date('2026-07-23T15:00:00Z'),
  });
}

test('sky-window query is bounded and requires exact UTC', () => {
  const now = new Date('2026-07-23T15:00:00Z');
  assert.deepEqual(
    validSkyWindowQuery(new URLSearchParams('lat=30&lon=100&start=2026-07-23T15%3A00%3A00.000Z&hours=24'), now),
    { latitude: 30, longitude: 100, startAt: '2026-07-23T15:00:00.000Z', hours: 24, locale: 'zh-CN' },
  );
  assert.equal(validSkyWindowQuery(new URLSearchParams('lat=30&lon=100&start=bad&hours=24'), now), null);
  assert.equal(validSkyWindowQuery(new URLSearchParams('lat=30&lon=100&start=2026-07-23T15%3A00%3A00.000Z&hours=100'), now), null);
});

test('clear public weather and dark terrain-aware sky create bounded windows', async () => {
  const result = await service().forecast({
    latitude: 30,
    longitude: 100,
    startAt: '2026-07-23T15:00:00.000Z',
    hours: 6,
    locale: 'zh-CN',
  });
  assert.equal(result.contractVersion, 1);
  assert.equal(result.stepMinutes, 15);
  assert.ok(result.current.moon);
  assert.equal(result.samples.length, 25);
  assert.equal(result.samples[0].validAt, result.current.observedAt);
  assert.equal(result.samples.at(-1).validAt, result.endAt);
  assert.equal(result.samples[0].totalCloudCoverPercent, 5);
  assert.equal(result.samples[0].weatherAgreement, 'unavailable');
  assert.ok(result.windows.length >= 1);
  assert.ok(result.bestWindowId);
  assert.equal(result.confidence.criticalSourcesReady, true);
  assert.equal(result.confidence.missingSources.includes('seven_timer_auxiliary'), true);
  assert.equal(Object.hasOwn(result, 'successProbability'), false);
  assert.equal(Object.hasOwn(result.samples[0], 'successProbability'), false);
});

test('precipitation blocks windows without creating a probability', async () => {
  const result = await service({ weather: { precipitation: 0.4, probability: 80 } }).forecast({
    latitude: 30,
    longitude: 100,
    startAt: '2026-07-23T15:00:00.000Z',
    hours: 6,
    locale: 'zh-CN',
  });
  assert.equal(result.windows.length, 0);
  assert.equal(result.current.conditionBand, 'unavailable');
  assert.equal(result.samples[0].precipitationProbabilityPercent, 80);
  assert.equal(result.samples[0].precipitationMm, 0.4);
  assert.ok(result.current.limitations.includes('precipitation_likely'));
  assert.ok(result.samples[0].limitations.includes('precipitation_likely'));
});
