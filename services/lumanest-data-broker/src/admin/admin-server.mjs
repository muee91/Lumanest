import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

import { isLanAddress } from './lan-address.mjs';
import { publicProviderCatalog } from '../llm/provider-catalog.mjs';
import { validateLLMProfile } from '../llm/profile.mjs';
import { validateDiscoverySearchProfile } from '../discovery/search-profile.mjs';
import { simulationPresetCatalog } from '../context/simulation.mjs';
import { providerSourceDefaults, publicProviderSourceCatalog, safeProviderSources } from '../environment/provider-runtime-config.mjs';
import { apiErrorCodes } from '../api/error-codes.mjs';

const maximumBodyBytes = 16 * 1024;
const maximumImportBodyBytes = 2 * 1024 * 1024;
const publicRoot = new URL('./public/', import.meta.url);
const staticAssets = new Map([
  ['/admin', ['index.html', 'text/html; charset=utf-8']],
  ['/admin/', ['index.html', 'text/html; charset=utf-8']],
  ['/admin-assets/styles.css', ['styles.css', 'text/css; charset=utf-8']],
  ['/admin-assets/llm.css', ['llm.css', 'text/css; charset=utf-8']],
  ['/admin-assets/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/admin-assets/providers.js', ['providers.js', 'text/javascript; charset=utf-8']],
  ['/admin-assets/observability.js', ['observability.js', 'text/javascript; charset=utf-8']],
  ['/admin-assets/observability.css', ['observability.css', 'text/css; charset=utf-8']],
]);
const contentSecurityPolicy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'";

async function serveStatic(pathname, response) {
  const asset = staticAssets.get(pathname);
  if (asset == null) return false;
  const [fileName, contentType] = asset;
  const contents = await readFile(new URL(fileName, publicRoot));
  response.writeHead(200, {
    'Content-Type': contentType,
    'Content-Security-Policy': contentSecurityPolicy,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
  });
  response.end(contents);
  return true;
}

function json(response, status, body, headers = {}) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...headers,
  });
  response.end(JSON.stringify(body));
}

async function body(request, maximumBytes = maximumBodyBytes) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumBytes) return { tooLarge: true };
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    return value && typeof value === 'object' && !Array.isArray(value) ? { value } : {};
  } catch {
    return {};
  }
}

function cookieToken(header) {
  if (typeof header !== 'string') return null;
  for (const item of header.split(';')) {
    const [name, ...parts] = item.trim().split('=');
    if (name === 'lumanest_admin') return parts.join('=') || null;
  }
  return null;
}

function maskedSecret(value) {
  const configured = typeof value === 'string' && value.length > 0;
  return { configured, lastFour: configured ? [...value].slice(-4).join('') : null };
}

function safeLLMProfile(profile) {
  return {
    id: profile.id,
    name: profile.name,
    providerId: profile.providerId,
    protocol: profile.protocol,
    apiKey: maskedSecret(profile.apiKey),
    baseUrl: profile.baseUrl,
    model: profile.model,
    enabled: profile.enabled,
    timeoutMs: profile.timeoutMs,
    allowFallback: profile.allowFallback,
  };
}

function safeDiscoverySearchProfile(profile) {
  return {
    baseUrl: profile?.baseUrl ?? 'https://api.tavily.com',
    apiKey: maskedSecret(profile?.apiKey),
    enabled: profile?.enabled ?? false,
    timeoutMs: profile?.timeoutMs ?? 8_000,
    sourcePolicies: profile?.sourcePolicies ?? [],
  };
}

const auditHealthErrorCodes = new Set([
  'EACCES', 'ENOENT', 'EISDIR', 'ENOSPC', 'EROFS',
  'write_failed', 'read_failed', 'corrupt_file',
]);

