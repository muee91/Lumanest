const amapBaseUrl = 'https://restapi.amap.com';
const earthAxis = 6_378_245;
const eccentricitySquared = 0.00669342162296594323;

const waterTerms = /湖|水库|湿地|河流|江河|海湾|海滩|滩涂/;
const mountainTerms = /雪山|山峰|山脉|峡谷|垭口|山(?=\s|$)|峰(?=\s|$)|岭(?=\s|$)/;
const aridTerms = /沙漠|戈壁|沙地|雅丹/;
const settlementTerms = /古镇|古村|村落|村庄|民族村/;
const villagePlaceType = /村庄级地名/;
const semanticPoiType = /风景|地名|公园|自然/;
const containingAoiDistanceMeters = 100;
const immediateSettlementDistanceMeters = 100;
const namedSettlementDistanceMeters = 200;

function distanceMeters(value) {
  const raw = value?.distance;
  if (raw == null || raw === '') return Number.POSITIVE_INFINITY;
  const distance = Number(raw);
  return Number.isFinite(distance) && distance >= 0 ? distance : Number.POSITIVE_INFINITY;
}

function isLocalSettlement(value, { aoi = false } = {}) {
  const name = String(value?.name ?? '');
  const type = String(value?.type ?? '');
  const distance = distanceMeters(value);
  if (aoi) {
    return distance <= containingAoiDistanceMeters && settlementTerms.test(`${name} ${type}`);
  }
  if (villagePlaceType.test(type)) return distance <= immediateSettlementDistanceMeters;
  return distance <= namedSettlementDistanceMeters && settlementTerms.test(name);
}

function outsideMainland(latitude, longitude) {
  return longitude < 72.004 || longitude > 137.8347 ||
    latitude < 0.8293 || latitude > 55.8271;
}

function transformLatitude(x, y) {
  let result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y +
    0.2 * Math.sqrt(Math.abs(x));
  result += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(y * Math.PI) + 40 * Math.sin(y / 3 * Math.PI)) * 2 / 3;
  result += (160 * Math.sin(y / 12 * Math.PI) + 320 * Math.sin(y * Math.PI / 30)) * 2 / 3;
  return result;
}

function transformLongitude(x, y) {
  let result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y +
    0.1 * Math.sqrt(Math.abs(x));
  result += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(x * Math.PI) + 40 * Math.sin(x / 3 * Math.PI)) * 2 / 3;
  result += (150 * Math.sin(x / 12 * Math.PI) + 300 * Math.sin(x / 30 * Math.PI)) * 2 / 3;
  return result;
}

export function wgs84ToGcj02({ latitude, longitude }) {
  if (outsideMainland(latitude, longitude)) return { latitude, longitude };
  let latitudeDelta = transformLatitude(longitude - 105, latitude - 35);
  let longitudeDelta = transformLongitude(longitude - 105, latitude - 35);
  const latitudeRadians = latitude / 180 * Math.PI;
  let magic = Math.sin(latitudeRadians);
  magic = 1 - eccentricitySquared * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  latitudeDelta = latitudeDelta * 180 /
    (earthAxis * (1 - eccentricitySquared) / (magic * sqrtMagic) * Math.PI);
  longitudeDelta = longitudeDelta * 180 /
    (earthAxis / sqrtMagic * Math.cos(latitudeRadians) * Math.PI);
  return { latitude: latitude + latitudeDelta, longitude: longitude + longitudeDelta };
}

export function parseAmapSceneEvidence(body) {
  if (body?.status !== '1' || body.regeocode == null ||
      typeof body.regeocode !== 'object' || Array.isArray(body.regeocode)) return null;
  const semanticTexts = [];
  const aois = Array.isArray(body.regeocode.aois) ? body.regeocode.aois : [];
  let settlement = false;
  for (const value of aois) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) continue;
    semanticTexts.push(`${value.name ?? ''} ${value.type ?? ''}`);
    settlement ||= isLocalSettlement(value, { aoi: true });
  }
  const pois = Array.isArray(body.regeocode.pois) ? body.regeocode.pois : [];
  let poiCount = 0;
  for (const value of pois) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) continue;
    poiCount += 1;
    const type = String(value.type ?? '');
    if (semanticPoiType.test(type)) semanticTexts.push(`${value.name ?? ''} ${type}`);
    settlement ||= isLocalSettlement(value);
  }
  const semanticContext = semanticTexts.join(' ');
  const waterBody = waterTerms.test(semanticContext);
  const mountainous = mountainTerms.test(semanticContext);
  const aridLand = aridTerms.test(semanticContext);
  const address = body.regeocode.addressComponent;
  const hasCityCode = address != null && typeof address === 'object' &&
    !Array.isArray(address) && String(address.citycode ?? '').length > 0;
  return {
    urban: !waterBody && !mountainous && !aridLand && !settlement && hasCityCode && poiCount >= 10,
    waterBody,
    mountainous,
    aridLand,
    settlement,
  };
}

export async function fetchAmapSceneEvidence({
  coordinate,
  apiKey,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!apiKey) return { ok: false, error: 'not_configured' };
  const gcj02 = wgs84ToGcj02(coordinate);
  const url = new URL('/v3/geocode/regeo', amapBaseUrl);
  url.searchParams.set('location', `${gcj02.longitude},${gcj02.latitude}`);
  url.searchParams.set('radius', '3000');
  url.searchParams.set('extensions', 'all');
  url.searchParams.set('roadlevel', '1');
  url.searchParams.set('key', apiKey);
  try {
    const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = await upstream.json();
    const evidence = upstream.ok ? parseAmapSceneEvidence(body) : null;
    return evidence == null
      ? { ok: false, error: 'upstream_unavailable' }
      : { ok: true, evidence };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}
