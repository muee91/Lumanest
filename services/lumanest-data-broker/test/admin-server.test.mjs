import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createAdminServer } from '../src/admin/admin-server.mjs';
import { AdminAuthService } from '../src/admin/auth.mjs';
import { AuditLog } from '../src/admin/audit-log.mjs';
import { validateRuntimeSettings } from '../src/admin/runtime-settings.mjs';
import { SimulationRegistry } from '../src/context/simulation.mjs';

async function withAdmin(run, { simulationEnabled = false, simulationRegistry = null } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-admin-server-'));
  const authService = new AdminAuthService({
    filePath: join(directory, 'auth.json'),
    bootstrapPassword: 'initial-password',
  });
  await authService.initialize();
  let snapshot = Object.freeze({
    revision: 1,
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'key-id-1234', projectId: 'project-5678',
    serviceToken: 'service-secret-9012', amapWebKey: 'amap-secret-3456',
    aiApiKey: '', aiBaseUrl: '', aiModel: '',
    settings: validateRuntimeSettings({}),
    llmProfiles: [],
    llmRouting: { primaryProfileId: null, fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 },
  });
  const operations = [];
  const runtimeConfig = {
    snapshot: () => snapshot,
    replace: async (patch) => {
      snapshot = Object.freeze({ ...snapshot, ...patch, revision: snapshot.revision + 1 });
      return snapshot;
    },
  };
  const server = createAdminServer({
    authService, runtimeConfig, auditLog: new AuditLog(),
    testConnection: async () => ({ status: 'ok' }),
    clearCache: async () => operations.push('clear'),
    restart: async () => operations.push('restart'),
    testLLMProfile: async (profileId) => ({ status: 'ok', profileId }),
    listLLMModels: async (profile) => ({ ok: true, models: [`${profile.providerId}-model`] }),
    getShootingCalibration: async ({ days, minimumSamples }) => ({
      ok: true,
      report: {
        generatedAt: '2026-07-18T02:00:00Z', since: '2026-04-19T02:00:00Z',
        minimumSamples,
        rows: [{
          ruleVersion: 'water-evening.1', conditionBand: 'good', factorId: 'wind',
          factorEffect: 'supporting', evaluatedCount: minimumSamples,
          capturedCount: minimumSamples - 1, conditionsDidNotAppearCount: 1,
          capturedRate: (minimumSamples - 1) / minimumSamples,
        }],
      },
    }),
    importContextDataset: async (body) => {
      operations.push(`import:${body.datasetType}`);
      return {
        ok: true,
        result: {
          sourceId: body.source.id,
          datasetType: body.datasetType,
          importedCount: body.featureCollection?.features?.length ?? body.events?.length ?? 0,
          enabled: body.source.enabled,
          cacheInvalidated: true,
        },
      };
    },
    simulationEnabled,
    simulationRegistry,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    await run({ baseUrl: `http://127.0.0.1:${server.address().port}`, operations });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
}

async function login(baseUrl, password = 'initial-password') {
  const response = await fetch(`${baseUrl}/admin-api/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password }),
  });
  const value = await response.json();
  return { cookie: response.headers.get('set-cookie').split(';')[0], csrf: value.csrfToken };
}

test('LAN login and authenticated config never reveal raw secrets', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const unauthenticated = await fetch(`${baseUrl}/admin-api/config`);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('cache-control'), 'no-store');

    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/config`, {
      headers: { Cookie: credentials.cookie, 'X-Forwarded-For': '8.8.8.8' },
    });
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.equal(text.includes('service-secret-9012'), false);
    assert.equal(text.includes('aiApiKey'), false);
    assert.equal(JSON.parse(text).services.serviceToken.lastFour, '9012');
  });
});

test('password change requires the current password and matching confirmation', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const headers = {
      Cookie: credentials.cookie,
      'X-CSRF-Token': credentials.csrf,
      'Content-Type': 'application/json',
    };
    const wrongCurrent = await fetch(`${baseUrl}/admin-api/change-password`, {
      method: 'POST', headers,
      body: JSON.stringify({
        currentPassword: 'incorrect-password',
        newPassword: 'replacement-password',
        confirmPassword: 'replacement-password',
      }),
    });
    assert.equal(wrongCurrent.status, 401);
    assert.equal((await wrongCurrent.json()).error, 'invalid_current_password');
    assert.equal((await fetch(`${baseUrl}/admin-api/config`, {
      headers: { Cookie: credentials.cookie },
    })).status, 200);

    const mismatch = await fetch(`${baseUrl}/admin-api/change-password`, {
      method: 'POST', headers,
      body: JSON.stringify({
        currentPassword: 'initial-password',
        newPassword: 'replacement-password',
        confirmPassword: 'different-password',
      }),
    });
    assert.equal(mismatch.status, 400);
    assert.equal((await mismatch.json()).error, 'password_mismatch');

    const changed = await fetch(`${baseUrl}/admin-api/change-password`, {
      method: 'POST', headers,
      body: JSON.stringify({
        currentPassword: 'initial-password',
        newPassword: 'replacement-password',
        confirmPassword: 'replacement-password',
      }),
    });
    assert.equal(changed.status, 200);
    assert.match(changed.headers.get('set-cookie'), /Max-Age=0/);
    assert.equal((await fetch(`${baseUrl}/admin-api/config`, {
      headers: { Cookie: credentials.cookie },
    })).status, 401);
    assert.equal((await login(baseUrl, 'replacement-password')).csrf.length > 0, true);
  });
});

