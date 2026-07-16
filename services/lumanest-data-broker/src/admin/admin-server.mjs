import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

import { isLanAddress } from './lan-address.mjs';
import { publicProviderCatalog } from '../llm/provider-catalog.mjs';
import { validateLLMProfile } from '../llm/profile.mjs';
import { validateDiscoverySearchProfile } from '../discovery/search-profile.mjs';

const maximumBodyBytes = 16 * 1024;
const maximumImportBodyBytes = 2 * 1024 * 1024;
const publicRoot = new URL('./public/', import.meta.url);
const staticAssets = new Map([
  ['/admin', ['index.html', 'text/html; charset=utf-8']],
  ['/admin/', ['index.html', 'text/html; charset=utf-8']],
  ['/admin-assets/styles.css', ['styles.css', 'text/css; charset=utf-8']],
  ['/admin-assets/llm.css', ['llm.css', 'text/css; charset=utf-8']],
  ['/admin-assets/app.js', ['app.js', 'text/javascript; charset=utf-8']],
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

function safeConfiguration(snapshot) {
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
    settings: snapshot.settings,
  };
}

export function createAdminServer({
  authService,
  runtimeConfig,
  auditLog,
  testConnection = async () => ({ status: 'ok' }),
  testLLMProfile = async (profileId) => ({ status: 'profile_not_found', profileId }),
  listLLMModels = async () => ({ ok: false, error: 'upstream_unavailable' }),
  listContextSources = async () => ({ ok: false, error: 'not_configured' }),
  importContextDataset = async () => ({ ok: false, error: 'not_configured' }),
  clearCache = async () => {},
  restart = async () => {},
}) {
  return createServer(async (request, response) => {
    const remoteAddress = request.socket.remoteAddress;
    if (!isLanAddress(remoteAddress)) {
      json(response, 403, { error: 'lan_only' });
      return;
    }
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && await serveStatic(url.pathname, response)) return;

    if (request.method === 'POST' && url.pathname === '/admin-api/login') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (typeof parsed.value?.password !== 'string') return json(response, 400, { error: 'invalid_request' });
      const result = await authService.login({ password: parsed.value.password, ipAddress: remoteAddress });
      auditLog.record({ remoteAddress, operation: 'login', result: result.ok ? 'ok' : result.reason });
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
      return json(response, 200, safeConfiguration(runtimeConfig.snapshot()));
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
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      try {
        const current = runtimeConfig.snapshot().discoverySearchProfile;
        const profile = validateDiscoverySearchProfile(parsed.value, { existing: current });
        const snapshot = await runtimeConfig.replace({ discoverySearchProfile: profile });
        auditLog.record({
          remoteAddress,
          operation: 'update_discovery_search_profile',
          fields: Object.keys(parsed.value).filter((field) => field !== 'apiKey'),
          result: 'ok',
        });
        return json(response, 200, { profile: safeDiscoverySearchProfile(snapshot.discoverySearchProfile) });
      } catch {
        auditLog.record({ remoteAddress, operation: 'update_discovery_search_profile', result: 'rejected' });
        return json(response, 400, { error: 'invalid_search_profile' });
      }
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/context/sources') {
      const result = await listContextSources();
      auditLog.record({
        remoteAddress,
        operation: 'list_context_sources',
        result: result.ok ? 'ok' : result.error,
      });
      return json(response, result.ok ? 200 : 503, result.ok
        ? { sources: result.sources }
        : { sources: [], error: result.error });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/context/imports') {
      const parsed = await body(request, maximumImportBodyBytes);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      const result = await importContextDataset(parsed.value);
      auditLog.record({
        remoteAddress,
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
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      try {
        const existing = (runtimeConfig.snapshot().llmProfiles ?? []).find((profile) =>
          profile.id === parsed.value.id) ?? null;
        const profile = validateLLMProfile(parsed.value, { existing });
        const result = await listLLMModels(profile);
        auditLog.record({
          remoteAddress, operation: 'list_llm_models', fields: ['providerId'],
          result: result.ok ? 'ok' : result.error,
        });
        return json(response, 200, result.ok ? { models: result.models } : { models: [], error: result.error });
      } catch {
        return json(response, 400, { error: 'invalid_profile' });
      }
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/llm/profiles') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      try {
        const current = runtimeConfig.snapshot();
        if ((current.llmProfiles ?? []).some((profile) => profile.id === parsed.value.id)) {
          return json(response, 409, { error: 'profile_exists' });
        }
        const snapshot = await runtimeConfig.replace({
          llmProfiles: [...(current.llmProfiles ?? []), parsed.value],
        });
        const profile = snapshot.llmProfiles.find((candidate) => candidate.id === parsed.value.id);
        auditLog.record({ remoteAddress, operation: 'create_llm_profile', fields: ['id', 'providerId'], result: 'ok' });
        return json(response, 201, { profile: safeLLMProfile(profile) });
      } catch {
        auditLog.record({ remoteAddress, operation: 'create_llm_profile', result: 'rejected' });
        return json(response, 400, { error: 'invalid_profile' });
      }
    }
    const profileMatch = /^\/admin-api\/llm\/profiles\/([a-z0-9][a-z0-9_-]*)$/.exec(url.pathname);
    const profileTestMatch = /^\/admin-api\/llm\/profiles\/([a-z0-9][a-z0-9_-]*)\/test$/.exec(url.pathname);
    if (request.method === 'POST' && profileTestMatch != null) {
      const profileId = profileTestMatch[1];
      const result = await testLLMProfile(profileId);
      auditLog.record({ remoteAddress, operation: 'test_llm_profile', fields: ['profileId'], result: result.status });
      return json(response, 200, result);
    }
    if (profileMatch != null && request.method === 'PUT') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      const profileId = profileMatch[1];
      try {
        const current = runtimeConfig.snapshot();
        const existing = (current.llmProfiles ?? []).find((profile) => profile.id === profileId);
        if (existing == null) return json(response, 404, { error: 'profile_not_found' });
        const next = { ...existing, ...parsed.value, id: profileId };
        const snapshot = await runtimeConfig.replace({
          llmProfiles: current.llmProfiles.map((profile) => profile.id === profileId ? next : profile),
        });
        const profile = snapshot.llmProfiles.find((candidate) => candidate.id === profileId);
        auditLog.record({ remoteAddress, operation: 'update_llm_profile', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, { profile: safeLLMProfile(profile) });
      } catch {
        return json(response, 400, { error: 'invalid_profile' });
      }
    }
    if (profileMatch != null && request.method === 'DELETE') {
      const parsed = await body(request);
      const profileId = profileMatch[1];
      if (parsed.value?.confirmId !== profileId) return json(response, 400, { error: 'confirmation_required' });
      try {
        const current = runtimeConfig.snapshot();
        if (!(current.llmProfiles ?? []).some((profile) => profile.id === profileId)) {
          return json(response, 404, { error: 'profile_not_found' });
        }
        await runtimeConfig.replace({
          llmProfiles: current.llmProfiles.filter((profile) => profile.id !== profileId),
        });
        auditLog.record({ remoteAddress, operation: 'delete_llm_profile', fields: ['profileId'], result: 'ok' });
        return json(response, 200, { ok: true });
      } catch {
        return json(response, 400, { error: 'profile_referenced' });
      }
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/llm/routing') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      try {
        const snapshot = await runtimeConfig.replace({ llmRouting: parsed.value });
        auditLog.record({ remoteAddress, operation: 'update_llm_routing', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, { routing: snapshot.llmRouting });
      } catch {
        return json(response, 400, { error: 'invalid_routing' });
      }
    }
    if (request.method === 'PUT' && url.pathname === '/admin-api/config') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      if (parsed.value == null) return json(response, 400, { error: 'invalid_request' });
      try {
        const snapshot = await runtimeConfig.replace(parsed.value);
        auditLog.record({ remoteAddress, operation: 'update_config', fields: Object.keys(parsed.value), result: 'ok' });
        return json(response, 200, safeConfiguration(snapshot));
      } catch {
        auditLog.record({ remoteAddress, operation: 'update_config', fields: Object.keys(parsed.value), result: 'rejected' });
        return json(response, 400, { error: 'invalid_configuration' });
      }
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/test-connection') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      return json(response, 200, await testConnection(parsed.value ?? {}));
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/change-password') {
      const parsed = await body(request);
      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
      try {
        await authService.changePassword(parsed.value?.password);
        auditLog.record({ remoteAddress, operation: 'change_password', result: 'ok' });
        return json(response, 200, { ok: true }, {
          'Set-Cookie': 'lumanest_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0',
        });
      } catch {
        return json(response, 400, { error: 'invalid_password' });
      }
    }
    if (request.method === 'GET' && url.pathname === '/admin-api/audit') {
      return json(response, 200, { entries: auditLog.list() });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/clear-cache') {
      await clearCache();
      auditLog.record({ remoteAddress, operation: 'clear_cache', result: 'ok' });
      return json(response, 200, { ok: true });
    }
    if (request.method === 'POST' && url.pathname === '/admin-api/restart') {
      auditLog.record({ remoteAddress, operation: 'restart', result: 'accepted' });
      json(response, 202, { ok: true });
      setImmediate(() => restart());
      return;
    }
    json(response, 404, { error: 'not_found' });
  });
}
