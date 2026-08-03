import assert from 'node:assert/strict';
import test from 'node:test';

import {
  providerConfigured,
  providerSourceDefaults,
  safeProviderSources,
  validateProviderSources,
} from '../src/environment/provider-runtime-config.mjs';

test('provider defaults are production-safe and secrets are masked', () => {
  const configuration = validateProviderSources({
    ...providerSourceDefaults(),
    ebirdToken: 'ebird-secret-1234',
    firmsMapKey: 'firms-secret-5678',
  });
  const safe = safeProviderSources(configuration);
  assert.equal(safe.ebirdToken.configured, true);
  assert.equal(safe.ebirdToken.lastFour, '1234');
  assert.equal(JSON.stringify(safe).includes('ebird-secret'), false);
  assert.equal(providerConfigured('ebird', configuration), true);
});

test('official notice sources require HTTPS, coverage and authority before safety promotion', () => {
  assert.throws(() => validateProviderSources({
    officialNoticeSources: [{
      id: 'unsafe', name: 'Unsafe', feedUrl: 'http://example.com/feed',
      homepageUrl: 'https://example.com', format: 'rss', authoritative: true,
      promoteToSafety: true, coverage: { latitude: 30, longitude: 120, radiusKm: 20 },
      allowedKinds: ['closure'],
    }],
  }, { partial: true }), /HTTPS/);
  assert.throws(() => validateProviderSources({
    officialNoticeSources: [{
      id: 'reference', name: 'Reference', feedUrl: 'https://example.com/feed',
      homepageUrl: 'https://example.com', format: 'rss', authoritative: false,
      promoteToSafety: true, coverage: { latitude: 30, longitude: 120, radiusKm: 20 },
      allowedKinds: ['closure'],
    }],
  }, { partial: true }), /non-authoritative/);
});

test('unknown provider configuration fields are rejected', () => {
  assert.throws(
    () => validateProviderSources({ cookiePool: ['forbidden'] }, { partial: true }),
    /Unknown provider source field/,
  );
});
