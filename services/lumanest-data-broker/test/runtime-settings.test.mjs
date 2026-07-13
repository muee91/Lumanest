import assert from 'node:assert/strict';
import test from 'node:test';

import {
  defaultRuntimeSettings,
  validateRuntimeSettings,
} from '../src/admin/runtime-settings.mjs';

test('accepts values inside every documented range', () => {
  const value = validateRuntimeSettings({
    aiEnabled: true,
    aiTimeoutMs: 8_000,
    wildlifeRadiusKm: 20,
    wildlifeCacheTtlMinutes: 60,
    elevationCacheTtlMinutes: 1_440,
    elevationMaximumSamples: 64,
    upstreamTimeoutMs: 10_000,
    minimumOpportunityConfidence: 0.55,
    debugLogging: false,
  });

  assert.equal(value.elevationMaximumSamples, 64);
  assert.equal(Object.isFrozen(value), true);
});

test('rejects settings outside server-side ranges', () => {
  assert.throws(
    () => validateRuntimeSettings({ wildlifeRadiusKm: 500 }, { partial: true }),
    /wildlifeRadiusKm/,
  );
  assert.throws(
    () => validateRuntimeSettings({ aiTimeoutMs: 1_999 }, { partial: true }),
    /aiTimeoutMs/,
  );
  assert.throws(
    () => validateRuntimeSettings({ minimumOpportunityConfidence: 1.01 }, { partial: true }),
    /minimumOpportunityConfidence/,
  );
});

test('rejects unknown fields', () => {
  assert.throws(
    () => validateRuntimeSettings({ surprise: true }, { partial: true }),
    /Unknown runtime setting: surprise/,
  );
});

test('rejects non-finite numbers and invalid boolean values', () => {
  assert.throws(
    () => validateRuntimeSettings({ upstreamTimeoutMs: Number.NaN }, { partial: true }),
    /upstreamTimeoutMs/,
  );
  assert.throws(
    () => validateRuntimeSettings({ debugLogging: 'false' }, { partial: true }),
    /debugLogging/,
  );
});

test('fills omitted settings from immutable defaults', () => {
  const value = validateRuntimeSettings({});

  assert.deepEqual(value, defaultRuntimeSettings);
  assert.equal(Object.isFrozen(defaultRuntimeSettings), true);
  assert.equal(value.aiEnabled, true);
  assert.equal(value.debugLogging, false);
});

test('partial validation returns only supplied settings', () => {
  const value = validateRuntimeSettings(
    { aiEnabled: false, wildlifeRadiusKm: 5 },
    { partial: true },
  );

  assert.deepEqual(value, { aiEnabled: false, wildlifeRadiusKm: 5 });
  assert.equal(Object.isFrozen(value), true);
});