test('mutations require CSRF and supported operations remain authenticated', async () => {
  await withAdmin(async ({ baseUrl, operations }) => {
    const credentials = await login(baseUrl);
    const withoutCsrf = await fetch(`${baseUrl}/admin-api/clear-cache`, {
      method: 'POST', headers: { Cookie: credentials.cookie },
    });
    assert.equal(withoutCsrf.status, 403);

    const headers = { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' };
    assert.equal((await fetch(`${baseUrl}/admin-api/test-connection`, { method: 'POST', headers, body: '{}' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/config`, { method: 'PUT', headers, body: JSON.stringify({ settings: { wildlifeRadiusKm: 24 } }) })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/clear-cache`, { method: 'POST', headers, body: '{}' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/audit`, { headers: { Cookie: credentials.cookie } })).status, 200);
    assert.deepEqual(operations, ['clear']);
  });
});

test('rejects request bodies larger than 16 KiB before processing', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/admin-api/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: 'x'.repeat(17 * 1024) }),
    });
    assert.equal(response.status, 413);
  });
});

test('context imports require an authenticated CSRF-protected LAN session', async () => {
  await withAdmin(async ({ baseUrl, operations }) => {
    const importBody = {
      datasetType: 'spatialFeatures',
      source: {
        id: 'reviewed-lakes', enabled: false, licenseStatus: 'approved',
        attribution: 'Reviewed local fixture', version: '2026-07-14',
      },
      featureCollection: { type: 'FeatureCollection', features: [] },
    };
    const unauthenticated = await fetch(`${baseUrl}/admin-api/context/imports`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(importBody),
    });
    assert.equal(unauthenticated.status, 401);

    const credentials = await login(baseUrl);
    const withoutCsrf = await fetch(`${baseUrl}/admin-api/context/imports`, {
      method: 'POST',
      headers: { Cookie: credentials.cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify(importBody),
    });
    assert.equal(withoutCsrf.status, 403);

    const response = await fetch(`${baseUrl}/admin-api/context/imports`, {
      method: 'POST',
      headers: {
        Cookie: credentials.cookie,
        'X-CSRF-Token': credentials.csrf,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(importBody),
    });
    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), {
      sourceId: 'reviewed-lakes', datasetType: 'spatialFeatures',
      importedCount: 0, enabled: false, cacheInvalidated: true,
    });
    assert.deepEqual(operations, ['import:spatialFeatures']);
  });
});

test('shooting calibration is authenticated and exposes aggregate rows only', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const adminPage = await (await fetch(`${baseUrl}/admin`)).text();
    assert.equal(adminPage.includes('data-page="calibration"'), true);
    assert.equal(adminPage.includes('不包含地点、机位、身份或原始反馈'), true);

    const unauthenticated = await fetch(
      `${baseUrl}/admin-api/context/shooting-calibration?days=90&minimumSamples=5`,
    );
    assert.equal(unauthenticated.status, 401);

    const credentials = await login(baseUrl);
    const response = await fetch(
      `${baseUrl}/admin-api/context/shooting-calibration?days=90&minimumSamples=5`,
      { headers: { Cookie: credentials.cookie } },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.rows[0].evaluatedCount, 5);
    assert.equal(JSON.stringify(body).includes('targetId'), false);

    const invalid = await fetch(
      `${baseUrl}/admin-api/context/shooting-calibration?days=90x&minimumSamples=1`,
      { headers: { Cookie: credentials.cookie } },
    );
    assert.equal(invalid.status, 400);
  });
});

test('scene lab is capability-gated and controls opaque debug sessions only', async () => {
  const registry = new SimulationRegistry();
  registry.register('debugsession2345678', { contractVersion: 4 });
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const readHeaders = { Cookie: credentials.cookie };
    const writeHeaders = {
      ...readHeaders,
      'X-CSRF-Token': credentials.csrf,
      'Content-Type': 'application/json',
    };
    const capabilities = await fetch(`${baseUrl}/admin-api/capabilities`, { headers: readHeaders });
    assert.deepEqual(await capabilities.json(), {
      developerTools: { simulationEnabled: true },
    });
    const lab = await fetch(`${baseUrl}/admin-api/simulation`, { headers: readHeaders });
    const initial = await lab.json();
    assert.equal(initial.presets.length, 6);
    assert.equal(initial.sessions.length, 1);
    assert.match(initial.sessions[0].controlId, /^sim_[a-f0-9]{24}$/);
    assert.equal(JSON.stringify(initial).includes('debugsession2345678'), false);

    const activated = await fetch(
      `${baseUrl}/admin-api/simulation/sessions/${initial.sessions[0].controlId}`,
      { method: 'POST', headers: writeHeaders, body: JSON.stringify({ preset: 'lake-sunset' }) },
    );
    assert.equal(activated.status, 200);
    assert.equal((await activated.json()).preset, 'lake-sunset');

    const cleared = await fetch(`${baseUrl}/admin-api/simulation/sessions`, {
      method: 'DELETE', headers: writeHeaders, body: '{}',
    });
    assert.deepEqual(await cleared.json(), { ok: true, cleared: 1 });
  }, { simulationEnabled: true, simulationRegistry: registry });
});

test('scene lab endpoints are unavailable when the environment capability is disabled', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const headers = { Cookie: credentials.cookie };
    assert.deepEqual(await (await fetch(`${baseUrl}/admin-api/capabilities`, { headers })).json(), {
      developerTools: { simulationEnabled: false },
    });
    assert.equal((await fetch(`${baseUrl}/admin-api/simulation`, { headers })).status, 404);
  });
});

test('manages masked LLM profiles and explicit routing without a default provider', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const readHeaders = { Cookie: credentials.cookie };
    const writeHeaders = {
      ...readHeaders, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json',
    };
    const providersResponse = await fetch(`${baseUrl}/admin-api/llm/providers`, { headers: readHeaders });
    assert.equal(providersResponse.status, 200);
    const providers = (await providersResponse.json()).providers;
    assert.equal(providers.length, 11);
    assert.equal(JSON.stringify(providers).includes('default'), false);

    const empty = await fetch(`${baseUrl}/admin-api/llm/profiles`, { headers: readHeaders });
    assert.deepEqual((await empty.json()).profiles, []);

    const candidate = {
      id: 'deepseek-main', name: 'DeepSeek 主模型', providerId: 'deepseek',
      protocol: 'openai_compatible', apiKey: 'profile-secret-1234',
      baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat',
      enabled: true, timeoutMs: 8_000, allowFallback: false,
    };
    const created = await fetch(`${baseUrl}/admin-api/llm/profiles`, {
      method: 'POST', headers: writeHeaders, body: JSON.stringify(candidate),
    });
    assert.equal(created.status, 201);
    const createdText = await created.text();
    assert.equal(createdText.includes('profile-secret-1234'), false);
    assert.equal(JSON.parse(createdText).profile.apiKey.lastFour, '1234');

    const routing = await fetch(`${baseUrl}/admin-api/llm/routing`, {
      method: 'PUT', headers: writeHeaders,
      body: JSON.stringify({ primaryProfileId: 'deepseek-main', fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 }),
    });
    assert.equal(routing.status, 200);

    const tested = await fetch(`${baseUrl}/admin-api/llm/profiles/deepseek-main/test`, {
      method: 'POST', headers: writeHeaders, body: '{}',
    });
    assert.deepEqual(await tested.json(), { status: 'ok', profileId: 'deepseek-main' });
  });
});

test('lists models for a draft with no model selected and never returns its key', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const headers = {
      Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json',
    };
    const draft = {
      id: 'openai-main', name: 'OpenAI 主模型', providerId: 'openai',
      protocol: 'openai_compatible', apiKey: 'profile-secret-9876',
      baseUrl: 'https://api.openai.com/v1', model: '',
      enabled: true, timeoutMs: 8_000, allowFallback: false,
    };
    const response = await fetch(`${baseUrl}/admin-api/llm/models`, {
      method: 'POST', headers, body: JSON.stringify(draft),
    });
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.equal(text.includes('profile-secret-9876'), false);
    assert.deepEqual(JSON.parse(text), { models: ['openai-model'] });
  });
});

test('manages an encrypted reviewed-source search profile without exposing its key', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const headers = {
      Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json',
    };
    const profile = {
      baseUrl: 'https://api.tavily.com', apiKey: 'tavily-secret-9876', enabled: true, timeoutMs: 8_000,
      sourcePolicies: [{
        id: 'haining-culture', domain: 'culture.example.gov.cn', attribution: '海宁文化发布',
        license: 'CC BY 4.0', version: '2026-07', enabled: true,
      }],
    };
    const saved = await fetch(`${baseUrl}/admin-api/discovery/search-profile`, {
      method: 'PUT', headers, body: JSON.stringify(profile),
    });
    assert.equal(saved.status, 200);
    const text = await saved.text();
    assert.equal(text.includes('tavily-secret-9876'), false);
    const body = JSON.parse(text);
    assert.equal(body.profile.apiKey.lastFour, '9876');
    assert.equal(body.profile.sourcePolicies[0].version, '2026-07');
    const read = await fetch(`${baseUrl}/admin-api/discovery/search-profile`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal((await read.text()).includes('tavily-secret-9876'), false);
  });
});
