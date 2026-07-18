import { timingSafeEqual } from 'node:crypto';
import { createServer, request as httpRequest } from 'node:http';
import { access, readFile, realpath, writeFile, rename } from 'node:fs/promises';
import { join, relative } from 'node:path';

const validModes = new Set(['direct', 'mihomo']);
const managedServices = Object.freeze([
  ['qweather-token-broker', 'lumanest-qweather-token-broker'],
  ['context-service', 'lumanest-context-service'],
  ['discovery-api', 'lumanest-discovery-api'],
  ['discovery-worker', 'lumanest-discovery-worker'],
]);
const maximumBodyBytes = 1024;

function json(response, status, value) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(value));
}

function sameToken(value, expected) {
  if (typeof value !== 'string' || value.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(value), Buffer.from(expected));
}

async function requestBody(request) {
  let size = 0;
  const chunks = [];
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

export function modeFromEnvironment(value) {
  return value === 'mihomo' ? 'mihomo' : 'direct';
}

export function replaceEnvironmentValue(contents, name, value) {
  const expression = new RegExp(`^${name.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}=.*$`, 'm');
  const next = `${name}=${value}`;
  return expression.test(contents) ? contents.replace(expression, next) : `${contents.replace(/\n?$/, '\n')}${next}\n`;
}

function parseEnvironment(contents, name) {
  const line = contents.split(/\r?\n/).find((item) => item.startsWith(`${name}=`));
  return line?.slice(name.length + 1) ?? '';
}

async function currentRelease({ hostRoot, hostReleasePrefix }) {
  const raw = (await readFile(join(hostRoot, 'current-release'), 'utf8')).trim();
  const normalizedPrefix = `${hostReleasePrefix.replace(/\/$/, '')}/`;
  if (!raw.startsWith(normalizedPrefix)) throw new Error('invalid_release_marker');
  const relativeRelease = raw.slice(normalizedPrefix.length);
  if (relativeRelease.length === 0 || relativeRelease.includes('..')) throw new Error('invalid_release_marker');
  const root = await realpath(hostRoot);
  const candidate = await realpath(join(hostRoot, relativeRelease));
  if (relative(root, candidate).startsWith('..')) throw new Error('release_outside_root');
  await access(join(candidate, 'compose.yaml'));
  await access(join(candidate, 'qweather-token-broker.env'));
  return candidate;
}

function dockerRequest(method, path, body) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const request = httpRequest({
      socketPath: '/var/run/docker.sock',
      method,
      path,
      headers: payload == null ? {} : {
        'Content-Type': 'application/json',
        'Content-Length': String(payload.length),
      },
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        const value = text.length === 0 ? null : JSON.parse(text || 'null');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          resolve(value);
        } else {
          const error = new Error(`docker_api_${response.statusCode}:${text.slice(0, 360)}`);
          error.statusCode = response.statusCode;
          reject(error);
        }
      });
    });
    request.once('error', reject);
    if (payload != null) request.write(payload);
    request.end();
  });
}

async function inspectContainer(containerName) {
  return dockerRequest('GET', `/v1.47/containers/${encodeURIComponent(containerName)}/json`);
}

function environmentValue(environment, name) {
  return environment?.find((entry) => entry.startsWith(`${name}=`))?.slice(name.length + 1) ?? '';
}

function environmentWithMode(environment, mode, proxyUrl) {
  const values = (environment ?? []).filter((entry) =>
    !entry.startsWith('LUMANEST_OUTBOUND_NETWORK_MODE=') &&
    !entry.startsWith('HTTP_PROXY=') &&
    !entry.startsWith('HTTPS_PROXY='));
  values.push(`LUMANEST_OUTBOUND_NETWORK_MODE=${mode}`);
  values.push(`HTTP_PROXY=${mode === 'mihomo' ? proxyUrl : ''}`);
  values.push(`HTTPS_PROXY=${mode === 'mihomo' ? proxyUrl : ''}`);
  return values;
}

function networkingConfig(snapshot) {
  const endpoints = Object.fromEntries(Object.entries(snapshot.NetworkSettings?.Networks ?? {}).map(([name, endpoint]) => [name, {
    Aliases: endpoint.Aliases,
    Links: endpoint.Links,
    DriverOpts: endpoint.DriverOpts,
    MacAddress: endpoint.MacAddress,
  }]));
  return { EndpointsConfig: endpoints };
}

function createBody(snapshot, mode, proxyUrl) {
  return {
    ...snapshot.Config,
    Env: mode == null
      ? snapshot.Config?.Env
      : environmentWithMode(snapshot.Config?.Env, mode, proxyUrl),
    HostConfig: snapshot.HostConfig,
    NetworkingConfig: networkingConfig(snapshot),
  };
}

async function containerMode(containerName) {
  try {
    const container = await inspectContainer(containerName);
    const value = environmentValue(container.Config?.Env, 'LUMANEST_OUTBOUND_NETWORK_MODE');
    const proxy = environmentValue(container.Config?.Env, 'HTTPS_PROXY');
    return { name: containerName, mode: modeFromEnvironment(value), proxyConfigured: proxy.length > 0 };
  } catch {
    return { name: containerName, mode: null, proxyConfigured: false };
  }
}

