import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SkyBrightnessCalibrationStore,
  validateSkyBrightnessCalibrationBundle,
} from '../src/environment/sky-brightness-calibration.mjs';

function bundle() {
  return {
    contractVersion: 1,
    dataset: {
      id: 'public-ground-sky-r1',
      source: 'Normalized Globe at Night and SQM observations',
      attribution: 'Contributing observers',
      license: 'mixed-open',
      generatedAt: '2026-07-23T00:00:00Z',
    },
    cells: [
      {
        latitude: 30,
        longitude: 100,
        sampleCount: 12,
        sqmMedian: 21.2,
        limitingMagnitudeMedian: 6.1,
        observedFrom: '2025-01-01T00:00:00Z',
        observedTo: '2026-01-01T00:00:00Z',
      },
    ],
  };
}

test('ground calibration bundle is strict and provides nearby evidence', () => {
  const validated = validateSkyBrightnessCalibrationBundle(bundle());
  assert.ok(validated);
  const store = new SkyBrightnessCalibrationStore({ status: 'ready', bundle: validated });
  const result = store.lookup({ latitude: 30.01, longitude: 100.01 });
  assert.equal(result.status, 'ready');
  assert.equal(result.sampleCount, 12);
  assert.equal(result.sqmMedian, 21.2);
  assert.ok(result.distanceKm < 5);
});

test('ground calibration does not invent a distant Bortle value', () => {
  const store = new SkyBrightnessCalibrationStore({
    status: 'ready',
    bundle: validateSkyBrightnessCalibrationBundle(bundle()),
  });
  const result = store.lookup({ latitude: 40, longitude: 110 });
  assert.equal(result.status, 'unavailable');
  assert.equal(Object.hasOwn(result, 'bortle'), false);
});