function safeAuditLogHealth(raw) {
  const source = raw != null && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};

  // entries: finite non-negative integer, bounded to a sane maximum.
  let entries = 0;
  if (typeof source.entries === 'number' && Number.isFinite(source.entries) && source.entries >= 0) {
    entries = Math.min(Math.trunc(source.entries), Number.MAX_SAFE_INTEGER);
  }

  // lastWriteAt: only a valid ISO 8601 string or null.
  let lastWriteAt = null;
  if (typeof source.lastWriteAt === 'string') {
    const parsed = new Date(source.lastWriteAt);
    if (Number.isFinite(parsed.getTime()) && source.lastWriteAt.trim().length > 0) {
      lastWriteAt = source.lastWriteAt;
    }
  }

  // lastWriteOk: strictly true/false/null.
  let lastWriteOk = null;
  if (source.lastWriteOk === true) lastWriteOk = true;
  else if (source.lastWriteOk === false) lastWriteOk = false;

  // lastWriteError: only a finite stable error code or null.
  let lastWriteError = null;
  if (typeof source.lastWriteError === 'string' && auditHealthErrorCodes.has(source.lastWriteError)) {
    lastWriteError = source.lastWriteError;
  }

  return { entries, lastWriteAt, lastWriteOk, lastWriteError };
}

function safeConfiguration(snapshot, outboundNetwork) {
  return {
    revision: snapshot.revision,
    services: {
      qweatherPrivateKey: { configured: snapshot.privateKey != null, lastFour: null },
      keyId: maskedSecret(snapshot.keyId),
      projectId: maskedSecret(snapshot.projectId),
      serviceToken: maskedSecret(snapshot.serviceToken),
      amapWebKey: maskedSecret(snapshot.amapWebKey),
    },
    llm: {
      profileCount: snapshot.llmProfiles?.length ?? 0,
      primaryProfileId: snapshot.llmRouting?.primaryProfileId ?? null,
      fallbackEnabled: snapshot.llmRouting?.fallbackEnabled ?? false,
    },
    discoverySearch: safeDiscoverySearchProfile(snapshot.discoverySearchProfile),
    providers: {
      catalog: publicProviderSourceCatalog(),
      configuration: safeProviderSources(snapshot.providerSources ?? providerSourceDefaults()),
    },
    settings: snapshot.settings,
    outboundNetwork,
  };
}

