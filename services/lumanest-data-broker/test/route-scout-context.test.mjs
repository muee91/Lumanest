import assert from 'node:assert/strict';
import test from 'node:test';

import {
  coarseRouteCorridor,
  routeWeatherFacts,
  validRouteCorridorBinding,
} from '../src/assistant/route-scout-context.mjs';

test('route corridor binding keeps only coarse cells and route timing', () => {
  const binding = coarseRouteCorridor({
    routeId: 'r12345678',
    corridorSamples: [
      {
        latitude: 30.123456,
        longitude: 120.654321,
        system: 'wgs84',
        expectedAt: '2026-08-04T02:00:00Z',
        progress: 0,
      },
      {
        latitude: 30.223456,
        longitude: 120.754321,
        system: 'wgs84',
        expectedAt: '2026-08-04T03:00:00Z',
        progress: .5,
      },
    ],
  });

  assert.equal(validRouteCorridorBinding(binding), true);
  assert.notEqual(binding.samples[0].latitude, 30.123456);
  assert.notEqual(binding.samples[0].longitude, 120.654321);
  assert.equal(binding.samples[0].system, 'wgs84');
  assert.equal(Object.hasOwn(binding.samples[0], 'name'), false);
});

test('route weather facts preserve uncertainty and safety-card boundary', () => {
  const now = new Date('2026-08-04T02:00:00Z');
  const facts = routeWeatherFacts({
    ok: true,
    body: {
      routeId: 'r12345678',
      generatedAt: now.toISOString(),
      source: 'QWeather',
      coverage: 'full',
      requestedSamples: 2,
      availableSamples: 2,
      samples: [
        {
          progress: 0,
          expectedAt: now.toISOString(),
          forecastAt: now.toISOString(),
          condition: 'cloudy',
          cloudCoverPercent: 70,
          windSpeedMps: 3,
          precipitationMm: 0,
          visibilityKm: 20,
          thunder: false,
          stale: false,
        },
        {
          progress: .5,
          expectedAt: '2026-08-04T03:00:00Z',
          forecastAt: '2026-08-04T03:00:00Z',
          condition: 'rain',
          cloudCoverPercent: 95,
          windSpeedMps: 8,
          precipitationMm: 5,
          visibilityKm: 4,
          thunder: true,
          stale: false,
        },
      ],
    },
  }, now);

  assert.equal(facts.lines.length, 2);
  assert.match(facts.lines[1], /雷暴信号/);
  assert.match(facts.lines[1], /安全卡和官方预警/);
  assert.equal(facts.factIds.length, 2);
});
