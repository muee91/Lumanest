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
import {
  createConnectionTester,
  createLLMModelLister,
  createLLMProfileTester,
} from './admin/connection-tester.mjs';
import { routeNarrative } from './llm/router.mjs';
import {
  forwardContextSnapshot,
  fetchWildlifeLayers,
  importContextDataset,
  listContextSources,
  validContextRequest,
} from './context/proxy.mjs';
import { authoritativeWeather } from './context/qweather.mjs';
import { fetchAmapSceneEvidence } from './context/amap-evidence.mjs';
import { MemoryWeatherCache, RedisWeatherCache } from './context/weather-cache.mjs';

const tokenLifetimeSeconds = 900;
const amapBaseUrl = 'https://restapi.amap.com';
const gbifBaseUrl = 'https://api.gbif.org';
const elevationBaseUrl = 'https://api.open-meteo.com';

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
  'tone',
]);

const narrativeTones = new Set(['concise', 'balanced', 'detailed']);

function validNarrativeRequest(body) {
  if (Object.keys(body).some((key) => !narrativeRequestKeys.has(key))) return false;
  if (typeof body.scene !== 'string' || body.scene.length > 32) return false;
  if (typeof body.dayPhase !== 'string' || body.dayPhase.length > 24) return false;
  if (typeof body.weather !== 'string' || body.weather.length > 24) return false;
  if (typeof body.activeRoute !== 'boolean') return false;
  if (typeof body.templateSummary !== 'string' ||
      body.templateSummary.length === 0 || body.templateSummary.length > 160) return false;
  if (body.tone !== undefined && !narrativeTones.has(body.tone)) return false;
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

function narrativePrompt(body) {
  const tone = body.tone ?? 'balanced';
  const toneGuidance = {
    concise: '语气简洁直接，摘要尽量控制在20到35字。',
    balanced: '语气自然均衡，摘要尽量控制在35到55字。',
    detailed: '语气较详细，可增加一个解释分句，摘要仍不得超过80字。',
  }[tone];
  return {
    system: `你是摄影助手的文案编辑。只能改写给定模板和已成立创作事件的短标签，不得增加事实、地点、安全结论、坐标、链接或动作。${toneGuidance}只输出 JSON：{"summary":"不超过80字","noteLabels":{"事件ID":"2到8字"}}。noteLabels 的键只能来自 allowedCreativeEventIds。`,
    user: JSON.stringify({
      scene: body.scene,
      dayPhase: body.dayPhase,
      weather: body.weather,
      activeRoute: body.activeRoute,
      allowedCreativeEventIds: body.creativeEventIds,
      templateSummary: body.templateSummary,
      tone,
    }),
  };
}

function parsedNarrative(text, creativeEventIds) {
  const allowedIds = new Set(creativeEventIds);
  try {
    const candidate = JSON.parse(text);
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

// Amap-specific endpoints forward client-provided GCJ-02 coordinates to the
// AMap upstream verbatim. The Flutter client owns the single WGS84 → GCJ-02
// conversion boundary (see ChinaCoordinateConverter); the broker must never
// re-convert, because that would double-offset mainland coordinates.
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

const acceptedWildlifeBasisOfRecord = new Set([
  'HUMAN_OBSERVATION',
  'MACHINE_OBSERVATION',
  'OBSERVATION',
]);

const acceptedWildlifeLicenses = new Map([
  ['CC0_1_0', 'CC0-1.0'],
  ['http://creativecommons.org/publicdomain/zero/1.0/legalcode', 'CC0-1.0'],
  ['https://creativecommons.org/publicdomain/zero/1.0/legalcode', 'CC0-1.0'],
  ['CC_BY_4_0', 'CC-BY-4.0'],
  ['http://creativecommons.org/licenses/by/4.0/legalcode', 'CC-BY-4.0'],
  ['https://creativecommons.org/licenses/by/4.0/legalcode', 'CC-BY-4.0'],
]);

const severeWildlifeGeospatialIssues = new Set([
  'ZERO_COORDINATE',
  'COORDINATE_OUT_OF_RANGE',
  'COORDINATE_INVALID',
  'COUNTRY_COORDINATE_MISMATCH',
  'CONTINENT_COORDINATE_MISMATCH',
  'PRESUMED_SWAPPED_COORDINATE',
  'PRESUMED_NEGATED_LONGITUDE',
]);

const maximumWildlifeCoordinateUncertaintyMeters = 10_000;
const maximumWildlifeDatasetReferences = 8;
const gbifMetadataCacheTtlMilliseconds = 24 * 60 * 60 * 1_000;

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

function acceptedWildlifeLicense(value) {
  return typeof value === 'string' ? acceptedWildlifeLicenses.get(value) ?? null : null;
}

function acceptedWildlifeRecord(record) {
  if (record?.coordinateUncertaintyInMeters == null) return false;
  const uncertainty = Number(record.coordinateUncertaintyInMeters);
  return record?.occurrenceStatus === 'PRESENT' &&
    acceptedWildlifeBasisOfRecord.has(record.basisOfRecord) &&
    acceptedWildlifeLicense(record.license) != null &&
    Number.isFinite(uncertainty) && uncertainty >= 0 &&
    uncertainty <= maximumWildlifeCoordinateUncertaintyMeters &&
    (!Array.isArray(record.issues) ||
      !record.issues.some((issue) => severeWildlifeGeospatialIssues.has(issue)));
}

function recordMonth(record) {
  const month = Number(record.month);
  if (Number.isInteger(month) && month >= 1 && month <= 12) return month;
  const match = typeof record.eventDate === 'string'
    ? record.eventDate.match(/^\d{4}-(\d{2})-/)
    : null;
  const parsed = Number(match?.[1]);
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 12 ? parsed : null;
}

function recordHour(record) {
  const hour = Number(record.hour);
  if (Number.isInteger(hour) && hour >= 0 && hour <= 23) return hour;
  const match = typeof record.eventDate === 'string'
    ? record.eventDate.match(/T(\d{2}):/)
    : null;
  const parsed = Number(match?.[1]);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 23 ? parsed : null;
}

function observationPeriod(hour) {
  if (hour >= 5 && hour <= 8) return 'dawn';
  if (hour >= 9 && hour <= 16) return 'day';
  if (hour >= 17 && hour <= 20) return 'dusk';
  return 'night';
}

function temporalConcentration(records) {
  const monthCounts = new Map();
  const periodCounts = new Map();
  let recordsWithMonth = 0;
  let recordsWithTime = 0;
  for (const record of records) {
    const month = recordMonth(record);
    if (month != null) {
      recordsWithMonth += 1;
      monthCounts.set(month, (monthCounts.get(month) ?? 0) + 1);
    }
    const hour = recordHour(record);
    if (hour != null) {
      recordsWithTime += 1;
      const period = observationPeriod(hour);
      periodCounts.set(period, (periodCounts.get(period) ?? 0) + 1);
    }
  }
  const byCountThenKey = (a, b) => b.records - a.records ||
    String(a.month ?? a.period).localeCompare(String(b.month ?? b.period));
  return {
    recordsWithMonth,
    recordsWithTime,
    months: [...monthCounts].map(([month, count]) => ({ month, records: count }))
      .sort(byCountThenKey),
    timePeriods: [...periodCounts].map(([period, count]) => ({ period, records: count }))
      .sort(byCountThenKey),
  };
}

function validGbifKey(value) {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function boundedGbifText(value, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maximum &&
    !/[\u0000-\u001f\u007f]/.test(normalized)
    ? normalized
    : null;
}

function selectTraceableWildlifeRecords(records) {
  const datasetCounts = new Map();
  for (const record of records) {
    if (!validGbifKey(record.datasetKey)) continue;
    datasetCounts.set(record.datasetKey, (datasetCounts.get(record.datasetKey) ?? 0) + 1);
  }
  const selectedKeys = [...datasetCounts]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, maximumWildlifeDatasetReferences)
    .map(([key]) => key);
  const selected = new Set(selectedKeys);
  return {
    records: records.filter((record) => selected.has(record.datasetKey)),
    eligibleOccurrenceSampleSize: records.length,
    datasetsTruncated: datasetCounts.size > selected.size,
  };
}

async function gbifMetadata(path, { fetcher, cache, now, timeoutMs }) {
  const cached = cache.get(path);
  if (cached && now().getTime() - cached.createdAt < gbifMetadataCacheTtlMilliseconds) {
    return cached.value;
  }
  try {
    const upstream = await fetcher(new URL(path, gbifBaseUrl), {
      signal: AbortSignal.timeout(timeoutMs),
    });
    const value = await upstream.json();
    if (!upstream.ok || value == null || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    cache.set(path, { createdAt: now().getTime(), value });
    return value;
  } catch {
    return null;
  }
}

async function wildlifeDatasetReferences(records, dependencies) {
  const grouped = new Map();
  for (const record of records) {
    if (!validGbifKey(record.datasetKey)) continue;
    const existing = grouped.get(record.datasetKey) ?? {
      datasetKey: record.datasetKey,
      title: boundedGbifText(record.datasetTitle, 160),
      publisher: boundedGbifText(record.publishingOrgName, 160) ??
        boundedGbifText(record.institutionCode, 80),
      publishingOrgKey: validGbifKey(record.publishingOrgKey) ? record.publishingOrgKey : null,
      licenses: new Set(),
      records: 0,
    };
    existing.records += 1;
    existing.licenses.add(acceptedWildlifeLicense(record.license));
    grouped.set(record.datasetKey, existing);
  }
  const selected = [...grouped.values()]
    .sort((a, b) => b.records - a.records || a.datasetKey.localeCompare(b.datasetKey))
    .slice(0, maximumWildlifeDatasetReferences);
  return Promise.all(selected.map(async (reference) => {
    const dataset = await gbifMetadata(`/v1/dataset/${reference.datasetKey}`, dependencies);
    const organizationKey = validGbifKey(dataset?.publishingOrganizationKey)
      ? dataset.publishingOrganizationKey
      : reference.publishingOrgKey;
    const organization = organizationKey == null ? null : await gbifMetadata(
      `/v1/organization/${organizationKey}`,
      dependencies,
    );
    const title = boundedGbifText(dataset?.title, 160) ?? reference.title;
    const publisher = boundedGbifText(organization?.title, 160) ?? reference.publisher;
    const url = `https://www.gbif.org/dataset/${reference.datasetKey}`;
    const citation = boundedGbifText(dataset?.citation?.text, 500) ??
      (title == null
        ? `GBIF occurrence dataset. ${url}`
        : `${title}. ${url}`);
    return {
      datasetKey: reference.datasetKey,
      title: title ?? 'GBIF occurrence dataset',
      publisher: publisher ?? 'GBIF data publisher',
      licenses: [...reference.licenses].filter(Boolean).sort(),
      records: reference.records,
      citation,
      url,
    };
  }));
}

async function regionalWildlifeSummary({
  location,
  radiusKm,
  fetcher,
  cache,
  now,
  cacheTtlMilliseconds,
  timeoutMs,
  metadataCache,
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
      url.searchParams.set('occurrenceStatus', 'PRESENT');
      url.searchParams.set('hasGeospatialIssue', 'false');
      url.searchParams.set(
        'coordinateUncertaintyInMeters',
        String(maximumWildlifeCoordinateUncertaintyMeters),
      );
      for (const basis of acceptedWildlifeBasisOfRecord) {
        url.searchParams.append('basisOfRecord', basis);
      }
      url.searchParams.append('license', 'CC0_1_0');
      url.searchParams.append('license', 'CC_BY_4_0');
      url.searchParams.set('limit', '100');
      url.searchParams.set('geometry', regionalWildlifeGeometry(location, radiusKm));
      try {
        const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
        const body = await upstream.json();
        return upstream.ok && Array.isArray(body.results)
          ? { ok: true, results: body.results }
          : { ok: false, results: [] };
      } catch {
        return { ok: false, results: [] };
      }
    }));
    const successfulResponses = responses.filter((response) => response.ok);
    if (successfulResponses.length === 0) return null;
    const scannedRecords = successfulResponses.flatMap((response) => response.results);
    const qualityRecords = scannedRecords.filter(acceptedWildlifeRecord);
    const traceableCandidates = [];
    for (const record of qualityRecords) {
      const scientificName = boundedGbifText(record.species || record.scientificName, 160);
      if (scientificName == null) continue;
      if (excludedDomesticSpecies.has(scientificName.toLowerCase())) continue;
      traceableCandidates.push(record);
    }
    const selection = selectTraceableWildlifeRecords(traceableCandidates);
    const acceptedRecords = selection.records;
    const grouped = new Map();
    for (const record of acceptedRecords) {
      const scientificName = boundedGbifText(record.species || record.scientificName, 160);
      if (scientificName == null) continue;
      const existing = grouped.get(scientificName) ?? {
        scientificName,
        commonName: boundedGbifText(record.vernacularName, 120),
        animalClass: wildlifeGroupFor(record),
        records: 0,
      };
      existing.records += 1;
      grouped.set(scientificName, existing);
    }
    const taxa = [...grouped.values()]
      .sort((a, b) => b.records - a.records)
      .slice(0, 12);
    const datasets = await wildlifeDatasetReferences(acceptedRecords, {
      fetcher,
      cache: metadataCache,
      now,
      timeoutMs,
    });
    const sanitized = {
      contractVersion: 2,
      source: 'GBIF',
      scope: 'regional_wildlife_observations',
      radiusKm,
      scannedOccurrenceSampleSize: scannedRecords.length,
      eligibleOccurrenceSampleSize: selection.eligibleOccurrenceSampleSize,
      occurrenceSampleSize: acceptedRecords.length,
      datasetReferencesTruncated: selection.datasetsTruncated,
      qualityPolicy: {
        acceptedLicenses: ['CC0-1.0', 'CC-BY-4.0'],
        acceptedBasisOfRecord: [...acceptedWildlifeBasisOfRecord],
        maximumCoordinateUncertaintyMeters: maximumWildlifeCoordinateUncertaintyMeters,
        maximumDatasetReferences: maximumWildlifeDatasetReferences,
        excludesSevereGeospatialIssues: true,
      },
      historicalRecordConcentration: temporalConcentration(acceptedRecords),
      datasets,
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
  llmProfiles = [],
  llmRouting = {
    primaryProfileId: null,
    fallbackEnabled: false,
    fallbackProfileIds: [],
    maximumAttempts: 3,
  },
  settings,
  runtimeConfig,
  contextServiceUrl = '',
  contextInternalToken = '',
  qweatherApiHost = '',
  weatherCache = new MemoryWeatherCache(),
  now = () => new Date(),
  fetcher = fetch,
}) {
  const fixedSnapshot = Object.freeze({
    privateKey,
    keyId,
    projectId,
    serviceToken,
    amapWebKey,
    llmProfiles: Object.freeze([...llmProfiles]),
    llmRouting: Object.freeze({ ...llmRouting }),
    contextServiceUrl,
    contextInternalToken,
    qweatherApiHost,
    settings: validateRuntimeSettings(settings ?? {}),
  });
  const configurationSource = runtimeConfig ?? { snapshot: () => fixedSnapshot };
  const wildlifeCache = new Map();
  const gbifMetadataCache = new Map();
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
        metadataCache: gbifMetadataCache,
      });
      if (body == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, body);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/wildlife/layers') {
      const location = requestUrl.searchParams.get('location');
      if (!validCoordinate(location)) {
        writeJson(response, 400, { error: 'invalid_location' });
        return;
      }
      const [longitude, latitude] = location.split(',').map(Number);
      const radiusKm = clampInteger(requestUrl.searchParams.get('radiusKm'), {
        fallback: configuration.settings.wildlifeRadiusKm,
        min: 5,
        max: 50,
      });
      const result = await fetchWildlifeLayers({
        latitude,
        longitude,
        radiusKm,
        serviceUrl: configuration.contextServiceUrl,
        internalToken: configuration.contextInternalToken,
        fetcher,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!result.ok) {
        writeJson(response, result.error === 'not_configured' ? 503 : 502, {
          error: result.error === 'not_configured' ? 'context_unconfigured' : 'upstream_unavailable',
        });
        return;
      }
      writeJson(response, 200, result.body);
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
      if (!configuration.settings.aiEnabled || configuration.llmRouting.primaryProfileId == null) {
        writeJson(response, 503, { error: 'ai_unconfigured' });
        return;
      }
      const body = await readJsonBody(request);
      if (body == null || !validNarrativeRequest(body)) {
        writeJson(response, 400, { error: 'invalid_narrative_request' });
        return;
      }
      const routed = await routeNarrative({
        profiles: configuration.llmProfiles,
        routing: configuration.llmRouting,
        prompt: narrativePrompt(body),
        fetcher,
      });
      if (!routed.ok) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      const narrative = parsedNarrative(routed.text, body.creativeEventIds);
      if (narrative == null) {
        writeJson(response, 502, { error: 'upstream_unavailable' });
        return;
      }
      writeJson(response, 200, narrative);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/context/snapshot') {
      const body = await readJsonBody(request, 16 * 1024);
      if (body == null || !validContextRequest(body)) {
        writeJson(response, 400, { error: 'invalid_context_request' });
        return;
      }
      const [weather, sceneEvidence] = await Promise.all([
        authoritativeWeather({
          coordinate: body.coordinate,
          apiHost: configuration.qweatherApiHost,
          privateKey: configuration.privateKey,
          keyId: configuration.keyId,
          projectId: configuration.projectId,
          cache: weatherCache,
          fetcher,
          now,
          timeoutMs: configuration.settings.upstreamTimeoutMs,
        }),
        fetchAmapSceneEvidence({
          coordinate: body.coordinate,
          apiKey: configuration.amapWebKey,
          fetcher,
          timeoutMs: configuration.settings.upstreamTimeoutMs,
        }),
      ]);
      if (!weather.ok) {
        writeJson(response, weather.error === 'not_configured' ? 503 : 502, {
          error: weather.error === 'not_configured' ? 'weather_unconfigured' : 'upstream_unavailable',
        });
        return;
      }
      const internalBody = {
        contractVersion: body.contractVersion,
        coordinate: body.coordinate,
        observedAt: body.observedAt,
        locale: body.locale,
        intent: body.intent,
        route: body.route,
        evidence: sceneEvidence.ok ? sceneEvidence.evidence : {
          urban: false,
          waterBody: false,
          mountainous: false,
          aridLand: false,
          settlement: false,
        },
        weather: weather.body.weather,
        forecast: weather.body.forecast,
        officialWarnings: weather.body.officialWarnings,
      };
      const result = await forwardContextSnapshot({
        body: internalBody,
        serviceUrl: configuration.contextServiceUrl,
        internalToken: configuration.contextInternalToken,
        fetcher,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!result.ok) {
        writeJson(response, result.error === 'not_configured' ? 503 : 502, {
          error: result.error === 'not_configured' ? 'context_unconfigured' : 'upstream_unavailable',
        });
        return;
      }
      writeJson(response, 200, result.body);
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
    // Legacy values are never an active model configuration. RuntimeConfigService
    // exposes a non-empty legacy tuple only as a manual import candidate.
    aiBaseUrl: environment.AI_BASE_URL?.trim() ?? '',
    aiModel: environment.AI_MODEL?.trim() ?? '',
    contextServiceUrl: environment.CONTEXT_SERVICE_URL?.trim() ?? '',
    contextInternalToken: environment.CONTEXT_INTERNAL_TOKEN?.trim() ?? '',
    qweatherApiHost: environment.QWEATHER_API_HOST?.trim() ?? '',
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
  const weatherCache = await RedisWeatherCache.connect(environment.REDIS_URL?.trim() ?? '') ??
    new MemoryWeatherCache();
  const appServer = createTokenBrokerServer({ runtimeConfig, weatherCache });
  const adminServer = createAdminServer({
    authService,
    runtimeConfig,
    auditLog,
    testConnection: createConnectionTester({ runtimeConfig }),
    testLLMProfile: createLLMProfileTester({ runtimeConfig }),
    listLLMModels: createLLMModelLister(),
    listContextSources: async () => {
      const snapshot = runtimeConfig.snapshot();
      return listContextSources({
        serviceUrl: snapshot.contextServiceUrl,
        internalToken: snapshot.contextInternalToken,
      });
    },
    importContextDataset: async (body) => {
      const snapshot = runtimeConfig.snapshot();
      return importContextDataset({
        body,
        serviceUrl: snapshot.contextServiceUrl,
        internalToken: snapshot.contextInternalToken,
      });
    },
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
