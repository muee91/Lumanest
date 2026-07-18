import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canonicalTags,
  creativePrompts,
  opportunityCatalog,
  opportunityCatalogVersion,
  timingPolicies,
} from '../src/generated/opportunity-catalog.mjs';

test('generated catalog matches engineering-spec counts', () => {
  assert.equal(opportunityCatalogVersion, 1);
  assert.equal(opportunityCatalog.length, 48);
  assert.equal(opportunityCatalog.filter((item) => item.catalogTier === 'core').length, 16);
  assert.equal(opportunityCatalog.filter((item) => item.catalogTier === 'legacyOnly').length, 3);
  assert.equal(opportunityCatalog.filter((item) => item.catalogTier === 'reserved').length, 29);
  assert.equal(opportunityCatalog.filter((item) => item.coreCapability === 'available').length, 6);
  assert.equal(opportunityCatalog.filter((item) => item.coreCapability === 'degraded').length, 7);
  assert.equal(opportunityCatalog.filter((item) => item.coreCapability === 'unavailable').length, 3);
  assert.equal(timingPolicies.length, 16);
  assert.equal(canonicalTags.length, 96);
  assert.equal(creativePrompts.length, 48);
});

test('generated catalog is deeply immutable', () => {
  assert.equal(Object.isFrozen(opportunityCatalog), true);
  assert.equal(Object.isFrozen(opportunityCatalog[0]), true);
  assert.equal(Object.isFrozen(opportunityCatalog[0].presentation.zhCN), true);
});
