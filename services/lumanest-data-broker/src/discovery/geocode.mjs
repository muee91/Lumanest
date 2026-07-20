import { gcj02ToWgs84, wgs84ToGcj02 } from './deterministic.mjs';

const amapBaseUrl = 'https://restapi.amap.com';
const requestKeys = new Set(['query', 'addressHint', 'region', 'locale']);
const regionKeys = new Set(['latitude', 'longitude', 'radiusMeters']);

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
  const distanceMeters = Math.round(distanceKm(center, coordinate) * 1_000);
  if (distanceMeters > radiusMeters) return null;
  const name = text(poi.name, 240);
  if (name == null) return null;
  const address = text(poi.address, 300);
  const exactName = name === query ? 3 : (name.includes(query) || query.includes(name) ? 2 : 0);
  const addressMatch = addressHint != null && address != null && address.includes(addressHint) ? 2 : 0;
  return {
    name,
    address,
    coordinate,
    distanceMeters,
    score: exactName + addressMatch,
  };
}

function evidenceFor(place, observedAt) {
  const coordinate = `${place.coordinate.latitude.toFixed(5)},${place.coordinate.longitude.toFixed(5)}`;
  return {
    sourceId: 'amap-poi',
    publisher: '高德地图',
    license: '高德开放平台服务',
    version: 'amap-web-service-v1',
    title: `高德地点：${place.name}`,
    snippet: `${place.address ?? place.name} 坐标：${coordinate}`,
    url: 'https://ditu.amap.com/',
    publishedAt: observedAt,
  };
}

export async function resolvePlace({ body, amapWebKey, fetcher = fetch, timeoutMs = 8_000, now = () => new Date() }) {
  if (!amapWebKey) return { status: 'failed' };
  const center = wgs84ToGcj02(body.region.latitude, body.region.longitude);
  const url = new URL('/v3/place/text', amapBaseUrl);
  url.searchParams.set('keywords', body.query);
  url.searchParams.set('location', `${center.longitude.toFixed(6)},${center.latitude.toFixed(6)}`);
  url.searchParams.set('radius', String(Math.min(body.region.radiusMeters, 50_000)));
  url.searchParams.set('offset', '10');
  url.searchParams.set('page', '1');
  url.searchParams.set('extensions', 'all');
  url.searchParams.set('key', amapWebKey);
  try {
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
