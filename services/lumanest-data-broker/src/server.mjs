import { createPrivateKey, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { createQWeatherJwt } from './jwt.mjs';
import { validateRuntimeSettings } from './admin/runtime-settings.mjs';
import { EncryptedConfigStore } from './admin/config-store.mjs';
import { RuntimeConfigService } from './admin/runtime-config.mjs';
import { AdminAuthService } from './admin/auth.mjs';
import { AuditLog } from './admin/audit-log.mjs';
import { createAdminServer } from './admin/admin-server.mjs';
import { createConnectionTester } from './admin/connection-tester.mjs';

const tokenLifetimeSeconds = 900;
const amapBaseUrl = 'https://restapi.amap.com';
const gbifBaseUrl = 'https://api.gbif.org';
const elevationBaseUrl = 'https://api.open-meteo.com';
const defaultAiBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const defaultAiModel = 'qwen-plus';

function writeJson(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(body));
}

function hasValidAuthorization(header, serviceToken) {
  if (typeof header !== 'string') return false;
  const actual = Buffer.from(header);
  const expected = Buffer.from(`Bearer ${serviceToken}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function validCoordinate(value) {
  if (typeof value !== 'string') return false;
  const [longitude, latitude, ...rest] = value.split(',').map(Number);
  return rest.length === 0 &&
    Number.isFinite(longitude) && Number.isFinite(latitude) &&
    longitude >= -180 && longitude <= 180 && latitude >= -90 && latitude <= 90;
}

function clampInteger(value, { fallback, min, max }) {
  const parsed = Number.parseInt(value ?? '', 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function validKeywords(value) {
  if (typeof value !== 'string') return false;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= 80;
}

function profileLocations(value, maximumSamples = 64) {
  if (typeof value !== 'string') return null;
  const locations = value.split(';');
  if (locations.length < 2 || locations.length > maximumSamples) return null;
  return locations.every(validCoordinate) ? locations : null;
}

async function readJsonBody(request, maximumBytes = 4096) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumBytes) return null;
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    return body && typeof body === 'object' && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

const narrativeRequestKeys = new Set([
  'scene',
  'dayPhase',
  'weather',
  'activeRoute',
  'creativeEventIds',
  'templateSummary',
]);

function validNarrativeRequest(body) {
  if (Object.keys(body).some((key) => !narrativeRequestKeys.has(key))) return false;
  if (typeof body.scene !== 'string' || body.scene.length > 32) return false;
  if (typeof body.dayPhase !== 'string' || body.dayPhase.length > 24) return false;
  if (typeof body.weather !== 'string' || body.weather.length > 24) return false;
  if (typeof body.activeRoute !== 'boolean') return false;
  if (typeof body.templateSummary !== 'string' ||
      body.templateSummary.length === 0 || body.templateSummary.length > 160) return false;
  if (!Array.isArray(body.creativeEventIds) || body.creativeEventIds.length === 0 ||
      body.creativeEventIds.length > 3) return false;
  return body.creativeEventIds.every((id) =>
    typeof id === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(id));
}

function validNarrativeText(value, minimumLength, maximumLength) {
  if (typeof value !== 'string') return false;
  const length = [...value.trim()].length;
  return length >= minimumLength && length <= maximumLength &&
    !/[\r\n]/.test(value) && !/https?:\/\//i.test(value);
}

async function generateNarrative({ body, aiApiKey, aiBaseUrl, aiModel, fetcher, timeoutMs }) {
  if (!aiApiKey) return null;
  const url = new URL('chat/completions', `${aiBaseUrl.replace(/\/+$/, '')}/`);
  const allowedIds = new Set(body.creativeEventIds);
  try {
    const upstream = await fetcher(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${aiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: aiModel,
        temperature: 0.4,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: '你是摄影助手的文案编辑。只能改写给定模板和已成立创作事件的短标签，不得增加事实、地点、安全结论、坐标、链接或动作。只输出 JSON：{"summary":"不超过80字","noteLabels":{"事件ID":"2到8字"}}。noteLabels 的键只能来自 allowedCreativeEventIds。',
          },
          {
            role: 'user',
            content: JSON.stringify({
              scene: body.scene,
              dayPhase: body.dayPhase,
              weather: body.weather,
              activeRoute: body.activeRoute,
              allowedCreativeEventIds: body.creativeEventIds,
              templateSummary: body.templateSummary,
            }),
          },
        ],
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const upstreamBody = await upstream.json();
    const content = upstreamBody?.choices?.[0]?.message?.content;
    if (!upstream.ok || typeof content !== 'string') return null;
    const candidate = JSON.parse(content);
    if (!validNarrativeText(candidate.summary, 1, 80)) return null;
    if (candidate.noteLabels == null || typeof candidate.noteLabels !== 'object' ||
        Array.isArray(candidate.noteLabels)) return null;
    const noteLabels = {};
    for (const [id, label] of Object.entries(candidate.noteLabels)) {
      if (!allowedIds.has(id) || !validNarrativeText(label, 2, 8)) return null;
      noteLabels[id] = label.trim();
    }
    return { summary: candidate.summary.trim(), noteLabels };
  } catch {
    return null;
  }
}

async function elevationProfile({ locations, fetcher, cache, now, cacheTtlMilliseconds, timeoutMs }) {
  const cacheKey = locations.join(';');
  const cached = cache.get(cacheKey);
  if (cached && now().getTime() - cached.createdAt < cacheTtlMilliseconds) {
    return cached.body;
  }
  const coordinates = locations.map((location) => location.split(',').map(Number));
  const url = new URL('/v1/elevation', elevationBaseUrl);
  url.searchParams.set('latitude', coordinates.map(([, latitude]) => latitude).join(','));
  url.searchParams.set('longitude', coordinates.map(([longitude]) => longitude).join(','));
  try {
    const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = await upstream.json();
    if (!upstream.ok || !Array.isArray(body.elevation) ||
        body.elevation.length !== locations.length ||
        body.elevation.some((value) => !Number.isFinite(value))) {
      return null;
    }
    const sanitized = {
      source: 'Open-Meteo Elevation API',
      elevations: body.elevation,
    };
    cache.set(cacheKey, { createdAt: now().getTime(), body: sanitized });
    return sanitized;
  } catch {
    return null;
  }
}

async function forwardAmap(response, path, parameters, amapWebKey, fetcher, timeoutMs) {
  const url = new URL(path, amapBaseUrl);
  for (const [key, value] of Object.entries({ ...parameters, key: amapWebKey })) {
    if (value) url.searchParams.set(key, value);
  }
  try {
    const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = await upstream.json();
    if (!upstream.ok || body.status !== '1') {
      writeJson(response, 502, { error: 'upstream_unavailable' });
      return;
    }
    writeJson(response, 200, body);
  } catch {
    writeJson(response, 502, { error: 'upstream_unavailable' });
  }
}

const wildlifeGroups = new Map([
  ['Aves', 'bird'],
  ['Mammalia', 'mammal'],
  ['Reptilia', 'reptile'],
  ['Amphibia', 'amphibian'],
  ['Insecta', 'insect'],
]);

const wildlifeClassKeys = [
  212, // Aves
  359, // Mammalia
  358, // Reptilia
  131, // Amphibia
  216, // Insecta
];

const excludedDomesticSpecies = new Set([
  'Felis catus',
  'Canis lupus familiaris',
  'Bos taurus',
  'Equus caballus',
  'Capra hircus',
  'Ovis aries',
  'Sus scrofa domesticus',
  'Gallus gallus domesticus',
].map((name) => name.toLowerCase()));

function regionalWildlifeGeometry(location, radiusKm) {
  const [longitude, latitude] = location.split(',').map(Number);
  const latitudeDelta = radiusKm / 111.32;
  const longitudeDelta = radiusKm / (111.32 * Math.cos(latitude * Math.PI / 180));
  const west = longitude - longitudeDelta;
  const east = longitude + longitudeDelta;
  const south = latitude - latitudeDelta;
  const north = latitude + latitudeDelta;
  return `POLYGON((${west} ${south},${east} ${south},${east} ${north},${west} ${north},${west} ${south}))`;
}

function wildlifeGroupFor(record) {
  return wildlifeGroups.get(record.class) ?? 'other';
}

async function regionalWildlifeSummary({
  location,
  radiusKm,
  fetcher,
  cache,
  now,
  cacheTtlMilliseconds,
  timeoutMs,
}) {
  const [longitude, latitude] = location.split(',').map(Number);
  const cacheKey = `${longitude.toFixed(1)},${latitude.toFixed(1)}:${radiusKm}`;
  const cached = cache.get(cacheKey);
  if (cached && now().getTime() - cached.createdAt < cacheTtlMilliseconds) {
    return cached.body;
  }
  try {
    const responses = await Promise.all(wildlifeClassKeys.map(async (classKey) => {
      const url = new URL('/v1/occurrence/search', gbifBaseUrl);
      url.searchParams.set('kingdom', 'Animalia');
      url.searchParams.set('classKey', String(classKey));
      url.searchParams.set('hasCoordinate', 'true');
      url.searchParams.set('limit', '25');
      url.searchParams.set('geometry', regionalWildlifeGeometry(location, radiusKm));
      const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
      const body = await upstream.json();
      return upstream.ok && Array.isArray(body.results) ? body.results : [];
    }));
    const records = responses.flat();
    if (records.length === 0) return null;
    const grouped = new Map();
    for (const record of records) {
      const scientificName = record.species || record.scientificName;
      if (typeof scientificName !== 'string' || scientificName.length === 0) continue;
      if (excludedDomesticSpecies.has(scientificName.toLowerCase())) continue;
      const existing = grouped.get(scientificName) ?? {
        scientificName,
        commonName: typeof record.vernacularName === 'string' ? record.vernacularName : null,
        animalClass: wildlifeGroupFor(record),
        records: 0,
      };
      existing.records += 1;
      grouped.set(scientificName, existing);
    }
    const taxa = [...grouped.values()]
      .sort((a, b) => b.records - a.records)
      .slice(0, 12);
    const sanitized = {
      source: 'GBIF',
      scope: 'regional_wildlife_observations',
      radiusKm,
      occurrenceSampleSize: records.length,
      taxa,
    };
    cache.set(cacheKey, { createdAt: now().getTime(), body: sanitized });
    return sanitized;
  } catch {
    return null;
  }
}

export function createTokenBrokerServer({
  privateKey,
  keyId,
  projectId,
  serviceToken,
  amapWebKey,
  aiApiKey = '',
  aiBaseUrl = defaultAiBaseUrl,
  aiModel = defaultAiModel,
  settings,
  runtimeConfig,
  now = () => new Date(),
  fetcher = fetch,
}) {
  const fixedSnapshot = Object.freeze({
    privateKey,
    keyId,
    projectId,
    serviceToken,
    amapWebKey,
    aiApiKey,
    aiBaseUrl,
    aiModel,
    settings: validateRuntimeSettings(settings ?? {}),
  });
  const configurationSource = runtimeConfig ?? { snapshot: () => fixedSnapshot };
  const wildlifeCache = new Map();
  const elevationCache = new Map();
  return createServer(async (request, response) => {
    const configuration = configurationSource.snapshot();
    const requestUrl = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && requestUrl.pathname === '/healthz') {
      writeJson(response, 200, { status: 'ok' });
      return;
    }

    if (requestUrl.pathname === '/admin' || requestUrl.pathname === '/admin/' ||
        requestUrl.pathname.startsWith('/admin-assets/')) {
      writeJson(response, 404, { error: 'not_found' });
      return;
    }

    if (!hasValidAuthorization(request.headers.authorization, configuration.serviceToken)) {
      writeJson(response, 401, { error: 'unauthorized' });
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/amap/nearby') {
      const location = requestUrl.searchParams.get('location');
      if (!validCoordinate(location)) {
        writeJson(response, 400, { error: 'invalid_location' });
        return;
      }
      await forwardAmap(response, '/v3/place/around', {
        location,
        keywords: requestUrl.searchParams.get('keywords') ?? '',
        types: requestUrl.searchParams.get('types') ?? '',
        radius: String(clampInteger(requestUrl.searchParams.get('radius'), { fallback: 5000, min: 100, max: 50000 })),
        offset: String(clampInteger(requestUrl.searchParams.get('offset'), { fallback: 20, min: 1, max: 25 })),
        extensions: 'all',
      }, configuration.amapWebKey, fetcher, configuration.settings.upstreamTimeoutMs);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/amap/search') {
      const keywords = requestUrl.searchParams.get('keywords');
      if (!validKeywords(keywords)) {
        writeJson(response, 400, { error: 'invalid_keywords' });
        return;
      }
      await forwardAmap(response, '/v3/place/text', {
        keywords: keywords.trim(),
        city: requestUrl.searchParams.get('city') ?? '',
        citylimit: 'false',
        offset: String(clampInteger(requestUrl.searchParams.get('offset'), { fallback: 10, min: 1, max: 25 })),
        page: '1',
        extensions: 'base',
      }, configuration.amapWebKey, fetcher, configuration.settings.upstreamTimeoutMs);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/amap/scene-evidence') {
      const location = requestUrl.searchParams.get('location');
      if (!validCoordinate(location)) {
        writeJson(response, 400, { error: 'invalid_location' });
        return;
      }
      await forwardAmap(response, '/v3/geocode/regeo', {
        location,
        radius: '3000',
        extensions: 'all',
        roadlevel: '1',
      }, configuration.amapWebKey, fetcher, configuration.settings.upstreamTimeoutMs);
      return;
    }

    if (request.method === 'GET' &&
        (requestUrl.pathname === '/v1/amap/driving' ||
         requestUrl.pathname === '/v1/amap/walking')) {
      const origin = requestUrl.searchParams.get('origin');
      const destination = requestUrl.searchParams.get('destination');
      if (!validCoordinate(origin) || !validCoordinate(destination)) {
        writeJson(response, 400, { error: 'invalid_route' });
        return;
      }
      const walking = requestUrl.pathname.endsWith('/walking');
      await forwardAmap(response, walking ? '/v3/direction/walking' : '/v3/direction/driving', {
        origin,
        destination,
        extensions: 'all',
        strategy: walking ? '' : '0',
      }, configuration.amapWebKey, fetcher, configuration.settings.upstreamTimeoutMs);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/wildlife/nearby') {
      const location = requestUrl.searchParams.get('location');
      if (!validCoordinate(location)) {
        writeJson(response, 400, { error: 'invalid_location' });
        return;
      }
      const radiusKm = clampInteger(requestUrl.searchParams.get('radiusKm'), {
        fallback: configuration.settings.wildlifeRadiusKm,
        min: 5,
        max: 50,
      });
      const body = await regionalWildlifeSummary({
        location,
        radiusKm,
        fetcher,
        cache: wildlifeCache,
        now,
        cacheTtlMilliseconds: configuration.settings.wildlifeCacheTtlMinutes * 60 * 1_000,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (body == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, body);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/elevation/profile') {
      const locations = profileLocations(
        requestUrl.searchParams.get('locations'),
        configuration.settings.elevationMaximumSamples,
      );
      if (locations == null) {
        writeJson(response, 400, { error: 'invalid_locations' });
        return;
      }
      const body = await elevationProfile({
        locations,
        fetcher,
        cache: elevationCache,
        now,
        cacheTtlMilliseconds: configuration.settings.elevationCacheTtlMinutes * 60 * 1_000,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (body == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, body);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/narrative') {
      if (!configuration.settings.aiEnabled || !configuration.aiApiKey) {
        writeJson(response, 503, { error: 'ai_unconfigured' });
        return;
      }
      const body = await readJsonBody(request);
      if (body == null || !validNarrativeRequest(body)) {
        writeJson(response, 400, { error: 'invalid_narrative_request' });
        return;
      }
      const narrative = await generateNarrative({
        body,
        aiApiKey: configuration.aiApiKey,
        aiBaseUrl: configuration.aiBaseUrl,
        aiModel: configuration.aiModel,
        fetcher,
        timeoutMs: configuration.settings.aiTimeoutMs,
      });
      if (narrative == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, narrative);
      return;
    }

    if (request.method !== 'POST' || requestUrl.pathname !== '/v1/qweather/token') {
      writeJson(response, 404, { error: 'not_found' });
      return;
    }

    const issuedAt = now();
    const iat = Math.floor(issuedAt.getTime() / 1000) - 30;
    const token = createQWeatherJwt({
      privateKey: configuration.privateKey,
      keyId: configuration.keyId,
      projectId: configuration.projectId,
      now: issuedAt,
      ttlSeconds: tokenLifetimeSeconds,
    });
    writeJson(response, 200, {
      token,
      expiresAt: new Date((iat + tokenLifetimeSeconds) * 1000).toISOString(),
    });
  });
}

export function configurationFromEnvironment(environment = process.env) {
  const required = (name) => {
    const value = environment[name]?.trim();
    if (!value) throw new Error(`Missing required environment variable: ${name}`);
    return value;
  };

  const privateKeyPath = required('QWEATHER_PRIVATE_KEY_PATH');
  return {
    privateKey: createPrivateKey(readFileSync(privateKeyPath)),
    keyId: required('QWEATHER_KEY_ID'),
    projectId: required('QWEATHER_PROJECT_ID'),
    serviceToken: required('LUMANEST_SERVICE_TOKEN'),
    amapWebKey: required('AMAP_WEB_KEY'),
    aiApiKey: environment.AI_API_KEY?.trim() ?? '',
    aiBaseUrl: environment.AI_BASE_URL?.trim() || defaultAiBaseUrl,
    aiModel: environment.AI_MODEL?.trim() || defaultAiModel,
    port: Number.parseInt(environment.PORT ?? '8787', 10),
  };
}

export async function createBrokerServices(environment = process.env, {
  exit = (code) => process.exit(code),
} = {}) {
  const defaults = configurationFromEnvironment(environment);
  const dataDirectory = environment.LUMANEST_DATA_DIR?.trim() || '/var/lib/lumanest';
  const masterKey = environment.LUMANEST_CONFIG_MASTER_KEY?.trim();
  if (!masterKey) throw new Error('Missing required environment variable: LUMANEST_CONFIG_MASTER_KEY');

  const configStore = new EncryptedConfigStore({
    filePath: `${dataDirectory}/runtime-config.enc.json`,
    masterKey,
  });
  const runtimeConfig = new RuntimeConfigService({ defaults, store: configStore });
  await runtimeConfig.initialize();

  const authService = new AdminAuthService({
    filePath: `${dataDirectory}/admin-auth.json`,
    bootstrapPassword: environment.LUMANEST_ADMIN_PASSWORD ?? '',
  });
  await authService.initialize();
  const auditLog = new AuditLog();
  const appServer = createTokenBrokerServer({ runtimeConfig });
  const adminServer = createAdminServer({
    authService,
    runtimeConfig,
    auditLog,
    testConnection: createConnectionTester({ runtimeConfig }),
    restart: async () => exit(0),
  });
  return {
    appServer,
    adminServer,
    appPort: defaults.port,
    adminPort: Number.parseInt(environment.ADMIN_PORT ?? '8788', 10),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const services = await createBrokerServices();
  services.appServer.listen(services.appPort, '0.0.0.0', () => {
    console.log(`lumanest-data-broker app API listening on ${services.appPort}`);
  });
  services.adminServer.listen(services.adminPort, '0.0.0.0', () => {
    console.log(`lumanest-data-broker LAN admin listening on ${services.adminPort}`);
  });
}
