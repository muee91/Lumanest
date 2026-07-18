const amapBaseUrl = 'https://restapi.amap.com';
const requestKeys = new Set(['missionType', 'focus', 'locale', 'region', 'evidence']);
const regionKeys = new Set(['latitude', 'longitude', 'radiusMeters']);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return object(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function boundedText(value, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  return normalized.length > 0 && [...normalized].length <= maximum ? normalized : null;
}

export function validDeterministicDiscoveryRequest(body) {
  return exactKeys(body, requestKeys) &&
    ['routeConditions', 'openingAndClosure'].includes(body.missionType) &&
    boundedText(body.focus, 180) != null &&
    typeof body.locale === 'string' && /^[a-z]{2,3}(?:-[a-z0-9]{2,8})?$/i.test(body.locale) &&
    exactKeys(body.region, regionKeys) && finite(body.region.latitude, -90, 90) &&
    finite(body.region.longitude, -180, 180) && Number.isInteger(body.region.radiusMeters) &&
    finite(body.region.radiusMeters, 100, 50_000) && Array.isArray(body.evidence) &&
    body.evidence.length <= 24;
}

function transformLatitude(longitude, latitude) {
  let result = -100 + 2 * longitude + 3 * latitude + .2 * latitude * latitude +
    .1 * longitude * latitude + .2 * Math.sqrt(Math.abs(longitude));
  result += (20 * Math.sin(6 * longitude * Math.PI) + 20 * Math.sin(2 * longitude * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(latitude * Math.PI) + 40 * Math.sin(latitude / 3 * Math.PI)) * 2 / 3;
  return result + (160 * Math.sin(latitude / 12 * Math.PI) + 320 * Math.sin(latitude * Math.PI / 30)) * 2 / 3;
}

function transformLongitude(longitude, latitude) {
  let result = 300 + longitude + 2 * latitude + .1 * longitude * longitude +
    .1 * longitude * latitude + .1 * Math.sqrt(Math.abs(longitude));
  result += (20 * Math.sin(6 * longitude * Math.PI) + 20 * Math.sin(2 * longitude * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(longitude * Math.PI) + 40 * Math.sin(longitude / 3 * Math.PI)) * 2 / 3;
  return result + (150 * Math.sin(longitude / 12 * Math.PI) + 300 * Math.sin(longitude / 30 * Math.PI)) * 2 / 3;
}

function outsideChina(latitude, longitude) {
  return longitude < 72.004 || longitude > 137.8347 || latitude < .8293 || latitude > 55.8271;
}

export function wgs84ToGcj02(latitude, longitude) {
  if (outsideChina(latitude, longitude)) return { latitude, longitude };
  const ellipsoid = 6_378_245;
  const eccentricity = .006693421622965943;
  let latitudeDelta = transformLatitude(longitude - 105, latitude - 35);
  let longitudeDelta = transformLongitude(longitude - 105, latitude - 35);
  const radians = latitude / 180 * Math.PI;
  let magic = Math.sin(radians);
  magic = 1 - eccentricity * magic * magic;
  const root = Math.sqrt(magic);
  latitudeDelta = latitudeDelta * 180 / ((ellipsoid * (1 - eccentricity)) / (magic * root) * Math.PI);
  longitudeDelta = longitudeDelta * 180 / (ellipsoid / root * Math.cos(radians) * Math.PI);
  return { latitude: latitude + latitudeDelta, longitude: longitude + longitudeDelta };
}

export function gcj02ToWgs84(latitude, longitude) {
  if (outsideChina(latitude, longitude)) return { latitude, longitude };
  // The GCJ transform is smooth. Two inverse iterations keep the public
  // WGS84 coordinate comfortably inside the product's five-decimal limit.
  let result = { latitude, longitude };
  for (let index = 0; index < 2; index += 1) {
    const projected = wgs84ToGcj02(result.latitude, result.longitude);
    result = {
      latitude: result.latitude - (projected.latitude - latitude),
      longitude: result.longitude - (projected.longitude - longitude),
    };
  }
  return result;
}

function source({ id, title, snippet, observedAt }) {
  return Object.freeze({
    sourceId: id,
    publisher: '高德地图',
    license: '高德开放平台服务',
    version: 'amap-web-service-v1',
    title,
    snippet,
    url: 'https://ditu.amap.com/',
    publishedAt: observedAt,
  });
}

function coordinateText(point) {
  return `${point.latitude.toFixed(5)},${point.longitude.toFixed(5)}`;
}

async function requestAmap(path, parameters, { amapWebKey, fetcher, timeoutMs }) {
  const url = new URL(path, amapBaseUrl);
  for (const [key, value] of Object.entries({ ...parameters, key: amapWebKey })) {
    if (value != null && `${value}`.length > 0) url.searchParams.set(key, `${value}`);
  }
  try {
    const response = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = await response.json();
    return response.ok && body?.status === '1' ? body : null;
  } catch {
    return null;
  }
}

async function routeConditions(body, options) {
  const center = wgs84ToGcj02(body.region.latitude, body.region.longitude);
  const upstream = await requestAmap('/v3/traffic/status/circle', {
    location: `${center.longitude.toFixed(6)},${center.latitude.toFixed(6)}`,
    radius: Math.min(body.region.radiusMeters, 5_000),
    level: 6,
    extensions: 'all',
  }, options);
  const description = boundedText(upstream?.trafficinfo?.description, 280);
  if (description == null) return { candidates: [], evidence: [] };
  const observedAt = options.now().toISOString();
  const point = { latitude: body.region.latitude, longitude: body.region.longitude };
  const exactCoordinate = coordinateText(point);
  const evidence = [source({
    id: 'amap-traffic',
    title: '高德实时路况',
    snippet: `${description} 坐标：${exactCoordinate}`,
    observedAt,
  })];
  return {
    evidence,
    candidates: [{
      kind: 'candidate_viewpoint',
      title: boundedText(body.focus, 120) ?? '路线当前路况',
      summary: description,
      coordinate: point,
      coordinateEvidence: exactCoordinate,
      sourceIndexes: [0],
    }],
  };
}

function parseAmapLocation(value) {
  if (typeof value !== 'string') return null;
  const parts = value.split(',').map(Number);
  if (parts.length !== 2 || !finite(parts[0], -180, 180) || !finite(parts[1], -90, 90)) return null;
  const point = gcj02ToWgs84(parts[1], parts[0]);
  return {
    latitude: Number(point.latitude.toFixed(5)),
    longitude: Number(point.longitude.toFixed(5)),
  };
}

async function openingAndClosure(body, options) {
  const center = wgs84ToGcj02(body.region.latitude, body.region.longitude);
  const upstream = await requestAmap('/v3/place/around', {
    location: `${center.longitude.toFixed(6)},${center.latitude.toFixed(6)}`,
    keywords: body.focus,
    radius: Math.min(body.region.radiusMeters, 50_000),
    offset: 6,
    page: 1,
    extensions: 'all',
  }, options);
  if (!Array.isArray(upstream?.pois)) return { candidates: [], evidence: [] };
  const observedAt = options.now().toISOString();
  const evidence = [];
  const candidates = [];
  for (const poi of upstream.pois) {
    const title = boundedText(poi?.name, 120);
    const openTime = boundedText(poi?.biz_ext?.open_time, 160);
    const point = parseAmapLocation(poi?.location);
    if (title == null || openTime == null || point == null) continue;
    const exactCoordinate = coordinateText(point);
    const summary = `高德地点资料标注营业时间：${openTime}`;
    const index = evidence.length;
    evidence.push(source({
      id: 'amap-poi',
      title: `${title}营业资料`,
      snippet: `${summary} 坐标：${exactCoordinate}`,
      observedAt,
    }));
    candidates.push({
      kind: 'attraction',
      title,
      summary,
      coordinate: point,
      coordinateEvidence: exactCoordinate,
      sourceIndexes: [index],
    });
    if (candidates.length === 6) break;
  }
  return { candidates, evidence };
}

export async function resolveDeterministicDiscovery({
  body,
  amapWebKey,
  fetcher = fetch,
  timeoutMs = 8_000,
  now = () => new Date(),
}) {
  if (!validDeterministicDiscoveryRequest(body) || !amapWebKey) {
    return { ok: false, error: 'not_configured' };
  }
  const options = { amapWebKey, fetcher, timeoutMs, now };
  const result = body.missionType === 'routeConditions'
    ? await routeConditions(body, options)
    : await openingAndClosure(body, options);
  return { ok: true, ...result };
}
