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
  assert.equal(configuration.enabledProviders.includes('inaturalist'), true);
  assert.equal(configuration.enabledProviders.includes('ebird'), false);
  assert.equal(providerConfigured('inaturalist', configuration), true);
  assert.equal(providerConfigured('ebird', configuration), false);

  const explicitlyEnabled = validateProviderSources({
    ...configuration,
    enabledProviders: [...configuration.enabledProviders, 'ebird'],
  });
  assert.equal(providerConfigured('ebird', explicitlyEnabled), true);
});

test('only the providers named by the product scope run by default', () => {
  const configuration = validateProviderSources(providerSourceDefaults());

  assert.deepEqual([...configuration.enabledProviders].sort(), [
    'gbif',
    'inaturalist',
    'officialNotices',
    'osm',
    'wikidata',
    'wikimediaCommons',
  ]);
  // Adapters staying in the tree is not a reason to call them upstream; each of
  // these needs a named user value chain before it returns to the default set.
  for (const frozen of [
    'sentinel1',
    'sentinel2',
    'cams',
    'aeronet',
    'firms',
    'copernicusMarine',
    'jplHorizons',
    'noaaSwpc',
    'ebird',
  ]) {
    assert.equal(providerConfigured(frozen, configuration), false, frozen);
  }
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
