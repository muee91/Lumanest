import { createPrivateKey, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { createQWeatherJwt } from './jwt.mjs';

const tokenLifetimeSeconds = 900;
const amapBaseUrl = 'https://restapi.amap.com';
const gbifBaseUrl = 'https://api.gbif.org';
const wildlifeCacheTtlMilliseconds = 60 * 60 * 1000;

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

async function forwardAmap(response, path, parameters, amapWebKey, fetcher) {
  const url = new URL(path, amapBaseUrl);
  for (const [key, value] of Object.entries({ ...parameters, key: amapWebKey })) {
    if (value) url.searchParams.set(key, value);
  }
  try {
    const upstream = await fetcher(url, { signal: AbortSignal.timeout(10_000) });
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

async function regionalWildlifeSummary({ location, radiusKm, fetcher, cache, now }) {
  const [longitude, latitude] = location.split(',').map(Number);
  const cacheKey = `${longitude.toFixed(1)},${latitude.toFixed(1)}:${radiusKm}`;
  const cached = cache.get(cacheKey);
  if (cached && now().getTime() - cached.createdAt < wildlifeCacheTtlMilliseconds) {
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
      const upstream = await fetcher(url, { signal: AbortSignal.timeout(10_000) });
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
  now = () => new Date(),
  fetcher = fetch,
}) {
  const wildlifeCache = new Map();
  return createServer(async (request, response) => {
    const requestUrl = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && requestUrl.pathname === '/healthz') {
      writeJson(response, 200, { status: 'ok' });
      return;
    }

    if (!hasValidAuthorization(request.headers.authorization, serviceToken)) {
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
      }, amapWebKey, fetcher);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/amap/driving') {
      const origin = requestUrl.searchParams.get('origin');
      const destination = requestUrl.searchParams.get('destination');
      if (!validCoordinate(origin) || !validCoordinate(destination)) {
        writeJson(response, 400, { error: 'invalid_route' });
        return;
      }
      await forwardAmap(response, '/v3/direction/driving', {
        origin,
        destination,
        extensions: 'all',
        strategy: '0',
      }, amapWebKey, fetcher);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/wildlife/nearby') {
      const location = requestUrl.searchParams.get('location');
      if (!validCoordinate(location)) {
        writeJson(response, 400, { error: 'invalid_location' });
        return;
      }
      const radiusKm = clampInteger(requestUrl.searchParams.get('radiusKm'), {
        fallback: 20,
        min: 5,
        max: 50,
      });
      const body = await regionalWildlifeSummary({
        location,
        radiusKm,
        fetcher,
        cache: wildlifeCache,
        now,
      });
      if (body == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, body);
      return;
    }

    if (request.method !== 'POST' || requestUrl.pathname !== '/v1/qweather/token') {
      writeJson(response, 404, { error: 'not_found' });
      return;
    }

    const issuedAt = now();
    const iat = Math.floor(issuedAt.getTime() / 1000) - 30;
    const token = createQWeatherJwt({
      privateKey,
      keyId,
      projectId,
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
    port: Number.parseInt(environment.PORT ?? '8787', 10),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const configuration = configurationFromEnvironment();
  const server = createTokenBrokerServer(configuration);
  server.listen(configuration.port, '0.0.0.0', () => {
    console.log(`lumanest-data-broker listening on ${configuration.port}`);
  });
}
