import { createHash, createPrivateKey, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { validateRuntimeSettings } from './admin/runtime-settings.mjs';
import { EncryptedConfigStore } from './admin/config-store.mjs';
import { RuntimeConfigService } from './admin/runtime-config.mjs';
import { AdminAuthService } from './admin/auth.mjs';
import { AuditLog } from './admin/audit-log.mjs';
import { createAdminServer } from './admin/admin-server.mjs';
import { createOutboundNetworkControllerClient } from './admin/outbound-network-controller.mjs';
import { SimulationRegistry, isSimulationSessionId } from './context/simulation.mjs';
import {
  createConnectionTester,
  createLLMModelLister,
  createLLMProfileTester,
} from './admin/connection-tester.mjs';
import { routeNarrative } from './llm/router.mjs';
import { opportunityCatalog } from './generated/opportunity-catalog.mjs';
import {
  forwardContextSnapshot,
  fetchWildlifeLayers,
  forwardShootingFeedback,
  fetchShootingCalibration,
  importContextDataset,
  listContextSources,
  resolveShootingTarget,
  validContextRequest,
  validShootingFeedbackRequest,
  validTargetSessionRequest,
} from './context/proxy.mjs';
import { forwardDiscovery, validDiscoveryRequest } from './discovery/proxy.mjs';
import {
  extractDiscoveryCandidates,
  normalizedDiscoverySearchRequest,
  searchTavily,
  validDiscoveryExtractRequest,
  validDiscoverySearchRequest,
} from './discovery/ingestion.mjs';
import {
  resolveDeterministicDiscovery,
  validDeterministicDiscoveryRequest,
} from './discovery/deterministic.mjs';
import {
  decodedVerifiedMediaUrl,
  parsePlaceMediaRequest,
  searchVerifiedPlaceMedia,
  verifiedPlaceMediaContentTypes,
} from './discovery/place-media.mjs';
import { defaultDiscoverySearchProfile } from './discovery/search-profile.mjs';
import { authoritativeWeather } from './context/qweather.mjs';
import { routeWeatherForecast, validRouteWeatherRequest } from './context/route-weather.mjs';
import { fetchAmapSceneEvidence } from './context/amap-evidence.mjs';
import { MemoryWeatherCache, RedisWeatherCache } from './context/weather-cache.mjs';
import {
  MemorySkyOpportunityCache,
  RedisSkyOpportunityCache,
} from './infrastructure/cache/sky_opportunity_cache.mjs';
import { SkyOpportunityMetrics } from './infrastructure/metrics/sky_opportunity_metrics.mjs';
import {
  SkyOpportunityService,
  validDailySkyOpportunityQuery,
  validSkyOpportunityQuery,
} from './domain/sky_opportunity/sky_opportunity_service.mjs';
import {
  FallbackRequestRateLimiter,
  MemoryRequestRateLimiter,
  RedisRequestRateLimiter,
} from './context/request-rate-limiter.mjs';
import {
  CompanionStore,
  parseInventoryQuery,
  validCompanionRefreshRequest,
  validIdempotencyKey,
  validInsightFeedbackRequest,
} from './companion/orchestrator.mjs';

const amapBaseUrl = 'https://restapi.amap.com';
const amapPhotoHosts = new Set(['aos-comment.amap.com', 'store.is.autonavi.com']);
const amapPhotoContentTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const maximumAmapPhotoBytes = 8 * 1024 * 1024;
const maximumVerifiedPlaceMediaBytes = 8 * 1024 * 1024;
const gbifBaseUrl = 'https://api.gbif.org';
const elevationBaseUrl = 'https://api.open-meteo.com';

function writeJson(response, status, body, headers = {}) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...headers,
  });
  response.end(JSON.stringify(body));
}

