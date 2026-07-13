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
    aiApiKey: 'environment-ai-key',
    aiBaseUrl: 'https://environment.example/v1',
    aiModel: 'environment-model',
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

test('persisted values override environment while omitted fields fall back', async () => {
  const store = new MemoryStore({
    aiApiKey: 'persisted-ai-key',
    settings: { wildlifeRadiusKm: 35 },
  });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();

  const snapshot = service.snapshot();
  assert.equal(snapshot.aiApiKey, 'persisted-ai-key');
  assert.equal(snapshot.amapWebKey, 'environment-amap-key');
  assert.equal(snapshot.settings.wildlifeRadiusKm, 35);
  assert.equal(snapshot.settings.aiTimeoutMs, 8_000);
});

test('snapshots are frozen and existing callers retain their original revision', async () => {
  const store = new MemoryStore();
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();
  const inFlight = service.snapshot();

  await service.replace({ aiModel: 'next-model' });
  const nextRequest = service.snapshot();

  assert.equal(Object.isFrozen(inFlight), true);
  assert.equal(Object.isFrozen(inFlight.settings), true);
  assert.equal(inFlight.aiModel, 'environment-model');
  assert.equal(nextRequest.aiModel, 'next-model');
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
  await assert.rejects(() => service.replace({ aiModel: 'not-published' }), /store failure/);
  assert.equal(service.snapshot(), original);
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
