import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SiteEnvironmentService,
  validSiteEnvironmentQuery,
} from '../src/environment/site-environment-service.mjs';

const directions = [
  ['north', 0], ['northeast', 45], ['east', 90], ['southeast', 135],
  ['south', 180], ['southwest', 225], ['west', 270], ['northwest', 315],
];

function spatialAnalysis() {
  return {
    analysisVersion: 'viirs-spatial-radiance.1',
    maximumRadiusKm: 20,
    neighborhoods: [
      { radiusKm: 1, sampleCount: 12, coverageRatio: 1, median: 0.1, p90: 0.2, maximum: 0.3 },
      { radiusKm: 5, sampleCount: 80, coverageRatio: 0.95, median: 0.2, p90: 0.4, maximum: 1.2 },
      { radiusKm: 20, sampleCount: 1200, coverageRatio: 0.9, median: 0.3, p90: 1.5, maximum: 12 },
    ],
    lightDomes: {
      innerRadiusKm: 1,
      outerRadiusKm: 20,
      sectorCount: 8,
      dominantDirection: 'southeast',
      dominantAzimuthDegrees: 135,
      sectors: directions.map(([direction, azimuthCenterDegrees]) => ({
        direction,
        azimuthCenterDegrees,
        sampleCount: 100,
        coverageRatio: 0.9,
        median: direction === 'southeast' ? 1.2 : 0.2,
        p90: direction === 'southeast' ? 8 : 0.4,
        maximum: direction === 'southeast' ? 12 : 0.8,
        peakDistanceKm: direction === 'southeast' ? 14 : 8,
      })),
    },
  };
}

function rasterPayload() {
  return {
    status: 'ready',
    radiance: 0.42,
    datasetYear: 2024,
    datasetRevision: 'viirs-r1',
    resolutionMeters: 500,
    sampledLatitude: 28.45,
    sampledLongitude: 98.88,
    spatialAnalysis: spatialAnalysis(),
    sourceId: 'eog-viirs-annual-v2.2',
    attribution: 'Earth Observation Group',
  };
}

function terrainPayload() {
  return {
    status: 'ready',
    algorithmVersion: 'terrain-horizon-radial.1',
    datasetRevision: 'dem-r1',
    resolutionMeters: 30,
    sourceId: 'copernicus-dem-glo30',
    attribution: 'Copernicus DEM GLO-30',
    observer: {
      elevationMeters: 3200,
      sampledLatitude: 28.45,
      sampledLongitude: 98.88,
      heightMeters: 1.7,
    },
    azimuthStepDegrees: 5,
    maximumDistanceKm: 40,
    sampleSpacingMeters: 60,
    refractionCoefficient: 0.13,
    coverageRatio: 0.96,
    samples: Array.from({ length: 72 }, (_, index) => ({
      azimuthDegrees: index * 5,
      horizonAltitudeDegrees: 4,
      obstructionDistanceKm: 6,
      obstructionElevationMeters: 3600,
      coverageRatio: 0.96,
    })),
  };
}

test('assessment query requires an explicit UTC observation time', () => {
  assert.deepEqual(
    validSiteEnvironmentQuery(new URLSearchParams(
      'lat=30.25&lon=120.15&include=skyAssessment&at=2026-07-23T16%3A00%3A00Z',
    )),
    {
      latitude: 30.25,
      longitude: 120.15,
      includeSkyAssessment: true,
      observedAt: '2026-07-23T16:00:00.000Z',
    },
  );
  assert.equal(validSiteEnvironmentQuery(new URLSearchParams(
    'lat=30.25&lon=120.15&include=skyAssessment&at=invalid',
  )), null);
});

test('service returns contract v4 only for explicit sky assessment requests', async () => {
  const calls = [];
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    rasterServiceToken: 'raster-secret',
    rasterDatasetRevision: 'viirs-r1',
    terrainServiceUrl: 'http://terrain.internal:8793',
    terrainServiceToken: 'terrain-secret',
    terrainHorizonDatasetRevision: 'dem-r1',
    now: () => new Date('2026-07-23T16:00:01Z'),
    fetcher: async (url, options = {}) => {
      calls.push({ url: url.toString(), options });
      if (url.hostname === 'api.open-meteo.com') {
        return new Response(JSON.stringify({ elevation: [3260] }));
      }
      if (url.hostname === 'raster.internal') {
        return new Response(JSON.stringify(rasterPayload()));
      }
      assert.equal(url.pathname, '/v1/dem/horizon');
      assert.equal(options.headers.Authorization, 'Bearer terrain-secret');
      return new Response(JSON.stringify(terrainPayload()));
    },
  });

  const defaultBody = await service.facts({ latitude: 28.4502, longitude: 98.8802 });
  assert.equal(defaultBody.contractVersion, 3);
  assert.equal(Object.hasOwn(defaultBody, 'skySiteAssessment'), false);

  const assessmentBody = await service.facts({
    latitude: 28.4502,
    longitude: 98.8802,
    includeSkyAssessment: true,
    observedAt: '2026-07-23T16:00:00.000Z',
  });
  assert.equal(assessmentBody.contractVersion, 4);
  assert.equal(assessmentBody.terrainHorizon.status, 'ready');
  assert.equal(assessmentBody.terrainHorizon.samples.length, 72);
  assert.equal(assessmentBody.skySiteAssessment.status, 'ready');
  assert.equal(assessmentBody.skySiteAssessment.algorithmVersion, 'sky-site-assessment.1');
  assert.equal(Object.hasOwn(assessmentBody.skySiteAssessment, 'probability'), false);
  assert.equal(calls.filter((item) => item.url.includes('/v1/dem/horizon')).length, 1);
});
