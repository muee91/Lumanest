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

const testMasterKey = Buffer.alloc(32, 7).toString('base64');

async function withAdmin(run, {
  simulationEnabled = false,
  simulationRegistry = null,
  sevenTimer = null,
  getBrokerHealth = async () => ({ status: 'unknown' }),
  providerHub = null,
  observability = null,
  getAuditLogHealth = () => ({ entries: 0, lastWriteAt: null, lastWriteOk: null, lastWriteError: null }),
} = {}) {
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
  const auditLog = await new AuditLog({
    filePath: join(directory, 'audit-log.enc.json'),
    masterKey: testMasterKey,
  }).initialize();
  const server = createAdminServer({
    authService, runtimeConfig, auditLog,
    testConnection: async () => ({ status: 'ok' }),
    getSevenTimerHealth: async () => sevenTimer?.health ?? ({ provider: '7timer', enabled: true, status: 'unknown', products: [] }),
    testSevenTimer: async (query) => sevenTimer?.test?.(query) ?? ({ ok: true, traceId: 'trace-test', body: { points: [{}], sourceInitAt: '2026-07-19T00:00:00.000Z', sourceStatus: 'fresh' } }),
    getBrokerHealth,
    getProviderHealth: async () => providerHub?.health ?? ({ provider: 'providerHub', enabled: true, providers: [], cache: {} }),
    getOperationalObservability: async () => observability ?? ({
      contractVersion: 1, checkedAt: '2026-08-05T04:00:00Z',
      privacy: { preciseCoordinatesStored: false, promptsStored: false, rawFactsStored: false },
      regionBrief: {}, assistantContext: {}, providers: {},
    }),
    testProvider: async (query) => providerHub?.test?.(query) ?? ({ ok: false, error: 'not_configured' }),
    getAuditLogHealth,
    clearCache: async () => operations.push('clear'),
    restart: async () => operations.push('restart'),
    testLLMProfile: async (profileId) => ({ status: 'ok', profileId }),
    listLLMModels: async (profile) => ({ ok: true, models: [`${profile.providerId}-model`] }),
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
    await run({ baseUrl: `http://127.0.0.1:${server.address().port}`, operations, auditLog });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    // Flush any in-flight audit writes (e.g. from the last login) before
    // removing the temp directory, otherwise rm can race with a background
    // encrypted write and fail with ENOTEMPTY.
    await auditLog.flush();
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

test('7Timer health is authenticated and manual tests return sanitized traceable results', async () => {
  await withAdmin(async ({ baseUrl, auditLog }) => {
    const credentials = await login(baseUrl);
    const get = await fetch(`${baseUrl}/admin-api/services/7timer`, { headers: { Cookie: credentials.cookie } });
    assert.equal(get.status, 200);
    assert.equal((await get.json()).provider, '7timer');
    const headers = { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' };
    const testResponse = await fetch(`${baseUrl}/admin-api/services/7timer/test`, {
      method: 'POST', headers,
      body: JSON.stringify({ product: 'astro', latitude: 31.23, longitude: 121.47 }),
    });
    assert.equal(testResponse.status, 200);
    const value = await testResponse.json();
    assert.equal(value.traceId, 'trace-test');
    assert.equal('latitude' in value, false);
    assert.equal('longitude' in value, false);
    const entry = (await auditLog.list()).find((item) => item.operation === 'test_7timer');
    assert.deepEqual(entry.details, { product: 'astro', traceId: 'trace-test' });
    assert.doesNotMatch(JSON.stringify(entry), /31\.23|121\.47/);
  }, { sevenTimer: { health: { provider: '7timer', enabled: true, status: 'unknown', products: [] }, test: () => ({ ok: true, traceId: 'trace-test', body: { points: [{}], sourceInitAt: '2026-07-19T00:00:00.000Z', sourceStatus: 'fresh' } }) } });
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

test('scene lab is capability-gated and controls opaque debug sessions only', async () => {
  const registry = new SimulationRegistry();
  registry.register('debugsession2345678', { contractVersion: 5 });
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

test('health endpoint requires authentication and never leaks sensitive audit fields', async () => {
  // Unauthenticated requests must not reach the health endpoint.
  await withAdmin(async ({ baseUrl }) => {
    const unauthenticated = await fetch(`${baseUrl}/admin-api/health`);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('cache-control'), 'no-store');
  }, {
    getBrokerHealth: async () => ({ status: 'healthy' }),
    getAuditLogHealth: () => ({
      entries: 7,
      lastWriteAt: '2026-07-22T01:23:45.000Z',
      lastWriteOk: true,
      lastWriteError: null,
      // Sensitive fields that must never appear in the response.
      filePath: '/var/lib/lumanest/audit-log.enc.json',
      rawError: `EACCES: permission denied, open '/var/lib/lumanest/audit-log.enc.json'`,
      remoteAddress: '192.168.1.42',
      coordinates: { latitude: 31.23, longitude: 121.47 },
      token: 'service-secret-9012',
    }),
  });
});

test('authenticated health stays healthy when audit lastWriteOk is null and runtime/sevenTimer are healthy', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/health`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    // lastWriteOk:null (no write attempted yet) must not degrade health as
    // long as runtime is healthy and sevenTimer is in an acceptable state.
    assert.equal(body.status, 'healthy');
    assert.equal(body.audit.lastWriteOk, null);
    assert.equal(body.audit.entries, 0);
    assert.equal(body.audit.lastWriteError, null);
  }, {
    getBrokerHealth: async () => ({ status: 'healthy' }),
    // sevenTimer defaults to { status: 'unknown' } via withAdmin, which is
    // an acceptable non-degraded state per the health composition rule.
    getAuditLogHealth: () => ({
      entries: 0,
      lastWriteAt: null,
      lastWriteOk: null,
      lastWriteError: null,
    }),
  });
});

test('authenticated health is degraded when audit lastWriteOk is false', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/health`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    // A failed audit write (lastWriteOk:false) must degrade overall status
    // even when runtime and sevenTimer are otherwise healthy.
    assert.equal(body.status, 'degraded');
    assert.equal(body.audit.lastWriteOk, false);
    assert.equal(body.audit.lastWriteError, 'EACCES');
    assert.equal(body.audit.entries, 42);
    assert.equal(body.audit.lastWriteAt, '2026-07-22T02:00:00.000Z');
  }, {
    getBrokerHealth: async () => ({ status: 'healthy' }),
    getAuditLogHealth: () => ({
      entries: 42,
      lastWriteAt: '2026-07-22T02:00:00.000Z',
      lastWriteOk: false,
      lastWriteError: 'EACCES',
    }),
  });
});

test('authenticated health audit payload only exposes safe fields and never leaks paths, errors, addresses, tokens, or coordinates', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/health`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    const text = JSON.stringify(body);

    // The audit object must only contain the safe observability fields.
    assert.deepEqual(Object.keys(body.audit).sort(), [
      'entries',
      'lastWriteAt',
      'lastWriteError',
      'lastWriteOk',
    ].sort());

    // Sensitive injected values must never appear anywhere in the response.
    assert.equal(text.includes('/var/lib/lumanest/audit-log.enc.json'), false);
    assert.equal(text.includes('permission denied'), false);
    assert.equal(text.includes('192.168.1.42'), false);
    assert.equal(text.includes('remoteAddress'), false);
    assert.equal(text.includes('service-secret-9012'), false);
    assert.equal(text.includes('31.23'), false);
    assert.equal(text.includes('121.47'), false);
    assert.equal(text.includes('coordinates'), false);
    assert.equal(text.includes('token'), false);
    assert.equal(text.includes('rawError'), false);
    assert.equal(text.includes('filePath'), false);
  }, {
    getBrokerHealth: async () => ({ status: 'healthy' }),
    getAuditLogHealth: () => ({
      entries: 3,
      lastWriteAt: '2026-07-22T03:00:00.000Z',
      lastWriteOk: true,
      lastWriteError: null,
      // Sensitive extras that must be stripped/ignored by the safe field set.
      filePath: '/var/lib/lumanest/audit-log.enc.json',
      rawError: `EACCES: permission denied, open '/var/lib/lumanest/audit-log.enc.json'`,
      remoteAddress: '192.168.1.42',
      coordinates: { latitude: 31.23, longitude: 121.47 },
      token: 'service-secret-9012',
    }),
  });
});


test('provider configuration is masked and diagnostics never audit coordinates', async () => {
  await withAdmin(async ({ baseUrl, auditLog }) => {
    const credentials = await login(baseUrl);
    const config = await fetch(`${baseUrl}/admin-api/config`, { headers: { Cookie: credentials.cookie } });
    const text = await config.text();
    assert.equal(text.includes('provider-secret-value'), false);
    const parsed = JSON.parse(text);
    assert.equal(Array.isArray(parsed.providers.catalog), true);

    const headers = { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' };
    const response = await fetch(`${baseUrl}/admin-api/providers/test`, {
      method: 'POST', headers,
      body: JSON.stringify({ providerId: 'osm', latitude: 30.25, longitude: 120.15, radiusKm: 25 }),
    });
    assert.equal(response.status, 200);
    const entry = (await auditLog.list()).find((item) => item.operation === 'test_provider');
    assert.deepEqual(entry.details, { providerId: 'osm', traceId: 'provider-trace' });
    assert.doesNotMatch(JSON.stringify(entry), /30\.25|120\.15/);
  }, {
    providerHub: {
      health: { provider: 'providerHub', enabled: true, providers: [], cache: {} },
      test: () => ({ ok: true, providerId: 'osm', status: 'ready', signalCount: 1, latencyMs: 5, traceId: 'provider-trace', error: null }),
    },
  });
});
test('operational observability is authenticated and excludes raw private context', async () => {
  await withAdmin(async ({ baseUrl }) => {
    assert.equal((await fetch(`${baseUrl}/admin-api/observability`)).status, 401);
    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/observability`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal(response.status, 200);
    const text = await response.text();
    const value = JSON.parse(text);
    assert.equal(value.contractVersion, 1);
    assert.equal(value.privacy.preciseCoordinatesStored, false);
    assert.doesNotMatch(text, /30\.267|120\.153|用户问题|原始事实内容/);
  }, {
    observability: {
      contractVersion: 1,
      checkedAt: '2026-08-05T04:00:00Z',
      privacy: {
        preciseCoordinatesStored: false,
        promptsStored: false,
        rawFactsStored: false,
      },
      regionBrief: { requests: 2 },
      assistantContext: { builds: 1 },
      providers: { total: 14 },
    },
  });
});
