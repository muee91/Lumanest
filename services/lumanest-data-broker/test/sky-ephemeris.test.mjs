import assert from 'node:assert/strict';
import test from 'node:test';

import { skyEphemeris } from '../src/environment/sky-ephemeris.mjs';

function horizon(altitude = 0) {
  return {
    status: 'ready',
    azimuthStepDegrees: 5,
    samples: Array.from({ length: 72 }, (_, index) => ({
      azimuthDegrees: index * 5,
      horizonAltitudeDegrees: altitude,
      obstructionDistanceKm: 5,
      obstructionElevationMeters: 1000,
      coverageRatio: 1,
    })),
  };
}

test('sky ephemeris returns terrain-aware moon and galaxy geometry', () => {
  const result = skyEphemeris({
    latitude: 30,
    longitude: 100,
    elevationMeters: 2500,
    observedAt: new Date('2026-07-23T16:00:00Z'),
    horizon: horizon(),
  });
  assert.ok(result);
  assert.equal(result.modelVersion, 'astronomy-engine-2.1.19');
  assert.ok(result.moon.illuminationFraction >= 0 && result.moon.illuminationFraction <= 1);
  assert.ok(result.moon.phaseAngleDegrees >= 0 && result.moon.phaseAngleDegrees <= 180);
  assert.ok(result.moon.angularSeparationFromGalacticCenterDegrees >= 0);
  assert.equal(result.moon.terrainStatus, 'ready');
  assert.match(result.moon.interferenceBand, /^(low|moderate|high)$/);
  assert.ok(result.galacticCenter.azimuthDegrees >= 0 && result.galacticCenter.azimuthDegrees < 360);
});

test('terrain-blocked moon is treated as low directional interference', () => {
  const result = skyEphemeris({
    latitude: 30,
    longitude: 100,
    elevationMeters: 2500,
    observedAt: new Date('2026-07-23T16:00:00Z'),
    horizon: horizon(89),
  });
  assert.ok(result);
  assert.equal(result.moon.terrainBlocked, true);
  assert.equal(result.moon.interferenceBand, 'low');
});
