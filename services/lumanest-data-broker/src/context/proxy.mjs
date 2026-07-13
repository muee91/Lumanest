const requestKeys = new Set([
  'contractVersion', 'coordinate', 'observedAt', 'locale', 'intent',
  'route', 'evidence', 'weather', 'solar',
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

export function validContextRequest(body) {
  if (!exactKeys(body, requestKeys) || body.contractVersion !== 2) return false;
  if (!exactKeys(body.coordinate, new Set(['latitude', 'longitude', 'system'])) ||
      body.coordinate.system !== 'wgs84' ||
      !finiteIn(body.coordinate.latitude, -90, 90) ||
      !finiteIn(body.coordinate.longitude, -180, 180)) return false;
  if (typeof body.observedAt !== 'string' || !Number.isFinite(Date.parse(body.observedAt))) return false;
  if (!['zh-CN', 'en'].includes(body.locale)) return false;
  if (!['photography', 'food', 'supplies', 'fuel', 'wildlife'].includes(body.intent)) return false;
  if (!exactKeys(body.route, new Set(['mode', 'stage'])) ||
      !['none', 'driving', 'hiking'].includes(body.route.mode) ||
      !['none', 'planned', 'active', 'paused'].includes(body.route.stage)) return false;
  if (!exactKeys(body.evidence, new Set([
    'urban', 'waterBody', 'mountainous', 'aridLand', 'settlement',
  ])) || Object.values(body.evidence).some((value) => typeof value !== 'boolean')) return false;
  if (!exactKeys(body.weather, new Set([
    'observedAt', 'condition', 'windSpeedMps', 'precipitationMm',
    'visibilityKm', 'thunder', 'stale',
  ]))) return false;
  if (typeof body.weather.observedAt !== 'string' ||
      !Number.isFinite(Date.parse(body.weather.observedAt)) ||
      !['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(body.weather.condition) ||
      !finiteIn(body.weather.windSpeedMps, 0, 150) ||
      !finiteIn(body.weather.precipitationMm, 0, 2000) ||
      !finiteIn(body.weather.visibilityKm, 0, 500) ||
      typeof body.weather.thunder !== 'boolean' || typeof body.weather.stale !== 'boolean') return false;
  return exactKeys(body.solar, new Set(['dayPhase'])) &&
    ['dawn', 'day', 'sunset', 'blueHour', 'night'].includes(body.solar.dayPhase);
}

function validContextResponse(body) {
  return object(body) && body.contractVersion === 2 &&
    typeof body.contextId === 'string' && /^ctx_[a-f0-9]{24}$/.test(body.contextId) &&
    typeof body.generatedAt === 'string' && typeof body.expiresAt === 'string' &&
    typeof body.scene === 'string' && typeof body.fingerprint === 'string' &&
    typeof body.stale === 'boolean' && Array.isArray(body.events) && object(body.manifest);
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