async function stopAndRemove(containerName) {
  try { await dockerRequest('POST', `/v1.47/containers/${encodeURIComponent(containerName)}/stop?t=5`); } catch (error) {
    if (![304, 404].includes(error.statusCode)) throw error;
  }
  try { await dockerRequest('DELETE', `/v1.47/containers/${encodeURIComponent(containerName)}?v=0&force=1`); } catch (error) {
    if (error.statusCode !== 404) throw error;
  }
}

async function recreate(snapshots, mode, proxyUrl) {
  for (const snapshot of snapshots) await stopAndRemove(snapshot.Name.slice(1));
  for (const snapshot of snapshots) {
    await dockerRequest('POST', `/v1.47/containers/create?name=${encodeURIComponent(snapshot.Name.slice(1))}`,
      createBody(snapshot, mode, proxyUrl));
  }
  for (const [, containerName] of managedServices) {
    await dockerRequest('POST', `/v1.47/containers/${encodeURIComponent(containerName)}/start`);
  }
}

export function createOutboundNetworkController({
  token,
  hostRoot = '/lumanest-root',
  hostReleasePrefix = '/vol2/docker/lumanest',
  projectName = 'qweather-token-broker',
  proxyUrl = 'http://mihomo:7890',
} = {}) {
  if (typeof token !== 'string' || token.length < 24) throw new TypeError('LUMANEST_NETWORK_CONTROLLER_TOKEN must be at least 24 characters');
  let applying = null;
  let lastChange = null;

  async function status() {
    const services = await Promise.all(managedServices.map(([, containerName]) => containerMode(containerName)));
    const modes = new Set(services.map((service) => service.mode).filter(Boolean));
    const effectiveMode = modes.size === 1 && services.every((service) => service.mode != null)
      ? [...modes][0]
      : null;
    const consistent = effectiveMode != null && services.every((service) =>
      service.proxyConfigured === (effectiveMode === 'mihomo'));
    return {
      status: applying ? 'applying' : consistent ? 'ready' : 'degraded',
      effectiveMode,
      services,
      lastChange,
    };
  }

  async function apply(mode) {
    if (!validModes.has(mode)) throw new TypeError('invalid_mode');
    if (applying != null) throw new Error('change_in_progress');
    applying = { mode, startedAt: new Date().toISOString() };
    try {
      const release = await currentRelease({ hostRoot, hostReleasePrefix });
      const envPath = join(release, 'qweather-token-broker.env');
      const original = await readFile(envPath, 'utf8');
      const updated = replaceEnvironmentValue(
        replaceEnvironmentValue(original, 'LUMANEST_OUTBOUND_NETWORK_MODE', mode),
        'LUMANEST_OUTBOUND_PROXY_URL', mode === 'mihomo' ? proxyUrl : '',
      );
      const temporary = `${envPath}.network-mode-${process.pid}`;
      await writeFile(temporary, updated, { mode: 0o600 });
      await rename(temporary, envPath);
      const snapshots = await Promise.all(managedServices.map(([, containerName]) => inspectContainer(containerName)));
      try {
        await recreate(snapshots, mode, proxyUrl);
      } catch (error) {
        await writeFile(temporary, original, { mode: 0o600 });
        await rename(temporary, envPath);
        await recreate(snapshots, null, proxyUrl).catch((rollbackError) => {
          error.rollbackError = rollbackError.message;
        });
        throw error;
      }
      lastChange = { mode, completedAt: new Date().toISOString(), result: 'ok' };
    } catch (error) {
      lastChange = {
        mode,
        completedAt: new Date().toISOString(),
        result: 'failed',
        error: error.message,
        rollbackError: error.rollbackError ?? null,
      };
      throw error;
    } finally {
      applying = null;
    }
  }

  return createServer(async (request, response) => {
    if (!sameToken(request.headers['x-lumanest-network-token'], token)) {
      json(response, 401, { error: 'unauthorized' });
      return;
    }
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (url.pathname !== '/v1/outbound-network') return json(response, 404, { error: 'not_found' });
    if (request.method === 'GET') return json(response, 200, await status());
    if (request.method !== 'PUT') return json(response, 405, { error: 'method_not_allowed' });
    const parsed = await requestBody(request);
    if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });
    if (!validModes.has(parsed.value?.mode)) return json(response, 400, { error: 'invalid_mode' });
    if (applying != null) return json(response, 409, { error: 'change_in_progress' });
    const mode = parsed.value.mode;
    json(response, 202, { accepted: true, mode });
    setImmediate(() => apply(mode).catch((error) => console.error('outbound network apply failed', error.message)));
  });
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const server = createOutboundNetworkController({
    token: process.env.LUMANEST_NETWORK_CONTROLLER_TOKEN ?? '',
    hostRoot: process.env.LUMANEST_HOST_ROOT ?? '/lumanest-root',
    hostReleasePrefix: process.env.LUMANEST_HOST_RELEASE_PREFIX ?? '/vol2/docker/lumanest',
    projectName: process.env.LUMANEST_COMPOSE_PROJECT ?? 'qweather-token-broker',
    proxyUrl: process.env.LUMANEST_MIHOMO_PROXY_URL ?? 'http://mihomo:7890',
  });
  server.listen(Number.parseInt(process.env.PORT ?? '8790', 10), '0.0.0.0');
}
