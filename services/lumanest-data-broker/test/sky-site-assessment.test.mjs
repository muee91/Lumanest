import assert from 'node:assert/strict';
import test from 'node:test';

import {
  astronomicalGeometry,
  createSkySiteAssessment,
  interpolateDirectionalLight,
  interpolateTerrainHorizon,
} from '../src/environment/sky-site-assessment.mjs';

function horizon(altitude = 0, coverage = 1) {
  return {
    status: 'ready',
    algorithmVersion: 'terrain-horizon-radial.1',
    datasetRevision: 'dem-r1',
    azimuthStepDegrees: 5,
    samples: Array.from({ length: 72 }, (_, index) => ({
      azimuthDegrees: index * 5,
      horizonAltitudeDegrees: altitude,
      obstructionDistanceKm: 2,
      obstructionElevationMeters: 300,
      coverageRatio: coverage,
    })),
  };
}

function nightSky(p90 = 0.3, coverage = 1) {
  const directions = [
    'north', 'northeast', 'east', 'southeast',
    'south', 'southwest', 'west', 'northwest',
  ];
  return {
    status: 'ready',
    spatialAnalysis: {
      lightDomes: {
        dominantDirection: 'southeast',
        dominantAzimuthDegrees: 135,
        sectors: directions.map((direction, index) => ({
          direction,
          azimuthCenterDegrees: index * 45,
          p90: index === 3 ? Math.max(12, p90) : p90,
          coverageRatio: coverage,
        })),
      },
    },
  };
}

test('astronomical geometry remains bounded and deterministic', () => {
  const geometry = astronomicalGeometry({
    latitude: 30.25,
    longitude: 120.15,
    observedAt: new Date('2026-07-23T16:00:00Z'),
  });
  assert.ok(geometry.galacticCenter.azimuthDegrees >= 0 &&
    geometry.galacticCenter.azimuthDegrees < 360);
  assert.ok(geometry.galacticCenter.altitudeDegrees >= -90 &&
    geometry.galacticCenter.altitudeDegrees <= 90);
  assert.ok(geometry.sun.altitudeDegrees >= -90 && geometry.sun.altitudeDegrees <= 90);
  assert.equal(typeof geometry.astronomicalNight, 'boolean');
});

test('terrain interpolation wraps through north', () => {
  const profile = horizon();
  profile.samples[71].horizonAltitudeDegrees = 10;
  profile.samples[0].horizonAltitudeDegrees = 20;
  const result = interpolateTerrainHorizon(profile, 357.5);
  assert.equal(result.horizonAltitudeDegrees, 15);
});

test('directional light interpolation identifies the nearest sector', () => {
  const result = interpolateDirectionalLight(nightSky(0.4).spatialAnalysis, 140);
  assert.equal(result.direction, 'southeast');
  assert.equal(result.relativeRadianceBand, 'veryBright');
  assert.equal(result.dominantAngularSeparationDegrees, 5);
});

test('assessment reports terrain blocking without inventing a probability', () => {
  const assessment = createSkySiteAssessment({
    latitude: 30.25,
    longitude: 120.15,
    observedAt: new Date('2026-07-23T16:00:00Z'),
    horizon: horizon(89),
    nightSkyBackground: nightSky(0.2),
  });
  assert.equal(assessment.status, 'ready');
  assert.equal(assessment.conditionBand, 'unavailable');
  assert.ok(assessment.limitations.includes('galactic_center_terrain_blocked'));
  assert.equal(Object.hasOwn(assessment, 'probability'), false);
});
