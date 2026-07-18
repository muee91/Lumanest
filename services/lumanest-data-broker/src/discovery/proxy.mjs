const missionTypes = new Set([
  'popularPlaces', 'hiddenPlaces', 'humanityEvents', 'localStories',
  'routeConditions', 'openingAndClosure', 'seasonalSignals',
]);
const publicRequestKeys = new Set([
  'missionType', 'focus', 'locale', 'region', 'timeRange', 'routeCorridor', 'interests',
]);
const responseKeys = new Set([
  'missionType', 'status', 'generatedAt', 'expiresAt', 'retryAfterSeconds', 'items',
]);
const itemKeys = new Set([
  'id', 'kind', 'title', 'subtitle', 'placeStatus', 'coordinate', 'distanceMeters',
  'address', 'startsAt', 'endsAt', 'evidence',
]);
const regionKeys = new Set(['latitude', 'longitude', 'radiusMeters']);
const timeRangeKeys = new Set(['startsAt', 'endsAt']);
const corridorKeys = new Set(['routeId', 'name', 'samples']);
const sampleKeys = new Set(['latitude', 'longitude']);
const coordinateKeys = new Set(['latitude', 'longitude', 'system']);
const evidenceKeys = new Set(['publisher', 'title', 'url', 'observedAt']);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return object(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function finiteIn(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function validString(value, maximum) {
  return typeof value === 'string' && value.trim().length > 0 && [...value].length <= maximum;
}

function validCoordinate(value) {
  return exactKeys(value, coordinateKeys) && value.system === 'wgs84' &&
    finiteIn(value.latitude, -90, 90) && finiteIn(value.longitude, -180, 180);
}

function validRegion(value) {
  return exactKeys(value, regionKeys) && finiteIn(value.latitude, -90, 90) &&
    finiteIn(value.longitude, -180, 180) && Number.isInteger(value.radiusMeters) &&
    finiteIn(value.radiusMeters, 100, 50_000);
}

function validTimeRange(value) {
  return exactKeys(value, timeRangeKeys) && validDate(value.startsAt) && validDate(value.endsAt) &&
    Date.parse(value.endsAt) > Date.parse(value.startsAt) &&
    Date.parse(value.endsAt) - Date.parse(value.startsAt) <= 31 * 86_400_000;
}

function validRouteCorridor(value) {
  if (value === null) return true;
  return exactKeys(value, corridorKeys) && validString(value.routeId, 160) &&
    validString(value.name, 160) && Array.isArray(value.samples) &&
    value.samples.length >= 2 && value.samples.length <= 16 &&
    value.samples.every((sample) => exactKeys(sample, sampleKeys) &&
      finiteIn(sample.latitude, -90, 90) && finiteIn(sample.longitude, -180, 180));
}

function validUrl(value) {
  if (!validString(value, 500)) return false;
  try {
    return new URL(value).protocol === 'https:';
  } catch {
    return false;
  }
}

export function validDiscoveryRequest(body) {
  return exactKeys(body, publicRequestKeys) && missionTypes.has(body.missionType) &&
    validString(body.focus, 180) && validString(body.locale, 16) &&
    /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(body.locale) &&
    validRegion(body.region) && validTimeRange(body.timeRange) &&
    validRouteCorridor(body.routeCorridor) && Array.isArray(body.interests) &&
    body.interests.length <= 16 && new Set(body.interests).size === body.interests.length &&
    body.interests.every((value) => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9._-]{0,63}$/.test(value)) &&
    (body.missionType !== 'routeConditions' || body.routeCorridor !== null);
}

function validEvidence(value) {
  return exactKeys(value, evidenceKeys) && validString(value.publisher, 100) &&
    validString(value.title, 300) && validUrl(value.url) && validDate(value.observedAt);
}

function validItem(value) {
  return exactKeys(value, itemKeys) && validString(value.id, 96) &&
    ['candidate_viewpoint', 'attraction', 'event'].includes(value.kind) &&
    validString(value.title, 240) && (value.subtitle == null || validString(value.subtitle, 600)) &&
    ['candidate', 'verified', 'mine'].includes(value.placeStatus) && validCoordinate(value.coordinate) &&
    Number.isInteger(value.distanceMeters) && finiteIn(value.distanceMeters, 0, 50_000) &&
    (value.address == null || validString(value.address, 300)) &&
    (value.startsAt == null || validDate(value.startsAt)) &&
    (value.endsAt == null || validDate(value.endsAt)) &&
    Array.isArray(value.evidence) && value.evidence.length > 0 && value.evidence.length <= 6 &&
    value.evidence.every(validEvidence);
}

export function validDiscoveryResponse(body) {
  if (!exactKeys(body, responseKeys) || !missionTypes.has(body.missionType) ||
      !['ready', 'refreshing', 'pending'].includes(body.status) ||
      !validDate(body.generatedAt) || (body.expiresAt != null && !validDate(body.expiresAt)) ||
      (body.retryAfterSeconds != null &&
        (!Number.isInteger(body.retryAfterSeconds) || !finiteIn(body.retryAfterSeconds, 1, 3_600))) ||
      !Array.isArray(body.items) || body.items.length > 40 || !body.items.every(validItem)) return false;
  return body.status !== 'pending' ||
    (body.items.length === 0 && body.retryAfterSeconds != null && body.expiresAt == null);
}

export async function forwardDiscovery({
  body,
  serviceUrl,
  internalToken,
  sourcePolicies = [],
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/discover', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify({
        ...body,
        sourcePolicies: sourcePolicies.filter((policy) => policy?.enabled).map((policy) => ({
          id: policy.id,
          version: policy.version,
        })),
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (!upstream.ok || !validDiscoveryResponse(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, body: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}
