import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { RuntimeConfigService } from '../src/admin/runtime-config.mjs';

class Store {
  constructor(value = null) { this.value = value; }
  async read() { return this.value; }
  async write(value) { this.value = structuredClone(value); }
}

function defaults() {
  return {
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'key', projectId: 'project', serviceToken: 'service', amapWebKey: 'amap',
    port: 8787,
  };
}

function profile(overrides = {}) {
  return {
    id: 'deepseek-main', name: 'DeepSeek 主模型', providerId: 'deepseek',
    protocol: 'openai_compatible', apiKey: 'profile-secret',
    baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat',
    enabled: true, timeoutMs: 8_000, allowFallback: false, ...overrides,
  };
}

test('LLM runtime starts empty without selecting or creating a provider', async () => {
  const service = new RuntimeConfigService({ defaults: defaults(), store: new Store() });
  await service.initialize();
  const snapshot = service.snapshot();
  assert.deepEqual(snapshot.llmProfiles, []);
  assert.deepEqual(snapshot.llmRouting, {
    primaryProfileId: null, fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3,
  });
  assert.equal(Object.isFrozen(snapshot.llmProfiles), true);
  assert.equal(Object.isFrozen(snapshot.llmRouting), true);
});

test('publishes explicitly saved profiles and routing as immutable snapshots', async () => {
  const service = new RuntimeConfigService({ defaults: defaults(), store: new Store() });
  await service.initialize();
  await service.replace({ llmProfiles: [profile()] });
  const snapshot = await service.replace({
    llmRouting: {
      primaryProfileId: 'deepseek-main', fallbackEnabled: false,
      fallbackProfileIds: [], maximumAttempts: 3,
    },
  });
  assert.equal(snapshot.llmProfiles[0].id, 'deepseek-main');
  assert.equal(snapshot.llmRouting.primaryProfileId, 'deepseek-main');
  assert.equal(Object.isFrozen(snapshot.llmProfiles[0]), true);
});

test('profile update preserves an omitted encrypted API key', async () => {
  const store = new Store({ llmProfiles: [profile()] });
  const service = new RuntimeConfigService({ defaults: defaults(), store });
  await service.initialize();
  const edited = profile({ name: '新名称' });
  delete edited.apiKey;
  const snapshot = await service.replace({ llmProfiles: [edited] });
  assert.equal(snapshot.llmProfiles[0].apiKey, 'profile-secret');
  assert.equal(store.value.llmProfiles[0].apiKey, 'profile-secret');
});

test('rejects deleting a profile referenced by routing and keeps the old snapshot', async () => {
  const store = new Store({
    llmProfiles: [profile()],
    llmRouting: { primaryProfileId: 'deepseek-main', fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 },
  });
  const service = new RuntimeConfigService({ defaults: defaults(), store });
  await service.initialize();
  const original = service.snapshot();
  await assert.rejects(() => service.replace({ llmProfiles: [] }), /primaryProfileId/);
  assert.equal(service.snapshot(), original);
});

test('rejects duplicate IDs and invalid fallback references', async () => {
  const service = new RuntimeConfigService({ defaults: defaults(), store: new Store() });
  await service.initialize();
  await assert.rejects(() => service.replace({ llmProfiles: [profile(), profile()] }), /Duplicate LLM profile/);
  await service.replace({ llmProfiles: [profile()] });
  await assert.rejects(() => service.replace({
    llmRouting: { primaryProfileId: 'deepseek-main', fallbackEnabled: true, fallbackProfileIds: ['missing'], maximumAttempts: 3 },
  }), /fallbackProfileIds/);
});

test('allows an unselected model draft but never routes it', async () => {
  const service = new RuntimeConfigService({ defaults: defaults(), store: new Store() });
  await service.initialize();
  await service.replace({ llmProfiles: [profile({ model: '' })] });
  await assert.rejects(() => service.replace({
    llmRouting: {
      primaryProfileId: 'deepseek-main', fallbackEnabled: false,
      fallbackProfileIds: [], maximumAttempts: 3,
    },
  }), /selected model/);
});
