import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

import { isLanAddress } from './lan-address.mjs';

const maximumBodyBytes = 16 * 1024;
const publicRoot = new URL('./public/', import.meta.url);
const staticAssets = new Map([
  ['/admin', ['index.html', 'text/html; charset=utf-8']],
  ['/admin/', ['index.html', 'text/html; charset=utf-8']],
  ['/admin-assets/styles.css', ['styles.css', 'text/css; charset=utf-8']],
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

async function body(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumBodyBytes) return { tooLarge: true };
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

function safeConfiguration(snapshot) {
  return {
    revision: snapshot.revision,
    services: {
      qweatherPrivateKey: { configured: snapshot.privateKey != null, lastFour: null },
      keyId: maskedSecret(snapshot.keyId),
      projectId: maskedSecret(snapshot.projectId),
      serviceToken: maskedSecret(snapshot.serviceToken),
      amapWebKey: maskedSecret(snapshot.amapWebKey),
      aiApiKey: maskedSecret(snapshot.aiApiKey),
    },
    aiBaseUrl: snapshot.aiBaseUrl,
    aiModel: snapshot.aiModel,
    settings: snapshot.settings,
  };
}

export function createAdminServer({
  authService,
  runtimeConfig,
  auditLog,
  testConnection = async () => ({ status: 'ok' }),
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