function writeText(response, status, body, contentType = 'text/plain; charset=utf-8') {
  response.writeHead(status, {
    'Content-Type': contentType,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(body);
}

function hasValidAuthorization(header, serviceToken) {
  if (typeof header !== 'string') return false;
  const actual = Buffer.from(header);
  const expected = Buffer.from(`Bearer ${serviceToken}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function hasValidWorkerToken(header, workerToken) {
  if (typeof header !== 'string' || typeof workerToken !== 'string' || workerToken.length === 0) return false;
  const actual = Buffer.from(header);
  const expected = Buffer.from(workerToken);
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

function parsedAmapPhotoUrl(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 1_200) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        !amapPhotoHosts.has(url.hostname.toLowerCase())) return null;
    return url;
  } catch {
    return null;
  }
}

function amapPhotoMedia(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null;
  const url = parsedAmapPhotoUrl(value.url);
  if (url == null) return null;
  const sourceUrl = url.toString();
  const token = Buffer.from(sourceUrl, 'utf8').toString('base64url');
  const title = typeof value.title === 'string' && value.title.trim()
    ? value.title.trim().slice(0, 160)
    : null;
  const provider = typeof value.provider === 'string' && value.provider.trim()
    ? value.provider.trim().slice(0, 80)
    : '高德地图';
  return {
    id: createHash('sha256').update(sourceUrl).digest('hex').slice(0, 24),
    kind: 'photo',
    proxyPath: `/v1/amap/media/${token}`,
    title,
    attribution: provider,
  };
}

function normalizedAmapNearbyBody(body) {
  if (!Array.isArray(body?.pois)) return body;
  return {
    ...body,
    pois: body.pois.map((poi) => {
      if (poi == null || typeof poi !== 'object' || Array.isArray(poi)) return poi;
      const { photos, ...fields } = poi;
      const media = Array.isArray(photos)
        ? photos.map(amapPhotoMedia).filter(Boolean).slice(0, 3)
        : [];
      return { ...fields, media };
    }),
  };
}

function decodedAmapPhotoUrl(token) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{16,1800}$/.test(token)) return null;
  try {
    return parsedAmapPhotoUrl(Buffer.from(token, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

async function proxyAmapPhoto(response, token, fetcher, timeoutMs) {
  const url = decodedAmapPhotoUrl(token);
  if (url == null) {
    writeJson(response, 400, { error: 'invalid_media_reference' });
    return;
  }
  try {
    const upstream = await fetcher(url, {
      redirect: 'error',
      signal: AbortSignal.timeout(Math.min(timeoutMs, 12_000)),
      headers: { 'User-Agent': 'LumaNest/1.0 PlaceMediaProxy' },
    });
    const contentType = upstream.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
    const declaredLength = Number.parseInt(upstream.headers.get('content-length') ?? '', 10);
    if (!upstream.ok || !amapPhotoContentTypes.has(contentType) ||
        (Number.isFinite(declaredLength) && declaredLength > maximumAmapPhotoBytes) ||
        upstream.body == null) {
      writeJson(response, 502, { error: 'media_unavailable' });
      return;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of upstream.body) {
      size += chunk.byteLength;
      if (size > maximumAmapPhotoBytes) {
        await upstream.body.cancel().catch(() => {});
        writeJson(response, 502, { error: 'media_too_large' });
        return;
      }
      chunks.push(Buffer.from(chunk));
    }
    const body = Buffer.concat(chunks, size);
    response.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': body.length,
      'Cache-Control': 'private, max-age=86400',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(body);
  } catch {
    writeJson(response, 502, { error: 'media_unavailable' });
  }
}

async function proxyVerifiedPlaceMedia(response, token, fetcher, timeoutMs) {
  const url = decodedVerifiedMediaUrl(token);
  if (url == null) {
    writeJson(response, 400, { error: 'invalid_media_reference' });
    return;
  }
  try {
    const upstream = await fetcher(url, {
      redirect: 'error',
      signal: AbortSignal.timeout(Math.min(timeoutMs, 12_000)),
      headers: { 'User-Agent': 'LumaNest/1.0 PlaceMediaProxy' },
    });
    const contentType = upstream.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
    const declaredLength = Number.parseInt(upstream.headers.get('content-length') ?? '', 10);
    if (!upstream.ok || !verifiedPlaceMediaContentTypes.has(contentType) ||
        (Number.isFinite(declaredLength) && declaredLength > maximumVerifiedPlaceMediaBytes) ||
        upstream.body == null) {
      writeJson(response, 502, { error: 'media_unavailable' });
      return;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of upstream.body) {
      size += chunk.byteLength;
      if (size > maximumVerifiedPlaceMediaBytes) {
        await upstream.body.cancel().catch(() => {});
        writeJson(response, 502, { error: 'media_too_large' });
        return;
      }
      chunks.push(Buffer.from(chunk));
    }
    const body = Buffer.concat(chunks, size);
    response.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': body.length,
      'Cache-Control': 'private, max-age=86400',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(body);
  } catch {
    writeJson(response, 502, { error: 'media_unavailable' });
  }
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
const narrativeCreativeIds = new Set([
  ...opportunityCatalog
    .filter((item) => item.catalogTier === 'core' && item.coreCapability !== 'unavailable')
    .map((item) => item.id),
  'regional-wildlife',
]);

const ratePolicies = [
  { path: '/v1/narrative', limit: 8, windowMs: 5 * 60 * 1_000, key: 'narrative' },
  { path: '/v1/wildlife/nearby', limit: 12, windowMs: 60 * 1_000, key: 'wildlife' },
  { path: '/v1/wildlife/layers', limit: 12, windowMs: 60 * 1_000, key: 'wildlife-layer' },
  { path: '/v1/elevation/profile', limit: 20, windowMs: 60 * 1_000, key: 'elevation' },
  { path: '/v1/route/weather', limit: 12, windowMs: 60 * 1_000, key: 'route-weather' },
  { path: '/v1/context/snapshot', limit: 30, windowMs: 60 * 1_000, key: 'context' },
  { path: '/v1/context/target-session', limit: 20, windowMs: 60 * 1_000, key: 'target-session' },
  { path: '/v1/context/shooting-feedback', limit: 12, windowMs: 60 * 1_000, key: 'shooting-feedback' },
  { path: '/v1/context/safety-detail', limit: 30, windowMs: 60 * 1_000, key: 'safety-detail' },
  { path: '/v1/sky-opportunities', limit: 12, windowMs: 60 * 1_000, key: 'sky-opportunity' },
  { path: '/v1/sky-opportunities/daily', limit: 8, windowMs: 60 * 1_000, key: 'sky-opportunity-daily' },
  { path: '/v1/explore/discover', limit: 6, windowMs: 60 * 1_000, key: 'discovery' },
  { path: '/v1/explore/place-media', limit: 12, windowMs: 60 * 1_000, key: 'place-media-search' },
  { path: '/v1/companion/refresh', limit: 6, windowMs: 10 * 60 * 1_000, key: 'companion-refresh' },
  { path: '/v1/inspiration/inventory', limit: 30, windowMs: 60 * 1_000, key: 'inspiration-inventory' },
];

function ratePolicy(pathname) {
  if (/^\/v1\/insights\/insight_[a-f0-9]{24}\/feedback$/.test(pathname)) {
    return { limit: 60, windowMs: 60 * 1_000, key: 'insight-feedback' };
  }
  if (/^\/v1\/amap\/media\/[A-Za-z0-9_-]{16,1800}$/.test(pathname)) {
    return { limit: 60, windowMs: 60 * 1_000, key: 'amap-media' };
  }
  if (/^\/v1\/explore\/media\/[A-Za-z0-9_-]{16,2800}$/.test(pathname)) {
    return { limit: 60, windowMs: 60 * 1_000, key: 'place-media' };
  }
  return ratePolicies.find((policy) => policy.path === pathname) ?? {
    limit: 60,
    windowMs: 60 * 1_000,
    key: 'app',
  };
}

function writeApiError(response, status, code, { retryAfterSeconds = null } = {}) {
  writeJson(response, status, {
    error: {
      code,
      message: code,
      retryAfterSeconds,
      requestId: createHash('sha256')
        .update(`${Date.now()}:${code}`)
        .digest('hex')
        .slice(0, 16),
    },
  });
}

function rateLimitKey(request, policy) {
  const remoteAddress = request.socket?.remoteAddress ?? 'unknown';
  const source = createHash('sha256').update(remoteAddress).digest('hex').slice(0, 24);
  return `${policy.key}:${source}`;
}

function validSafetyDetailRequest(body) {
  return body != null && typeof body === 'object' && !Array.isArray(body) &&
    Object.keys(body).length === 2 &&
    typeof body.contextId === 'string' && /^ctx_[a-f0-9]{24}$/.test(body.contextId) &&
    typeof body.eventId === 'string' && /^weather-warning-[a-f0-9]{12}$/.test(body.eventId);
}

function safetyDetailsFor(contextId, warnings, eventIds) {
  const allowed = new Set(eventIds);
  return warnings.flatMap((warning) => {
    const eventId = `weather-warning-${warning.id}`;
    if (!allowed.has(eventId) || typeof warning.title !== 'string') return [];
    const description = typeof warning.description === 'string' && warning.description.trim()
      ? warning.description.trim()
      : '此预警由官方气象来源发布，请结合当地管制和现场情况调整行程。';
    const guidance = Array.isArray(warning.guidance)
      ? warning.guidance.filter((entry) => typeof entry === 'string' && entry.trim()).slice(0, 3)
      : [];
    return [{
      eventId,
      title: warning.title,
      description,
      guidance,
      source: '和风天气 · 官方预警',
      severity: warning.severity,
      observedAt: warning.observedAt,
      expiresAt: warning.expiresAt,
      contextId,
    }];
  });
}

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
  return body.creativeEventIds.every((id) => narrativeCreativeIds.has(id));
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
async function forwardAmap(
  response,
  path,
  parameters,
  amapWebKey,
  fetcher,
  timeoutMs,
  transform = (body) => body,
) {
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
    writeJson(response, 200, transform(body));
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
  discoveryServiceUrl = '',
  discoveryInternalToken = '',
  discoveryWorkerToken = '',
  discoverySearchProfile = defaultDiscoverySearchProfile(),
  qweatherApiHost = '',
  weatherCache = new MemoryWeatherCache(),
  sunsetBotBaseUrl = 'https://sunsetbot.top',
  skyOpportunityCache = new MemorySkyOpportunityCache(),
  skyOpportunityMetrics = new SkyOpportunityMetrics(),
  skyOpportunityLogger = () => {},
  requestRateLimiter = new MemoryRequestRateLimiter(),
  simulationRegistry = null,
  companionStore = null,
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
    discoveryServiceUrl,
    discoveryInternalToken,
    discoveryWorkerToken,
    discoverySearchProfile,
    qweatherApiHost,
    sunsetBotBaseUrl,
    settings: validateRuntimeSettings(settings ?? {}),
  });
  const configurationSource = runtimeConfig ?? { snapshot: () => fixedSnapshot };
  const skyOpportunityService = new SkyOpportunityService({
    settings: () => configurationSource.snapshot().settings,
    baseUrl: sunsetBotBaseUrl,
    amapWebKey: () => configurationSource.snapshot().amapWebKey,
    cache: skyOpportunityCache,
    metrics: skyOpportunityMetrics,
    fetcher,
    now,
    logger: skyOpportunityLogger,
  });
  const wildlifeCache = new Map();
  const gbifMetadataCache = new Map();
  const elevationCache = new Map();
  const placeMediaCache = new Map();
  const companion = companionStore ?? new CompanionStore({ now });
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

    // Discovery workers share this listener only to keep the Broker's outbound
    // credentials in one process. They never authenticate with the App token.
    // Compose places workers on the private network; the separate token is a
    // second boundary and is intentionally absent from all responses and logs.
    if (requestUrl.pathname === '/internal/v1/discovery/search' ||
        requestUrl.pathname === '/internal/v1/discovery/extract' ||
        requestUrl.pathname === '/internal/v1/discovery/deterministic') {
      if (request.method !== 'POST' || !hasValidWorkerToken(
        request.headers['x-discovery-worker-token'], configuration.discoveryWorkerToken,
      )) {
        writeJson(response, 401, { error: 'unauthorized' });
        return;
      }
      const body = await readJsonBody(request, requestUrl.pathname.endsWith('/search') ? 4_096 : 16 * 1_024);
      if (requestUrl.pathname.endsWith('/search')) {
        if (body == null || !validDiscoverySearchRequest(
          body, configuration.discoverySearchProfile.sourcePolicies,
        )) {
          writeJson(response, 400, { error: 'invalid_discovery_search_request' });
          return;
        }
        const result = await searchTavily({
          request: normalizedDiscoverySearchRequest(body, configuration.discoverySearchProfile.sourcePolicies),
          profile: configuration.discoverySearchProfile,
          fetcher,
        });
        if (!result.ok) {
          writeJson(response, result.error === 'search_unconfigured' ? 503 : 502, { error: result.error });
          return;
        }
        writeJson(response, 200, { results: result.results });
        return;
      }
      if (requestUrl.pathname.endsWith('/deterministic')) {
        if (body == null || !validDeterministicDiscoveryRequest(body)) {
          writeJson(response, 400, { error: 'invalid_deterministic_discovery_request' });
          return;
        }
        const result = await resolveDeterministicDiscovery({
          body,
          amapWebKey: configuration.amapWebKey,
          fetcher,
          timeoutMs: configuration.settings.upstreamTimeoutMs,
          now,
        });
        if (!result.ok) {
          writeJson(response, result.error === 'not_configured' ? 503 : 502, { error: result.error });
          return;
        }
        writeJson(response, 200, { candidates: result.candidates, evidence: result.evidence });
        return;
      }
      if (body == null || !validDiscoveryExtractRequest(body)) {
        writeJson(response, 400, { error: 'invalid_discovery_extract_request' });
        return;
      }
      const result = await extractDiscoveryCandidates({
        body,
        profiles: configuration.llmProfiles,
        routing: configuration.llmRouting,
        fetcher,
      });
      if (!result.ok) {
        writeJson(response, result.error === 'ai_unconfigured' ? 503 : 502, { error: result.error });
        return;
      }
      writeJson(response, 200, { candidates: result.candidates });
      return;
    }

    if (!hasValidAuthorization(request.headers.authorization, configuration.serviceToken)) {
      writeJson(response, 401, { error: 'unauthorized' });
      return;
    }

    const policy = ratePolicy(requestUrl.pathname);
    const limit = await requestRateLimiter.consume({
      key: rateLimitKey(request, policy),
      limit: policy.limit,
      windowMs: policy.windowMs,
      now: now(),
    });
    if (!limit.allowed) {
      writeJson(response, 429, { error: 'rate_limited' }, {
        'Retry-After': String(limit.retryAfterSeconds),
      });
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/companion/refresh') {
      const idempotencyKey = request.headers['idempotency-key'];
      const body = await readJsonBody(request, 2 * 1024);
      if (!validIdempotencyKey(idempotencyKey) ||
          body == null || !validCompanionRefreshRequest(body)) {
        writeApiError(response, 400, 'invalid_snapshot');
        return;
      }
      const result = companion.refresh(body, idempotencyKey);
      if (!result.ok) {
        writeApiError(response, result.error === 'invalid_snapshot' ? 400 : 502, result.error);
        return;
      }
      writeJson(response, result.status, result.body);
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/inspiration/inventory') {
      const query = parseInventoryQuery(requestUrl.searchParams);
      if (query == null) {
        writeApiError(response, 400, 'invalid_inventory_query');
        return;
      }
      writeJson(response, 200, companion.listInventory(query));
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/sky-opportunities') {
      const query = validSkyOpportunityQuery(requestUrl.searchParams);
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_sky_opportunity_query' });
        return;
      }
      writeJson(response, 200, await skyOpportunityService.forecast(query));
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/sky-opportunities/daily') {
      const query = validDailySkyOpportunityQuery(requestUrl.searchParams);
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_sky_opportunity_query' });
        return;
      }
      writeJson(response, 200, await skyOpportunityService.daily(query));
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/metrics') {
      writeText(response, 200, skyOpportunityMetrics.toPrometheus());
      return;
    }

    const feedbackMatch = /^\/v1\/insights\/(insight_[a-f0-9]{24})\/feedback$/.exec(
      requestUrl.pathname,
    );
    if (request.method === 'POST' && feedbackMatch != null) {
      const idempotencyKey = request.headers['idempotency-key'];
      const body = await readJsonBody(request, 1024);
      if (!validIdempotencyKey(idempotencyKey) ||
          body == null || !validInsightFeedbackRequest(body)) {
        writeApiError(response, 400, 'invalid_feedback');
        return;
      }
      const result = companion.feedback(feedbackMatch[1], body.action, idempotencyKey);
      if (!result.ok) {
        writeApiError(response, 404, result.error);
        return;
      }
      writeJson(response, 200, result.body);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/context/safety-detail') {
      const body = await readJsonBody(request, 512);
      if (body == null || !validSafetyDetailRequest(body)) {
        writeJson(response, 400, { error: 'invalid_safety_detail_request' });
        return;
      }
      const detail = typeof weatherCache.getSafetyDetail === 'function'
        ? await weatherCache.getSafetyDetail(body.contextId, body.eventId, now())
        : null;
      if (detail == null) {
        writeJson(response, 404, { error: 'safety_detail_unavailable' });
        return;
      }
      writeJson(response, 200, detail);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/route/weather') {
      const body = await readJsonBody(request, 8 * 1024);
      const requestedAt = now();
      if (body == null || !validRouteWeatherRequest(body, requestedAt)) {
        writeJson(response, 400, { error: 'invalid_route_weather_request' });
        return;
      }
      const result = await routeWeatherForecast({
        body,
        now: () => requestedAt,
        fetchWeather: (coordinate) => authoritativeWeather({
          coordinate,
          apiHost: configuration.qweatherApiHost,
          privateKey: configuration.privateKey,
          keyId: configuration.keyId,
          projectId: configuration.projectId,
          cache: weatherCache,
          fetcher,
          now,
          timeoutMs: configuration.settings.upstreamTimeoutMs,
        }),
      });
      if (!result.ok) {
        const configured = configuration.qweatherApiHost && configuration.privateKey &&
          configuration.keyId && configuration.projectId;
        writeJson(response, configured ? 502 : 503, {
          error: configured ? 'upstream_unavailable' : 'weather_unconfigured',
        });
        return;
      }
      writeJson(response, 200, result.body);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/context/shooting-feedback') {
      const body = await readJsonBody(request, 4 * 1024);
      if (body == null || !validShootingFeedbackRequest(body)) {
        writeJson(response, 400, { error: 'invalid_shooting_feedback_request' });
        return;
      }
      const simulationSession = request.headers['x-lumanest-debug-session'];
      if (isSimulationSessionId(simulationSession) &&
          simulationRegistry?.suppressFeedback(simulationSession)) {
        writeJson(response, 202, { accepted: true });
        return;
      }
      const result = await forwardShootingFeedback({
        body,
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
      writeJson(response, 202, { accepted: true });
      return;
    }

    const amapMediaMatch = requestUrl.pathname.match(
      /^\/v1\/amap\/media\/([A-Za-z0-9_-]{16,1800})$/,
    );
    if (request.method === 'GET' && amapMediaMatch != null) {
      await proxyAmapPhoto(
        response,
        amapMediaMatch[1],
        fetcher,
        configuration.settings.upstreamTimeoutMs,
      );
      return;
    }

    const verifiedMediaMatch = requestUrl.pathname.match(
      /^\/v1\/explore\/media\/([A-Za-z0-9_-]{16,2800})$/,
    );
    if (request.method === 'GET' && verifiedMediaMatch != null) {
      await proxyVerifiedPlaceMedia(
        response,
        verifiedMediaMatch[1],
        fetcher,
        configuration.settings.upstreamTimeoutMs,
      );
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/explore/place-media') {
      const mediaRequest = parsePlaceMediaRequest(requestUrl.searchParams);
      if (mediaRequest == null) {
        writeJson(response, 400, { error: 'invalid_place_media_request' });
        return;
      }
      const cacheKey = createHash('sha256')
        .update(`${mediaRequest.name}:${mediaRequest.city ?? ''}:` +
          `${mediaRequest.latitude.toFixed(4)}:${mediaRequest.longitude.toFixed(4)}`)
        .digest('hex');
      const cached = placeMediaCache.get(cacheKey);
      if (cached != null && now().getTime() - cached.createdAt < 24 * 60 * 60 * 1_000) {
        writeJson(response, 200, {
          status: cached.media == null ? 'unavailable' : 'ok',
          media: cached.media,
          cacheStatus: 'hit',
        });
        return;
      }
      const result = await searchVerifiedPlaceMedia({
        request: mediaRequest,
        fetcher,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!result.ok) {
        writeJson(response, 200, { status: 'unavailable', media: null, cacheStatus: 'miss' });
        return;
      }
      placeMediaCache.set(cacheKey, { createdAt: now().getTime(), media: result.media });
      writeJson(response, 200, {
        status: result.media == null ? 'unavailable' : 'ok',
        media: result.media,
        cacheStatus: 'miss',
      });
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
        sortrule: 'distance',
        extensions: 'all',
      }, configuration.amapWebKey, fetcher, configuration.settings.upstreamTimeoutMs,
      normalizedAmapNearbyBody);
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
      // This header is emitted only by Flutter debug builds. A release build
      // never sends it, and an inactive registry entry has no effect.
      const simulationSession = request.headers['x-lumanest-debug-session'];
      if (simulationRegistry != null && isSimulationSessionId(simulationSession)) {
        const debugContract = Number.parseInt(
          request.headers['x-lumanest-debug-contract'] ?? '',
          10,
        );
        simulationRegistry.register(simulationSession, {
          contractVersion: Number.isInteger(debugContract) ? debugContract : null,
        });
        const simulated = simulationRegistry.snapshot(simulationSession, now());
        if (simulated != null) {
          writeJson(response, 200, simulated);
          return;
        }
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
        officialWarnings: weather.body.officialWarnings.map((warning) => ({
          id: warning.id,
          observedAt: warning.observedAt,
          expiresAt: warning.expiresAt,
          severity: warning.severity,
          title: warning.title,
        })),
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
      const details = safetyDetailsFor(
        result.body.contextId,
        weather.body.officialWarnings,
        result.body.events.map((event) => event.id),
      );
      if (details.length > 0 && typeof weatherCache.setSafetyDetails === 'function') {
        await weatherCache.setSafetyDetails(
          result.body.contextId,
          details,
          result.body.expiresAt,
        );
      }
      companion.rememberSnapshot(result.body);
      writeJson(response, 200, result.body);
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/v1/context/target-session') {
      const body = await readJsonBody(request, 2 * 1024);
      if (body == null || !validTargetSessionRequest(body)) {
        writeJson(response, 400, { error: 'invalid_target_session_request' });
        return;
      }
      const resolved = await resolveShootingTarget({
        targetId: body.targetId,
        coordinate: body.targetCoordinate,
        serviceUrl: configuration.contextServiceUrl,
        internalToken: configuration.contextInternalToken,
        fetcher,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!resolved.ok) {
        const status = resolved.error === 'not_found'
          ? 404
          : resolved.error === 'not_configured' ? 503 : 502;
        writeJson(response, status, {
          error: resolved.error === 'not_found'
            ? 'shooting_target_unavailable'
            : resolved.error === 'not_configured'
              ? 'context_unconfigured'
              : 'upstream_unavailable',
        });
        return;
      }
      const weather = await authoritativeWeather({
        coordinate: resolved.target.coordinate,
        apiHost: configuration.qweatherApiHost,
        privateKey: configuration.privateKey,
        keyId: configuration.keyId,
        projectId: configuration.projectId,
        cache: weatherCache,
        fetcher,
        now,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!weather.ok) {
        writeJson(response, weather.error === 'not_configured' ? 503 : 502, {
          error: weather.error === 'not_configured' ? 'weather_unconfigured' : 'upstream_unavailable',
        });
        return;
      }
      const internalBody = {
        contractVersion: 4,
        coordinate: resolved.target.coordinate,
        observedAt: body.observedAt,
        locale: body.locale,
        intent: 'photography',
        route: { mode: 'none', stage: 'none' },
        evidence: {
          urban: false,
          waterBody: true,
          mountainous: false,
          aridLand: false,
          settlement: false,
        },
        weather: weather.body.weather,
        forecast: weather.body.forecast,
        officialWarnings: weather.body.officialWarnings.map((warning) => ({
          id: warning.id,
          observedAt: warning.observedAt,
          expiresAt: warning.expiresAt,
          severity: warning.severity,
          title: warning.title,
        })),
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

    if (request.method === 'POST' && requestUrl.pathname === '/v1/explore/discover') {
      const body = await readJsonBody(request, 1024);
      if (body == null || !validDiscoveryRequest(body)) {
        writeJson(response, 400, { error: 'invalid_discovery_request' });
        return;
      }
      const result = await forwardDiscovery({
        body,
        serviceUrl: configuration.discoveryServiceUrl,
        internalToken: configuration.discoveryInternalToken,
        sourcePolicies: configuration.discoverySearchProfile.sourcePolicies,
        fetcher,
        timeoutMs: configuration.settings.upstreamTimeoutMs,
      });
      if (!result.ok) {
        writeJson(response, result.error === 'not_configured' ? 503 : 502, {
          error: result.error === 'not_configured' ? 'discovery_unconfigured' : 'upstream_unavailable',
        });
        return;
      }
      writeJson(response, result.body.status === 'pending' ? 202 : 200, result.body);
      return;
    }

    writeJson(response, 404, { error: 'not_found' });
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
    contextServiceUrl: environment.CONTEXT_SERVICE_URL?.trim() ?? '',
    contextInternalToken: environment.CONTEXT_INTERNAL_TOKEN?.trim() ?? '',
    discoveryServiceUrl: environment.DISCOVERY_SERVICE_URL?.trim() ?? '',
    discoveryInternalToken: environment.DISCOVERY_INTERNAL_TOKEN?.trim() ?? '',
    discoveryWorkerToken: environment.DISCOVERY_WORKER_TOKEN?.trim() ?? '',
    qweatherApiHost: environment.QWEATHER_API_HOST?.trim() ?? '',
    sunsetBotBaseUrl: environment.SUNSETBOT_BASE_URL?.trim() || 'https://sunsetbot.top',
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
    bootstrapPassword: environment.LUMANEST_ADMIN_BOOTSTRAP_PASSWORD?.trim() ||
      environment.LUMANEST_ADMIN_PASSWORD?.trim() || '',
  });
  await authService.initialize();
  const auditLog = new AuditLog();
  const weatherCache = await RedisWeatherCache.connect(environment.REDIS_URL?.trim() ?? '') ??
    new MemoryWeatherCache();
  const skyOpportunityCache = await RedisSkyOpportunityCache.connect(
    environment.REDIS_URL?.trim() ?? '',
  ) ?? new MemorySkyOpportunityCache();
  const skyOpportunityMetrics = new SkyOpportunityMetrics();
  const redisRateLimiter = await RedisRequestRateLimiter.connect(
    environment.REDIS_URL?.trim() ?? '',
  );
  const requestRateLimiter = redisRateLimiter == null
    ? new MemoryRequestRateLimiter()
    : new FallbackRequestRateLimiter(redisRateLimiter);
  const simulationEnabled = /^(?:1|true|yes)$/i.test(
    environment.LUMANEST_SIMULATION_ENABLED?.trim() ?? '',
  );
  const simulationRegistry = simulationEnabled ? new SimulationRegistry() : null;
  const appServer = createTokenBrokerServer({
    runtimeConfig,
    weatherCache,
    sunsetBotBaseUrl: defaults.sunsetBotBaseUrl,
    skyOpportunityCache,
    skyOpportunityMetrics,
    skyOpportunityLogger: (entry) => console.info(JSON.stringify(entry)),
    requestRateLimiter,
    simulationRegistry,
  });
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
    getShootingCalibration: async ({ days, minimumSamples }) => {
      const snapshot = runtimeConfig.snapshot();
      return fetchShootingCalibration({
        days,
        minimumSamples,
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
    simulationEnabled,
    simulationRegistry,
    outboundNetworkController: createOutboundNetworkControllerClient({
      baseUrl: environment.LUMANEST_OUTBOUND_NETWORK_CONTROLLER_URL ?? '',
      token: environment.LUMANEST_NETWORK_CONTROLLER_TOKEN ?? '',
    }),
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
