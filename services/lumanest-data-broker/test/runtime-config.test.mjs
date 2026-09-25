import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { RuntimeConfigService } from '../src/admin/runtime-config.mjs';

function privateKeyPair() {
  const { privateKey } = generateKeyPairSync('ed25519');
  return {
    privateKey,
    pem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  };
}

function environmentDefaults() {
  const pair = privateKeyPair();
  return {
    privateKey: pair.privateKey,
    keyId: 'environment-key-id',
    projectId: 'environment-project-id',
    serviceToken: 'environment-service-token',
    amapWebKey: 'environment-amap-key',
    port: 8787,
  };
}

class MemoryStore {
  constructor(value = null) {
    this.value = value;
    this.failWrite = false;
  }

  async read() {
    return this.value;
  }

  async write(value) {
    if (this.failWrite) throw new Error('simulated store failure');
    this.value = structuredClone(value);
  }
}

test('an older persisted settings block does not brick startup when keys were removed', async () => {
  const store = new MemoryStore({
    settings: {
      wildlifeRadiusKm: 35,
      skyOpportunityNotificationEnabled: true,
      skyOpportunityNotificationThreshold: 1,
    },
  });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();

  const snapshot = service.snapshot();
  assert.equal(snapshot.settings.wildlifeRadiusKm, 35);
  assert.equal(Object.hasOwn(snapshot.settings, 'skyOpportunityNotificationEnabled'), false);
  assert.equal(Object.hasOwn(snapshot.settings, 'skyOpportunityNotificationThreshold'), false);
});

test('settings written through the admin API still reject unknown keys', async () => {
  const service = new RuntimeConfigService({
    defaults: environmentDefaults(),
    store: new MemoryStore({ settings: { wildlifeRadiusKm: 35 } }),
  });
  await service.initialize();

  await assert.rejects(
    service.replace({ settings: { skyOpportunityNotificationEnabled: true } }),
    /Unknown runtime setting: skyOpportunityNotificationEnabled/,
  );
});

test('persisted values override environment while omitted fields fall back', async () => {
  const store = new MemoryStore({
    settings: { wildlifeRadiusKm: 35 },
  });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();

  const snapshot = service.snapshot();
  assert.equal(snapshot.amapWebKey, 'environment-amap-key');
  assert.equal(snapshot.settings.wildlifeRadiusKm, 35);
  assert.equal(snapshot.settings.aiTimeoutMs, 8_000);
});

test('snapshots are frozen and existing callers retain their original revision', async () => {
  const store = new MemoryStore();
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();
  const inFlight = service.snapshot();

  await service.replace({ settings: { wildlifeRadiusKm: 24 } });
  const nextRequest = service.snapshot();

  assert.equal(Object.isFrozen(inFlight), true);
  assert.equal(Object.isFrozen(inFlight.settings), true);
  assert.equal(inFlight.settings.wildlifeRadiusKm, 20);
  assert.equal(nextRequest.settings.wildlifeRadiusKm, 24);
  assert.notEqual(inFlight.revision, nextRequest.revision);
});

test('failed validation or storage retains the previously published snapshot', async () => {
  const store = new MemoryStore();
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();
  const original = service.snapshot();

  await assert.rejects(
    () => service.replace({ settings: { wildlifeRadiusKm: 500 } }),
    /wildlifeRadiusKm/,
  );
  assert.equal(service.snapshot(), original);

  store.failWrite = true;
  await assert.rejects(() => service.replace({ settings: { wildlifeRadiusKm: 24 } }), /store failure/);
  assert.equal(service.snapshot(), original);
});

test('rejects unknown persisted fields instead of interpreting them', async () => {
  const service = new RuntimeConfigService({
    defaults: environmentDefaults(),
    store: new MemoryStore({
      removedField: 'not-supported',
    }),
  });
  await assert.rejects(() => service.initialize(), /Unknown runtime configuration field/);
});

test('QWeather private key accepts an encrypted PEM override', async () => {
  const override = privateKeyPair();
  const store = new MemoryStore({ qweatherPrivateKeyPem: override.pem });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();

  assert.equal(service.snapshot().privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(), override.pem);
});

test('invalid PEM override is rejected without replacing the file-backed key', async () => {
  const defaults = environmentDefaults();
  const store = new MemoryStore();
  const service = new RuntimeConfigService({ defaults, store });
  await service.initialize();
  const original = service.snapshot();

  await assert.rejects(
    () => service.replace({ qweatherPrivateKeyPem: 'not-a-private-key' }),
    /QWeather private key/,
  );
  assert.equal(service.snapshot(), original);
  assert.equal(service.snapshot().privateKey, defaults.privateKey);
});

test('rejects unknown configuration fields', async () => {
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store: new MemoryStore() });
  await service.initialize();
  await assert.rejects(() => service.replace({ surprise: 'value' }), /Unknown runtime configuration/);
});


test('provider configuration is persisted and omitted secrets remain encrypted', async () => {
  const store = new MemoryStore({
    providerSources: {
      ebirdToken: 'initial-ebird-token',
      firmsMapKey: 'initial-firms-key',
      enabledProviders: ['ebird', 'firms'],
    },
  });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();
  await service.replace({
    providerSources: {
      enabledProviders: ['ebird'],
      ebirdBaseUrl: 'https://api.ebird.org',
    },
  });
  assert.equal(service.snapshot().providerSources.ebirdToken, 'initial-ebird-token');
  assert.equal(service.snapshot().providerSources.firmsMapKey, 'initial-firms-key');
  assert.deepEqual(service.snapshot().providerSources.enabledProviders, ['ebird']);
  assert.equal(store.value.providerSources.ebirdToken, 'initial-ebird-token');
});
