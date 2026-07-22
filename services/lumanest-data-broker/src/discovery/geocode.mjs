import { gcj02ToWgs84, wgs84ToGcj02 } from './deterministic.mjs';

const amapBaseUrl = 'https://restapi.amap.com';
const requestKeys = new Set(['query', 'addressHint', 'region', 'locale']);
const regionKeys = new Set(['latitude', 'longitude', 'radiusMeters']);
export const regionIdentityQuery = '__region_identity__';
const relevantRegionType = /风景名胜|旅游景点|公园广场|自然地物|地名地址|行政区划|村庄|文化场馆|古镇|古村|景区/;
const genericRegionName = /^(?:中国|中华人民共和国|当前区域|附近|未知|无名)$/;
const regionIdentityCacheTtlMilliseconds = 24 * 60 * 60 * 1_000;
const regionIdentityNegativeCacheTtlMilliseconds = 15 * 60 * 1_000;
const maximumRegionIdentityCacheEntries = 512;
const defaultRegionIdentityCache = new Map();

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return object(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function text(value, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  return normalized.length > 0 && [...normalized].length <= maximum ? normalized : null;
}

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function scalarText(value, maximum = 80) {
  if (Array.isArray(value)) return value.length === 1 ? text(value[0], maximum) : null;
  return text(value, maximum);
}

function distanceMeters(value) {
  const parsed = Number(value?.distance);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : Number.POSITIVE_INFINITY;
}

function addRegionName(target, seen, value) {
  const name = scalarText(value);
  if (name == null || genericRegionName.test(name) || seen.has(name)) return;
  seen.add(name);
  target.push(name);
}

function regionIdentityCacheKey(body) {
  return `${body.region.latitude.toFixed(2)}:${body.region.longitude.toFixed(2)}:${body.locale.toLowerCase()}`;
}

function cachedRegionIdentity(cache, key, instant) {
  const entry = cache.get(key);
  if (entry == null) return null;
  if (entry.expiresAt <= instant.getTime()) {
    cache.delete(key);
    return null;
  }
  // Refresh insertion order so bounded eviction approximates an LRU policy.
  cache.delete(key);
  cache.set(key, entry);
  return structuredClone(entry.value);
}

function cacheRegionIdentity(cache, key, value, instant) {
  cache.delete(key);
  cache.set(key, {
    value: structuredClone(value),
    expiresAt: instant.getTime() + (value.status === 'resolved'
      ? regionIdentityCacheTtlMilliseconds
      : regionIdentityNegativeCacheTtlMilliseconds),
  });
  while (cache.size > maximumRegionIdentityCacheEntries) {
    cache.delete(cache.keys().next().value);
  }
}

export function validResolvePlaceRequest(body) {
  return exactKeys(body, requestKeys) && text(body.query, 240) != null &&
    (body.addressHint == null || text(body.addressHint, 300) != null) &&
    typeof body.locale === 'string' && /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(body.locale) &&
    exactKeys(body.region, regionKeys) && finite(body.region.latitude, -90, 90) &&
    finite(body.region.longitude, -180, 180) && Number.isInteger(body.region.radiusMeters) &&
    finite(body.region.radiusMeters, 100, 50_000);
}

function distanceKm(first, second) {
  const radians = Math.PI / 180;
  const latitude = (second.latitude - first.latitude) * radians;
  const longitude = (second.longitude - first.longitude) * radians;
  const value = Math.sin(latitude / 2) ** 2 +
    Math.cos(first.latitude * radians) * Math.cos(second.latitude * radians) * Math.sin(longitude / 2) ** 2;
  return 6_371 * 2 * Math.asin(Math.sqrt(value));
}

function parsePoi(poi, center, radiusMeters, query, addressHint) {
  if (!object(poi) || typeof poi.location !== 'string') return null;
  const [longitude, latitude] = poi.location.split(',').map(Number);
  if (!finite(longitude, -180, 180) || !finite(latitude, -90, 90)) return null;
  const point = gcj02ToWgs84(latitude, longitude);
  const coordinate = {
    latitude: Number(point.latitude.toFixed(5)),
    longitude: Number(point.longitude.toFixed(5)),
  };
  const distanceMetersValue = Math.round(distanceKm(center, coordinate) * 1_000);
  if (distanceMetersValue > radiusMeters) return null;
  const name = text(poi.name, 240);
  if (name == null) return null;
  const address = text(poi.address, 300);
  const exactName = name === query ? 3 : (name.includes(query) || query.includes(name) ? 2 : 0);
  const addressMatch = addressHint != null && address != null && address.includes(addressHint) ? 2 : 0;
  return { name, address, coordinate, distanceMeters: distanceMetersValue, score: exactName + addressMatch };
}

function evidenceFor(place, observedAt) {
  const coordinate = `${place.coordinate.latitude.toFixed(5)},${place.coordinate.longitude.toFixed(5)}`;
  return {
    sourceId: 'amap-poi', publisher: '高德地图', license: '高德开放平台服务',
    version: 'amap-web-service-v1', title: `高德地点：${place.name}`,
    snippet: `${place.address ?? place.name} 坐标：${coordinate}`,
    url: 'https://ditu.amap.com/', publishedAt: observedAt,
  };
}

export function parseAmapRegionIdentity(payload) {
  if (payload?.status !== '1' || !object(payload.regeocode)) return null;
  const names = [];
  const seen = new Set();
  const candidates = [];
  for (const value of Array.isArray(payload.regeocode.aois) ? payload.regeocode.aois : []) {
    if (!object(value)) continue;
    const name = scalarText(value.name);
    const type = scalarText(value.type, 160) ?? '';
    const distance = distanceMeters(value);
    if (name != null && distance <= 500 && relevantRegionType.test(`${name} ${type}`)) {
      candidates.push({ name, distance, priority: distance <= 100 ? 0 : 1 });
    }
  }
  for (const value of Array.isArray(payload.regeocode.pois) ? payload.regeocode.pois : []) {
    if (!object(value)) continue;
    const name = scalarText(value.name);
    const type = scalarText(value.type, 160) ?? '';
    const distance = distanceMeters(value);
    if (name != null && distance <= 300 && relevantRegionType.test(`${name} ${type}`)) {
      candidates.push({ name, distance, priority: 2 });
    }
  }
  candidates
    .sort((left, right) => left.priority - right.priority || left.distance - right.distance || left.name.localeCompare(right.name))
    .forEach((item) => addRegionName(names, seen, item.name));
  const address = object(payload.regeocode.addressComponent) ? payload.regeocode.addressComponent : {};
  addRegionName(names, seen, address.township);
  addRegionName(names, seen, address.district);
  addRegionName(names, seen, address.city);
  addRegionName(names, seen, address.province);
  const formatted = scalarText(payload.regeocode.formatted_address, 160);
  if (names.length === 0 && formatted != null) addRegionName(names, seen, formatted);
  if (names.length === 0) return null;
  return {
    displayName: names[0], searchNames: names.slice(0, 5),
    source: { sourceId: 'amap-regeocode', publisher: '高德地图', version: 'amap-web-service-v1' },
  };
}

async function resolveRegionIdentity({
  body,
  amapWebKey,
  fetcher,
  timeoutMs,
  now,
  cache,
}) {
  const instant = now();
  const key = regionIdentityCacheKey(body);
  const cached = cachedRegionIdentity(cache, key, instant);
  if (cached != null) return cached;

  const center = wgs84ToGcj02(body.region.latitude, body.region.longitude);
  const url = new URL('/v3/geocode/regeo', amapBaseUrl);
  url.searchParams.set('location', `${center.longitude.toFixed(6)},${center.latitude.toFixed(6)}`);
  url.searchParams.set('radius', String(Math.min(body.region.radiusMeters, 3_000)));
  url.searchParams.set('extensions', 'all');
  url.searchParams.set('roadlevel', '1');
  url.searchParams.set('key', amapWebKey);
  const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
  const payload = await upstream.json();
  const region = upstream.ok ? parseAmapRegionIdentity(payload) : null;
  const result = region == null ? { status: 'not_found' } : { status: 'resolved', region };
  cacheRegionIdentity(cache, key, result, instant);
  return result;
}

export async function resolvePlace({
  body,
  amapWebKey,
  fetcher = fetch,
  timeoutMs = 8_000,
  now = () => new Date(),
  regionIdentityCache = defaultRegionIdentityCache,
}) {
  if (!amapWebKey) return { status: 'failed' };
  try {
    if (body.query === regionIdentityQuery) {
      return await resolveRegionIdentity({
        body,
        amapWebKey,
        fetcher,
        timeoutMs,
        now,
        cache: regionIdentityCache,
      });
    }
    const center = wgs84ToGcj02(body.region.latitude, body.region.longitude);
    const url = new URL('/v3/place/text', amapBaseUrl);
    url.searchParams.set('keywords', body.query);
    url.searchParams.set('location', `${center.longitude.toFixed(6)},${center.latitude.toFixed(6)}`);
    url.searchParams.set('radius', String(Math.min(body.region.radiusMeters, 50_000)));
    url.searchParams.set('offset', '10');
    url.searchParams.set('page', '1');
    url.searchParams.set('extensions', 'all');
    url.searchParams.set('key', amapWebKey);
    const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const payload = await upstream.json();
    if (!upstream.ok || payload?.status !== '1' || !Array.isArray(payload.pois)) return { status: 'failed' };
    const centerWgs = { latitude: body.region.latitude, longitude: body.region.longitude };
    const places = payload.pois
      .map((poi) => parsePoi(poi, centerWgs, body.region.radiusMeters, body.query, body.addressHint))
      .filter(Boolean)
      .sort((first, second) => second.score - first.score || first.distanceMeters - second.distanceMeters || first.name.localeCompare(second.name));
    if (places.length === 0) return { status: 'not_found' };
    const [best, second] = places;
    if (second != null && best.score === second.score) return { status: 'ambiguous' };
    const observedAt = now().toISOString();
    return { status: 'resolved', place: best, evidence: evidenceFor(best, observedAt) };
  } catch {
    return { status: 'failed' };
  }
}