export function createAdminServer({
  authService,
  runtimeConfig,
  auditLog,
  testConnection = async () => ({ status: 'ok' }),
  testLLMProfile = async (profileId) => ({ status: 'profile_not_found', profileId }),
  listLLMModels = async () => ({ ok: false, error: apiErrorCodes.upstreamUnavailable }),
  listContextSources = async () => ({ ok: false, error: apiErrorCodes.notConfigured }),
  getSevenTimerHealth = async () => ({ provider: '7timer', enabled: false, status: 'unknown', products: [] }),
  getBrokerHealth = async () => ({ status: 'unknown' }),
  getProviderHealth = async () => ({ provider: 'providerHub', enabled: false, providers: [], cache: {} }),
  getOperationalObservability = async () => ({
    contractVersion: 1, checkedAt: new Date().toISOString(),
    privacy: {}, regionBrief: {}, assistantContext: {}, providers: {},
  }),
  testProvider = async () => ({ ok: false, error: apiErrorCodes.notConfigured }),
  getAuditLogHealth = () => ({ entries: 0, lastWriteAt: null, lastWriteOk: null, lastWriteError: null }),
  testSevenTimer = async () => ({ ok: false, error: apiErrorCodes.notConfigured }),
  getShootingCalibration = async () => ({ ok: false, error: apiErrorCodes.notConfigured }),
  importContextDataset = async () => ({ ok: false, error: apiErrorCodes.notConfigured }),
  simulationEnabled = false,
  simulationRegistry = null,
  clearCache = async () => {},
  restart = async () => {},
  outboundNetworkController = null,
}) {
  return createServer(async (request, response) => {
    const remoteAddress = request.socket.remoteAddress;
    if (!isLanAddress(remoteAddress)) {
      json(response, 403, { error: apiErrorCodes.lanOnly });
      return;
    }
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && await serveStatic(url.pathname, response)) return;

    if (request.method === 'POST' && url.pathname === '/admin-api/login') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (typeof parsed.value?.password !== 'string') return json(response, 400, { error: apiErrorCodes.invalidRequest });
      const result = await authService.login({ password: parsed.value.password, ipAddress: remoteAddress });
      auditLog.record({ operation: 'login', result: result.ok ? 'ok' : result.reason });
      if (!result.ok) return json(response, result.reason === 'rate_limited' ? 429 : 401, { error: result.reason });
      return json(response, 200, { authenticated: true, csrfToken: result.csrfToken }, { 'Set-Cookie': result.cookie });
    }

    const sessionToken = cookieToken(request.headers.cookie);
    const changing = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method);
    const authentication = await authService.authenticate({
      sessionToken,
      csrfToken: request.headers['x-csrf-token'],
      requireCsrf: changing,
    });
    if (!authentication.ok) {
      const status = authentication.reason === 'csrf_mismatch' ? 403 : 401;
      return json(response, status, { error: authentication.reason });
    }

    if (request.method === 'GET' && url.pathname === '/admin-api/session') {
      const csrfToken = await authService.issueCsrf(sessionToken);
      return json(response, 200, { authenticated: true, csrfToken });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/logout') {
      await authService.logout(sessionToken);
      return json(response, 200, { ok: true }, {
        'Set-Cookie': 'lumanest_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0',
      });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/config') {
      const outboundNetwork = outboundNetworkController == null
        ? { status: 'unavailable', error: apiErrorCodes.controllerNotConfigured }
        : await outboundNetworkController.status();
      return json(response, 200, safeConfiguration(runtimeConfig.snapshot(), outboundNetwork));
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/capabilities') {
      return json(response, 200, {
        developerTools: { simulationEnabled: simulationEnabled && simulationRegistry != null },
      });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/services/7timer') {
      return json(response, 200, await getSevenTimerHealth());
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/providers/health') {
      return json(response, 200, await getProviderHealth());
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/observability') {
      return json(response, 200, await getOperationalObservability());
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/providers/test') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      const { providerId, latitude, longitude, radiusKm = 25 } = parsed.value ?? {};
      if (typeof providerId !== 'string' || typeof latitude !== 'number' || latitude < -90 || latitude > 90 ||
          typeof longitude !== 'number' || longitude < -180 || longitude > 180 ||
          typeof radiusKm !== 'number' || radiusKm < 1 || radiusKm > 50) {
        return json(response, 400, { error: apiErrorCodes.invalidRequest });
      }
      const result = await testProvider({ providerId, latitude, longitude, radiusKm });
      auditLog.record({ operation: 'test_provider', fields: ['providerId'], result: result.ok ? 'ok' : result.error, details: { providerId, traceId: result.traceId ?? null } });
      return json(response, result.ok ? 200 : result.error === 'invalid_request' ? 400 : 503, result);
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/health') {
      const [runtime, sevenTimer, providerHub] = await Promise.all([getBrokerHealth(), getSevenTimerHealth(), getProviderHealth()]);
      const audit = safeAuditLogHealth(getAuditLogHealth());
      const auditDegraded = audit.lastWriteOk === false;
      const status = runtime.status === 'healthy'
        && ['healthy', 'unknown', 'disabled'].includes(sevenTimer.status)
        && !auditDegraded
        ? 'healthy' : 'degraded';
      return json(response, 200, {
        status,
        checkedAt: new Date().toISOString(),
        runtime,
        services: { sevenTimer, providerHub },
        audit,
      });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/services/7timer/test') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      const { product, latitude, longitude } = parsed.value ?? {};
      if (!['astro', 'meteo', 'two'].includes(product) ||
          typeof latitude !== 'number' || latitude < -90 || latitude > 90 ||
          typeof longitude !== 'number' || longitude < -180 || longitude > 180) {
        return json(response, 400, { error: apiErrorCodes.invalidRequest });
      }
      const result = await testSevenTimer({ product, latitude, longitude });
      auditLog.record({
        operation: 'test_7timer',
        fields: ['product'],
        result: result.ok ? 'ok' : result.error,
        details: { product, traceId: result.traceId ?? null },
      });
      const testStatus = result.ok ? 200 : result.error === 'disabled' ? 409
        : ['test_in_progress', 'test_cooldown', 'test_busy'].includes(result.error) ? 429 : 503;
      return json(response, testStatus, result.ok
        ? { ok: true, product, traceId: result.traceId, pointCount: result.body.points.length, sourceInitAt: result.body.sourceInitAt, sourceStatus: result.body.sourceStatus }
        : { ok: false, product, error: result.error, traceId: result.traceId ?? null, retryAfterSeconds: result.retryAfterSeconds ?? null });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/llm/providers') {
      return json(response, 200, { providers: publicProviderCatalog() });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/discovery/search-profile') {
      return json(response, 200, {
        profile: safeDiscoverySearchProfile(runtimeConfig.snapshot().discoverySearchProfile),
      });
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/discovery/search-profile') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      try {
        const current = runtimeConfig.snapshot().discoverySearchProfile;
        const profile = validateDiscoverySearchProfile(parsed.value, { existing: current });
        const snapshot = await runtimeConfig.replace({ discoverySearchProfile: profile });
        auditLog.record({
          operation: 'update_discovery_search_profile',
          fields: Object.keys(parsed.value).filter((field) => field !== 'apiKey'),
          result: 'ok',
        });
        return json(response, 200, { profile: safeDiscoverySearchProfile(snapshot.discoverySearchProfile) });
      } catch {
        auditLog.record({ operation: 'update_discovery_search_profile', result: 'rejected' });
        return json(response, 400, { error: apiErrorCodes.invalidSearchProfile });
      }
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/context/sources') {
      const result = await listContextSources();
      auditLog.record({
        operation: 'list_context_sources',
        result: result.ok ? 'ok' : result.error,
      });
      return json(response, result.ok ? 200 : 503, result.ok
        ? { sources: result.sources }
        : { sources: [], error: result.error });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/context/shooting-calibration') {
      const rawDays = url.searchParams.get('days') ?? '90';
      const rawMinimum = url.searchParams.get('minimumSamples') ?? '5';
      const days = /^\d{1,3}$/.test(rawDays) ? Number.parseInt(rawDays, 10) : NaN;
      const minimumSamples = /^\d{1,3}$/.test(rawMinimum)
        ? Number.parseInt(rawMinimum, 10)
        : NaN;
      if (!Number.isInteger(days) || days < 30 || days > 365 ||
          !Number.isInteger(minimumSamples) || minimumSamples < 5 || minimumSamples > 100) {
        return json(response, 400, { error: apiErrorCodes.invalidRequest });
      }
      const result = await getShootingCalibration({ days, minimumSamples });
      auditLog.record({
        operation: 'read_shooting_calibration',
        fields: ['days', 'minimumSamples'],
        result: result.ok ? 'ok' : result.error,
      });
      return json(response, result.ok ? 200 : 503, result.ok
        ? result.report
        : { error: result.error });
    }
    if (url.pathname.startsWith('/admin-api/simulation') &&
        (!simulationEnabled || simulationRegistry == null)) {
      return json(response, 404, { error: apiErrorCodes.notFound });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/simulation') {
      return json(response, 200, {
        presets: simulationPresetCatalog(),
        sessions: simulationRegistry.list(),
      });
    }
    if (request.method === 'DELETE' && url.pathname === '/admin-api/simulation/sessions') {
      const result = simulationRegistry.clearAll();
      auditLog.record({
        operation: 'clear_all_simulations',
        result: 'ok',
      });
      return json(response, 200, result);
    }
    const simulationMatch = /^\/admin-api\/simulation\/sessions\/(sim_[a-f0-9]{24})$/.exec(url.pathname);
    if (simulationMatch != null && request.method === 'POST') {
      const parsed = await body(request);
      if (parsed.tooLarge || typeof parsed.value?.preset !== 'string') {
        return json(response, 400, { error: apiErrorCodes.invalidSimulationRequest });
      }
      const result = simulationRegistry.activate(simulationMatch[1], parsed.value.preset);
      auditLog.record({ operation: 'activate_simulation', fields: ['preset'], result: result.ok ? 'ok' : result.error });
      return json(response, result.ok ? 200 : 404, result);
    }
    if (simulationMatch != null && request.method === 'DELETE') {
      const result = simulationRegistry.clear(simulationMatch[1]);
      auditLog.record({ operation: 'clear_simulation', result: result.ok ? 'ok' : result.error });
      return json(response, result.ok ? 200 : 404, result);
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/context/imports') {
      const parsed = await body(request, maximumImportBodyBytes);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      const result = await importContextDataset(parsed.value);
      auditLog.record({
        operation: 'import_context_dataset',
        fields: ['sourceId', 'datasetType'],
        result: result.ok ? 'ok' : result.error,
      });
      if (result.ok) return json(response, 201, result.result);
      return json(response, result.error === 'invalid_import' ? 422 : 503, {
        error: result.error,
      });
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/llm/profiles') {
      const snapshot = runtimeConfig.snapshot();
      return json(response, 200, {
        profiles: (snapshot.llmProfiles ?? []).map(safeLLMProfile),
        routing: snapshot.llmRouting,
      });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/llm/models') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      try {
        const existing = (runtimeConfig.snapshot().llmProfiles ?? []).find((profile) =>
          profile.id === parsed.value.id) ?? null;
        const profile = validateLLMProfile(parsed.value, { existing });
        const result = await listLLMModels(profile);
        auditLog.record({
          operation: 'list_llm_models', fields: ['providerId'],
          result: result.ok ? 'ok' : result.error,
        });
        return json(response, 200, result.ok ? { models: result.models } : { models: [], error: result.error });
      } catch {
        return json(response, 400, { error: apiErrorCodes.invalidProfile });
      }
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/llm/profiles') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      try {
        const current = runtimeConfig.snapshot();
        if ((current.llmProfiles ?? []).some((profile) => profile.id === parsed.value.id)) {
          return json(response, 409, { error: apiErrorCodes.profileExists });
        }
        const snapshot = await runtimeConfig.replace({
          llmProfiles: [...(current.llmProfiles ?? []), parsed.value],
        });
        const profile = snapshot.llmProfiles.find((candidate) => candidate.id === parsed.value.id);
        auditLog.record({ operation: 'create_llm_profile', fields: ['id', 'providerId'], result: 'ok' });
        return json(response, 201, { profile: safeLLMProfile(profile) });
      } catch {
        auditLog.record({ operation: 'create_llm_profile', result: 'rejected' });
        return json(response, 400, { error: apiErrorCodes.invalidProfile });
      }
    }
    const profileMatch = /^\/admin-api\/llm\/profiles\/([a-z0-9][a-z0-9_-]*)$/.exec(url.pathname);
    const profileTestMatch = /^\/admin-api\/llm\/profiles\/([a-z0-9][a-z0-9_-]*)\/test$/.exec(url.pathname);
    if (request.method === 'POST' && profileTestMatch != null) {
      const profileId = profileTestMatch[1];
      const result = await testLLMProfile(profileId);
      auditLog.record({ operation: 'test_llm_profile', fields: ['profileId'], result: result.status });
      return json(response, 200, result);
    }
    if (profileMatch != null && request.method === 'PUT') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      const profileId = profileMatch[1];
      try {
        const current = runtimeConfig.snapshot();
        const existing = (current.llmProfiles ?? []).find((profile) => profile.id === profileId);
        if (existing == null) return json(response, 404, { error: apiErrorCodes.profileNotFound });
        const next = { ...existing, ...parsed.value, id: profileId };
        const snapshot = await runtimeConfig.replace({
          llmProfiles: current.llmProfiles.map((profile) => profile.id === profileId ? next : profile),
        });
        const profile = snapshot.llmProfiles.find((candidate) => candidate.id === profileId);
        auditLog.record({ operation: 'update_llm_profile', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, { profile: safeLLMProfile(profile) });
      } catch {
        return json(response, 400, { error: apiErrorCodes.invalidProfile });
      }
    }
    if (profileMatch != null && request.method === 'DELETE') {
      const parsed = await body(request);
      const profileId = profileMatch[1];
      if (parsed.value?.confirmId !== profileId) return json(response, 400, { error: apiErrorCodes.confirmationRequired });
      try {
        const current = runtimeConfig.snapshot();
        if (!(current.llmProfiles ?? []).some((profile) => profile.id === profileId)) {
          return json(response, 404, { error: apiErrorCodes.profileNotFound });
        }
        await runtimeConfig.replace({
          llmProfiles: current.llmProfiles.filter((profile) => profile.id !== profileId),
        });
        auditLog.record({ operation: 'delete_llm_profile', fields: ['profileId'], result: 'ok' });
        return json(response, 200, { ok: true });
      } catch {
        return json(response, 400, { error: apiErrorCodes.profileReferenced });
      }
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/llm/routing') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      try {
        const snapshot = await runtimeConfig.replace({ llmRouting: parsed.value });
        auditLog.record({ operation: 'update_llm_routing', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, { routing: snapshot.llmRouting });
      } catch {
        return json(response, 400, { error: apiErrorCodes.invalidRouting });
      }
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/config') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (parsed.value == null) return json(response, 400, { error: apiErrorCodes.invalidRequest });
      try {
        const snapshot = await runtimeConfig.replace(parsed.value);
        auditLog.record({ operation: 'update_config', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, safeConfiguration(snapshot));
      } catch {
        auditLog.record({ operation: 'update_config', fields: Object.keys(parsed.value), result: 'rejected' });
        return json(response, 400, { error: apiErrorCodes.invalidConfiguration });
      }
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/test-connection') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      return json(response, 200, await testConnection(parsed.value ?? {}));
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/outbound-network') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      if (typeof parsed.value?.mode !== 'string' || outboundNetworkController == null) {
        return json(response, 400, { error: apiErrorCodes.invalidRequest });
      }
      const result = await outboundNetworkController.apply(parsed.value);
      const accepted = result.accepted === true;
      auditLog.record({
        operation: 'update_outbound_network',
        fields: ['mode'],
        result: accepted ? 'accepted' : result.error ?? 'rejected',
      });
      return json(response, accepted ? 202 : 503, result);
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/change-password') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: apiErrorCodes.bodyTooLarge });
      const { currentPassword, newPassword, confirmPassword } = parsed.value ?? {};
      if (typeof currentPassword !== 'string' || typeof newPassword !== 'string' ||
          typeof confirmPassword !== 'string') {
        return json(response, 400, { error: apiErrorCodes.invalidRequest });
      }
      if (newPassword !== confirmPassword) {
        return json(response, 400, { error: apiErrorCodes.passwordMismatch });
      }
      try {
        const result = await authService.changePassword(newPassword, { currentPassword });
        if (!result.ok) {
          auditLog.record({ operation: 'change_password', result: result.reason });
          return json(response, 401, { error: result.reason });
        }
        auditLog.record({ operation: 'change_password', result: 'ok' });
        return json(response, 200, { ok: true }, {
          'Set-Cookie': 'lumanest_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0',
        });
      } catch {
        auditLog.record({ operation: 'change_password', result: 'invalid_password' });
        return json(response, 400, { error: apiErrorCodes.invalidPassword });
      }
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/audit') {
      return json(response, 200, { entries: await auditLog.list() });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/clear-cache') {
      try {
        await clearCache();
        auditLog.record({ operation: 'clear_cache', result: 'ok' });
        return json(response, 200, { ok: true });
      } catch {
        auditLog.record({ operation: 'clear_cache', result: 'failed' });
        return json(response, 503, { error: apiErrorCodes.cacheClearFailed });
      }
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/restart') {
      // The restart audit entry must reach disk before the process exits.
      // record() returns a promise that resolves once the encrypted write
      // completes; we await it here so the entry is not silently lost.
      const writePromise = auditLog.record({ operation: 'restart', result: 'accepted' });
      json(response, 202, { ok: true });
      setImmediate(async () => {
        await writePromise;
        await auditLog.flush();
        restart();
      });
      return;
    }
    json(response, 404, { error: apiErrorCodes.notFound });
  });
}
