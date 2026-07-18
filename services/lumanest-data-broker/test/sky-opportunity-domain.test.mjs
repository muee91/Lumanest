import assert from 'node:assert/strict';
import test from 'node:test';

import { aggregateSkyOpportunity } from '../src/domain/sky_opportunity/sky_opportunity_aggregator.mjs';
import { clarityLevel, opportunityLevel } from '../src/domain/sky_opportunity/sky_opportunity_levels.mjs';
import { parseAmapCityCandidates } from '../src/domain/sky_opportunity/sky_opportunity_city_resolver.mjs';

function model(model, score, overrides = {}) {
  return {
    model,
    score,
    status: 'ok',
    parseStatus: 'ok',
    aod: .244,
    eventTime: '2026-07-18T18:59:55+08:00',
    fetchedAt: '2026-07-18T09:10:00Z',
    ...overrides,
  };
}

function aggregate(models, { stale = false } = {}) {
  return aggregateSkyOpportunity({
    city: '杭州',
    requestedCity: '杭州',
    latitude: 30.2741,
    longitude: 120.1551,
    eventType: 'sunset',
    dayOffset: 0,
    models,
    now: new Date('2026-07-18T09:10:00Z'),
    freshTtlSeconds: 5_400,
    stale,
    cacheStatus: stale ? 'stale' : 'miss',
  });
}

test('averages GFS and EC and maps strong agreement', () => {
  const value = aggregate([model('GFS', .291), model('EC', .429)]);
  assert.equal(value.summary.score, .36);
  assert.equal(value.summary.level, 'moderate');
  assert.equal(value.summary.agreement, 'strong');
  assert.equal(value.summary.confidence, 'high');
  assert.equal(value.summary.normalizedScore, .144);
  assert.equal(value.atmosphere.clarityLevel, 'good');
});

test('single model remains usable and confidence is capped at medium', () => {
  const value = aggregate([
    model('GFS', .42),
    { model: 'EC', status: 'timeout', parseStatus: 'timeout', fetchedAt: null },
  ]);
  assert.equal(value.summary.score, .42);
  assert.equal(value.summary.agreement, 'single_model');
  assert.equal(value.summary.confidence, 'medium');
});

test('conflicting models stay low confidence and never become probability', () => {
  const value = aggregate([model('GFS', .20), model('EC', .90)]);
  assert.equal(value.summary.score, .55);
  assert.equal(value.summary.agreement, 'conflict');
  assert.equal(value.summary.confidence, 'low');
  assert.equal(value.summary.primaryReason, '双模型分歧较大');
});

test('stale cache lowers confidence and scales its score', () => {
  const value = aggregate([model('GFS', .4), model('EC', .5)], { stale: true });
  assert.equal(value.summary.confidence, 'medium');
  assert.equal(value.summary.confidenceScore, .85 * .75);
  assert.equal(value.freshness.isStale, true);
  assert.equal(value.provider.providerStatus, 'degraded');
});

test('maps every fixed score and AOD edge without filling missing AOD', () => {
  assert.equal(opportunityLevel(null).level, 'unavailable');
  assert.equal(opportunityLevel(0).level, 'none');
  assert.equal(opportunityLevel(.30).level, 'moderate');
  assert.equal(opportunityLevel(.20).level, 'moderate');
  assert.equal(opportunityLevel(.60).level, 'strong');
  assert.equal(opportunityLevel(2).level, 'exceptional');
  assert.equal(clarityLevel(null).clarityLevel, 'unknown');
  assert.equal(clarityLevel(.244).clarityLevel, 'good');
  assert.equal(clarityLevel(.81).clarityLevel, 'very_poor');
});

test('prefers prefecture city over district and keeps editable aliases', () => {
  const result = parseAmapCityCandidates({
    status: '1',
    regeocode: {
      addressComponent: { province: '浙江省', city: '杭州市', district: '临安区' },
    },
  });
  assert.equal(result.requestedCity, '杭州');
  assert.deepEqual(result.candidates, ['杭州']);
  assert.equal(result.candidates.includes('临安'), false);
});
