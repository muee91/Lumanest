const canonicalRequestKeys = new Set([
  'contractVersion', 'coordinate', 'observedAt', 'locale', 'intent', 'route',
]);
const legacyRequestKeys = new Set([
  ...canonicalRequestKeys, 'evidence', 'weather', 'solar',
]);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}
function exactKeys(value, keys) {
  return object(value) && Object.keys(value).every((key) => keys.has(key));
}

function finiteIn(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

// ContextSnapshotV2 route invariant:
//   mode == 'none'  iff  stage == 'none'
//   when mode != 'none', stage must be one of planned/active/paused
//   (covered structurally by the iff rule given the allowed enum values)
// For responses, active must equal (stage == 'active').
function validRouteModeStage(mode, stage) {
  return (mode === 'none') === (stage === 'none');
}

export function validContextRequest(body) {
  const keys = Object.keys(body ?? {});
  const legacy = keys.some((key) => ['evidence', 'weather', 'solar'].includes(key));
  if (!exactKeys(body, legacy ? legacyRequestKeys : canonicalRequestKeys) ||
      body.contractVersion !== 2) return false;
  if (!exactKeys(body.coordinate, new Set(['latitude', 'longitude', 'system'])) ||
      body.coordinate.system !== 'wgs84' ||
      !finiteIn(body.coordinate.latitude, -90, 90) ||
      !finiteIn(body.coordinate.longitude, -180, 180)) return false;
  if (typeof body.observedAt !== 'string' || !Number.isFinite(Date.parse(body.observedAt))) return false;
  if (!['zh-CN', 'en'].includes(body.locale)) return false;
  if (!['photography', 'food', 'supplies', 'fuel', 'wildlife'].includes(body.intent)) return false;
  if (!exactKeys(body.route, new Set(['mode', 'stage'])) ||
      !['none', 'driving', 'hiking'].includes(body.route.mode) ||
      !['none', 'planned', 'active', 'paused'].includes(body.route.stage) ||
      !validRouteModeStage(body.route.mode, body.route.stage)) return false;
  if (!legacy) return true;
  if (!exactKeys(body.evidence, new Set([
    'urban', 'waterBody', 'mountainous', 'aridLand', 'settlement',
  ])) || Object.values(body.evidence).some((value) => typeof value !== 'boolean')) return false;
  if (!exactKeys(body.weather, new Set([
    'observedAt', 'condition', 'windSpeedMps', 'precipitationMm',
    'visibilityKm', 'thunder', 'stale', 'temperatureCelsius',
    'windDirectionDegrees', 'cloudCoverPercent',
  ]))) return false;
  if (typeof body.weather.observedAt !== 'string' ||
      !Number.isFinite(Date.parse(body.weather.observedAt)) ||
      !['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(body.weather.condition) ||
      !finiteIn(body.weather.windSpeedMps, 0, 150) ||
      !finiteIn(body.weather.precipitationMm, 0, 2000) ||
      !finiteIn(body.weather.visibilityKm, 0, 500) ||
      typeof body.weather.thunder !== 'boolean' || typeof body.weather.stale !== 'boolean') return false;
  for (const key of ['temperatureCelsius', 'windDirectionDegrees', 'cloudCoverPercent']) {
    if (body.weather[key] != null && typeof body.weather[key] !== 'number') return false;
  }
  if (body.weather.temperatureCelsius != null && !finiteIn(body.weather.temperatureCelsius, -100, 100)) return false;
  if (body.weather.windDirectionDegrees != null &&
      (!finiteIn(body.weather.windDirectionDegrees, 0, 360) || body.weather.windDirectionDegrees === 360)) return false;
  if (body.weather.cloudCoverPercent != null && !finiteIn(body.weather.cloudCoverPercent, 0, 100)) return false;
  return exactKeys(body.solar, new Set(['dayPhase', 'elevationDegrees', 'azimuthDegrees'])) &&
    ['dawn', 'day', 'sunset', 'blueHour', 'night'].includes(body.solar.dayPhase) &&
    (body.solar.elevationDegrees == null || finiteIn(body.solar.elevationDegrees, -90, 90)) &&
    (body.solar.azimuthDegrees == null ||
      (finiteIn(body.solar.azimuthDegrees, 0, 360) && body.solar.azimuthDegrees !== 360));
}

export function isLegacyContextRequest(body) {
  return object(body) && ['evidence', 'weather', 'solar'].some((key) => Object.hasOwn(body, key));
}

const actions = new Set([
  'openExplore', 'openShootingWindow', 'openWeather', 'openSafety', 'openRoute',
  'openAuthority',
]);
const moonPhases = new Set([
  'newMoon', 'waxingCrescent', 'firstQuarter', 'waxingGibbous',
  'fullMoon', 'waningGibbous', 'lastQuarter', 'waningCrescent',
]);

function validEvent(value) {
  if (!exactKeys(value, new Set([
    'id', 'channel', 'source', 'observedAt', 'expiresAt', 'confidence',
    'geoScope', 'severity', 'allowedAction', 'title', 'sourceUrl',
  ])) || typeof value.id !== 'string' || !/^[a-z0-9_-]{1,64}$/.test(value.id) ||
    !['opportunity', 'safety', 'wildlifeOpportunity', 'wildlifeSafety'].includes(value.channel) ||
    !['weather', 'solar', 'rule', 'official', 'wildlifeHistorical', 'astronomyCatalog'].includes(value.source) ||
    typeof value.observedAt !== 'string' || !Number.isFinite(Date.parse(value.observedAt)) ||
    typeof value.expiresAt !== 'string' || !Number.isFinite(Date.parse(value.expiresAt)) ||
    !finiteIn(value.confidence, 0, 1) || !['point', 'regional', 'route'].includes(value.geoScope) ||
    !['info', 'caution', 'warning', 'critical'].includes(value.severity) || !actions.has(value.allowedAction)) {
    return false;
  }
  if (value.allowedAction === 'openAuthority') {
    if (value.source !== 'astronomyCatalog' || typeof value.title !== 'string' ||
        [...value.title.trim()].length < 1 || [...value.title.trim()].length > 80 ||
        typeof value.sourceUrl !== 'string' || value.sourceUrl.length > 500) return false;
    try {
      return new URL(value.sourceUrl).protocol === 'https:';
    } catch {
      return false;
    }
  }
  return value.sourceUrl == null && (value.title == null ||
    (typeof value.title === 'string' && [...value.title.trim()].length >= 1 &&
      [...value.title.trim()].length <= 80));
}

function validContextResponse(body) {
  if (!exactKeys(body, new Set([
    'contractVersion', 'contextId', 'generatedAt', 'expiresAt', 'scene', 'fingerprint',
    'stale', 'dataFreshness', 'weather', 'sunMoon', 'route', 'events', 'allowedActions', 'manifest',
  ])) || body.contractVersion !== 2) return false;
  if (!/^ctx_[a-f0-9]{24}$/.test(body.contextId) ||
      !Number.isFinite(Date.parse(body.generatedAt)) || !Number.isFinite(Date.parse(body.expiresAt)) ||
      !['unknown', 'city', 'lake', 'mountain', 'desert', 'village', 'driving', 'hiking'].includes(body.scene) ||
      !/^[a-f0-9]{24}$/.test(body.fingerprint) || typeof body.stale !== 'boolean' ||
      !body.events.every(validEvent)) return false;
  const freshness = body.dataFreshness;
  if (!exactKeys(freshness, new Set(['context', 'weather', 'weatherObservedAt'])) ||
      !['fresh', 'stale'].includes(freshness.context) || !['fresh', 'stale'].includes(freshness.weather) ||
      typeof freshness.weatherObservedAt !== 'string' || !Number.isFinite(Date.parse(freshness.weatherObservedAt))) return false;
  const weather = body.weather;
  if (!exactKeys(weather, new Set([
    'condition', 'temperatureCelsius', 'windSpeedMps', 'windDirectionDegrees', 'precipitationMm',
    'visibilityKm', 'cloudCoverPercent', 'thunder', 'airQualityIndex', 'airQualityCategory',
    'primaryPollutant', 'airQualityObservedAt', 'airQualityStale',
  ])) || !['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(weather.condition) ||
      (weather.temperatureCelsius != null && !finiteIn(weather.temperatureCelsius, -100, 100)) ||
      !finiteIn(weather.windSpeedMps, 0, 150) ||
      (weather.windDirectionDegrees != null &&
        (!finiteIn(weather.windDirectionDegrees, 0, 360) || weather.windDirectionDegrees === 360)) ||
      !finiteIn(weather.precipitationMm, 0, 2000) || !finiteIn(weather.visibilityKm, 0, 500) ||
      (weather.cloudCoverPercent != null && !finiteIn(weather.cloudCoverPercent, 0, 100)) ||
      typeof weather.thunder !== 'boolean' ||
      (weather.airQualityIndex != null && !Number.isInteger(weather.airQualityIndex)) ||
      (weather.airQualityIndex != null && !finiteIn(weather.airQualityIndex, 0, 500)) ||
      (weather.airQualityCategory != null &&
        (typeof weather.airQualityCategory !== 'string' || weather.airQualityCategory.length > 40)) ||
      (weather.primaryPollutant != null &&
        (typeof weather.primaryPollutant !== 'string' || weather.primaryPollutant.length > 40)) ||
      (weather.airQualityObservedAt != null &&
        (typeof weather.airQualityObservedAt !== 'string' ||
          !Number.isFinite(Date.parse(weather.airQualityObservedAt)))) ||
      typeof weather.airQualityStale !== 'boolean') return false;
  if ((weather.airQualityIndex == null) !== (weather.airQualityObservedAt == null)) return false;
  const sunMoon = body.sunMoon;
  if (!exactKeys(sunMoon, new Set([
    'dayPhase', 'sunElevationDegrees', 'sunAzimuthDegrees', 'moonPhase', 'moonIllumination',
  ])) || !['dawn', 'day', 'sunset', 'blueHour', 'night'].includes(sunMoon.dayPhase) ||
      (sunMoon.sunElevationDegrees != null && !finiteIn(sunMoon.sunElevationDegrees, -90, 90)) ||
      (sunMoon.sunAzimuthDegrees != null &&
        (!finiteIn(sunMoon.sunAzimuthDegrees, 0, 360) || sunMoon.sunAzimuthDegrees === 360)) ||
      !moonPhases.has(sunMoon.moonPhase) || !finiteIn(sunMoon.moonIllumination, 0, 1)) return false;
  if (!exactKeys(body.route, new Set(['mode', 'stage', 'active'])) ||
      !['none', 'driving', 'hiking'].includes(body.route.mode) ||
      !['none', 'planned', 'active', 'paused'].includes(body.route.stage) ||
      !validRouteModeStage(body.route.mode, body.route.stage) ||
      typeof body.route.active !== 'boolean' ||
      body.route.active !== (body.route.stage === 'active') ||
      !Array.isArray(body.allowedActions) ||
      body.allowedActions.some((action) => !actions.has(action)) ||
      new Set(body.allowedActions).size !== body.allowedActions.length) return false;
  return exactKeys(body.manifest, new Set([
    'layoutMode', 'primaryEventId', 'secondaryEventIds', 'safetyEventIds',
  ])) && ['quiet', 'opportunity', 'safety'].includes(body.manifest.layoutMode) &&
    (body.manifest.primaryEventId == null || typeof body.manifest.primaryEventId === 'string') &&
    Array.isArray(body.manifest.secondaryEventIds) && Array.isArray(body.manifest.safetyEventIds);
}

export async function forwardContextSnapshot({
  body,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const url = new URL('/internal/v1/evaluate', serviceUrl);
    const upstream = await fetcher(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (!upstream.ok || !validContextResponse(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, body: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

export async function listContextSources({ serviceUrl, internalToken, fetcher = fetch, timeoutMs = 8_000 }) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/sources', serviceUrl), {
      headers: { 'X-Internal-Service-Token': internalToken },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await upstream.json();
    if (!upstream.ok || !Array.isArray(body)) return { ok: false, error: 'upstream_unavailable' };
    return { ok: true, sources: body };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function validPosition(value) {
  return Array.isArray(value) && value.length >= 2 &&
    finiteIn(value[0], -180, 180) && finiteIn(value[1], -90, 90);
}

function validRing(value) {
  return Array.isArray(value) && value.length >= 4 && value.every(validPosition) &&
    value[0][0] === value.at(-1)[0] && value[0][1] === value.at(-1)[1];
}

function validWildlifeGeometry(value) {
  if (!exactKeys(value, new Set(['type', 'coordinates'])) || !Array.isArray(value.coordinates)) return false;
  if (value.type === 'Polygon') return value.coordinates.length > 0 && value.coordinates.every(validRing);
  if (value.type === 'MultiPolygon') {
    return value.coordinates.length > 0 && value.coordinates.every((polygon) =>
      Array.isArray(polygon) && polygon.length > 0 && polygon.every(validRing));
  }
  return false;
}

function validWildlifeLayerResponse(body) {
  if (!exactKeys(body, new Set(['contractVersion', 'generatedAt', 'radiusKm', 'areas'])) ||
      body.contractVersion !== 1 || !Number.isFinite(Date.parse(body.generatedAt)) ||
      !Number.isInteger(body.radiusKm) || body.radiusKm < 5 || body.radiusKm > 50 ||
      !Array.isArray(body.areas) || body.areas.length > 50) return false;
  return body.areas.every((area) =>
    exactKeys(area, new Set(['id', 'name', 'geometry', 'source'])) &&
    typeof area.id === 'string' && /^[a-f0-9]{64}$/.test(area.id) &&
    typeof area.name === 'string' && [...area.name.trim()].length >= 1 && [...area.name.trim()].length <= 200 &&
    validWildlifeGeometry(area.geometry) &&
    exactKeys(area.source, new Set(['attribution', 'version', 'updatedAt'])) &&
    typeof area.source.attribution === 'string' && area.source.attribution.trim().length > 0 &&
    typeof area.source.version === 'string' && area.source.version.trim().length > 0 &&
    (area.source.updatedAt == null ||
      (typeof area.source.updatedAt === 'string' && Number.isFinite(Date.parse(area.source.updatedAt)))));
}

export async function fetchWildlifeLayers({
  latitude,
  longitude,
  radiusKm,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const url = new URL('/internal/v1/wildlife/layers', serviceUrl);
    url.searchParams.set('latitude', String(latitude));
    url.searchParams.set('longitude', String(longitude));
    url.searchParams.set('radiusKm', String(radiusKm));
    const upstream = await fetcher(url, {
      headers: { 'X-Internal-Service-Token': internalToken },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await upstream.json();
    if (!upstream.ok || !validWildlifeLayerResponse(body)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, body };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function validImportResult(body) {
  return object(body) && typeof body.sourceId === 'string' &&
    ['spatialFeatures', 'astronomyEvents'].includes(body.datasetType) &&
    Number.isInteger(body.importedCount) && body.importedCount >= 0 &&
    typeof body.enabled === 'boolean' && typeof body.cacheInvalidated === 'boolean';
}

export async function importContextDataset({
  body,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 20_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/imports', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (upstream.status === 422) return { ok: false, error: 'invalid_import' };
    if (!upstream.ok || !validImportResult(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, result: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}
