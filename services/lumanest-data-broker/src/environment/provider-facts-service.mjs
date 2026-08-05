import { createHash } from 'node:crypto';

import { loadOfficialNoticeItems, officialNoticeSafetyKinds } from './official-notice-feed.mjs';
import {
  providerConfigured,
  providerConfigurationFingerprint,
  providerSourceDefaults,
  publicProviderSourceCatalog,
  validateProviderSources,
} from './provider-runtime-config.mjs';

const providerIds = Object.freeze([
  'sentinel1',
  'sentinel2',
  'cams',
  'aeronet',
  'officialNotices',
  'osm',
  'wikidata',
  'wikimediaCommons',
  'gbif',
  'inaturalist',
  'ebird',
  'firms',
  'copernicusMarine',
  'jplHorizons',
  'noaaSwpc',
]);
const providerIdSet = new Set(providerIds);
const defaultProviderIds = Object.freeze(providerIds.filter((id) => id !== 'ebird'));
const defaultRadiusKm = 25;
const maximumRadiusKm = 50;
const cacheLimit = 256;
const readyTtlMs = 30 * 60 * 1_000;
const referenceTtlMs = 12 * 60 * 60 * 1_000;
const unavailableTtlMs = 10 * 60 * 1_000;
const unconfiguredTtlMs = 30 * 60 * 1_000;

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function boundedText(value, maximum = 280) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return normalized.length > 0 ? [...normalized].slice(0, maximum).join('') : null;
}

function boundedUrl(value) {
  if (typeof value !== 'string' || value.length > 2_048) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url.toString() : null;
  } catch {
    return null;
  }
}

function configuredUrl(value) {
  const url = boundedUrl(value?.trim?.() ?? '');
  return url == null ? '' : url.replace(/\/$/, '');
}

function configuredToken(value, maximum = 512) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= maximum
    ? value.trim()
    : '';
}

function parseCsvList(value) {
  if (typeof value !== 'string' || value.trim().length === 0) return [];
  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

function pointBox(latitude, longitude, radiusKm) {
  const latDelta = radiusKm / 111.32;
  const cos = Math.max(0.1, Math.cos(latitude * Math.PI / 180));
  const lonDelta = radiusKm / (111.32 * cos);
  return {
    west: Math.max(-180, longitude - lonDelta),
    south: Math.max(-90, latitude - latDelta),
    east: Math.min(180, longitude + lonDelta),
    north: Math.min(90, latitude + latDelta),
  };
}

function iso(value) {
  const date = value instanceof Date ? value : new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function dateOnly(date) {
  return date.toISOString().slice(0, 10);
}

function stableId(...parts) {
  return `signal_${createHash('sha256').update(parts.join('|')).digest('hex').slice(0, 24)}`;
}

function source({ id, title, publisher, url, license, version }) {
  return {
    id,
    title,
    publisher,
    url,
    license,
    version,
  };
}

function boundedAttributes(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null;
  const entries = Object.entries(value).filter(([key, item]) =>
    /^[a-z][a-zA-Z0-9]{0,31}$/.test(key) && Number.isInteger(item) && item >= 0 && item <= 1_000,
  ).slice(0, 16);
  return entries.length > 0 ? Object.fromEntries(entries) : null;
}

function signal({ providerId, kind, category, title, summary, verification, observedAt, expiresAt, sourceUrl, attributes = null }) {
  const safeTitle = boundedText(title, 120);
  const safeSummary = boundedText(summary, 360);
  const safeObservedAt = iso(observedAt);
  const safeExpiresAt = iso(expiresAt);
  const safeSourceUrl = boundedUrl(sourceUrl);
  const safeAttributes = boundedAttributes(attributes);
  if (!safeTitle || !safeSummary || !safeObservedAt || !safeExpiresAt || !safeSourceUrl ||
      Date.parse(safeExpiresAt) <= Date.parse(safeObservedAt)) return null;
  return {
    id: stableId(providerId, kind, safeObservedAt, safeTitle),
    kind,
    category,
    title: safeTitle,
    summary: safeSummary,
    verification,
    observedAt: safeObservedAt,
    expiresAt: safeExpiresAt,
    sourceUrl: safeSourceUrl,
    ...(safeAttributes == null ? {} : { attributes: safeAttributes }),
  };
}

function providerResult({ id, category, status, now, ttlMs, sourceInfo = null, signals = [], message = null }) {
  const observedAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + ttlMs).toISOString();
  return {
    id,
    category,
    status,
    observedAt,
    expiresAt,
    source: sourceInfo,
    signals: signals.filter(Boolean).slice(0, 8),
    message: boundedText(message, 160),
  };
}

function unavailable(id, category, now, message = '上游暂不可用') {
  return providerResult({ id, category, status: 'unavailable', now, ttlMs: unavailableTtlMs, message });
}

function unconfigured(id, category, now, message = '需要服务端配置') {
  return providerResult({ id, category, status: 'unconfigured', now, ttlMs: unconfiguredTtlMs, message });
}

function noData(id, category, now, sourceInfo, message = '当前范围没有可用数据') {
  return providerResult({ id, category, status: 'noData', now, ttlMs: readyTtlMs, sourceInfo, message });
}

function cacheKey(query, configurationFingerprint = '') {
  return [
    query.latitude.toFixed(2), query.longitude.toFixed(2), query.radiusKm,
    query.locale, query.providerIds.join(','), configurationFingerprint,
  ].join(':');
}

function readCache(cache, key, now) {
  const item = cache.get(key);
  if (item == null) return null;
  if (item.expiresAt <= now.getTime()) {
    cache.delete(key);
    return null;
  }
  cache.delete(key);
  cache.set(key, item);
  return structuredClone(item.value);
}

function writeCache(cache, key, value) {
  cache.delete(key);
  cache.set(key, { value: structuredClone(value), expiresAt: Date.parse(value.expiresAt) });
  while (cache.size > cacheLimit) cache.delete(cache.keys().next().value);
}

async function fetchJson(fetcher, url, { timeoutMs, method = 'GET', headers = {}, body } = {}) {
  const response = await fetcher(url, {
    method,
    headers,
    body,
    redirect: 'error',
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`http_${response.status}`);
  return response.json();
}

async function fetchText(fetcher, url, { timeoutMs, headers = {} } = {}) {
  const response = await fetcher(url, {
    headers,
    redirect: 'error',
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`http_${response.status}`);
  return response.text();
}

export function validProviderFactsQuery(searchParams, now = new Date()) {
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  const radiusKm = Number(searchParams.get('radiusKm') ?? defaultRadiusKm);
  const locale = searchParams.get('locale') ?? 'zh-CN';
  const atRaw = searchParams.get('at');
  const includeRaw = searchParams.get('include');
  if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180) ||
      !finite(radiusKm, 1, maximumRadiusKm) ||
      !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(locale)) return null;
  const observedAt = atRaw == null ? now : new Date(atRaw);
  if (!Number.isFinite(observedAt.getTime()) || Math.abs(observedAt.getTime() - now.getTime()) > 7 * 24 * 60 * 60 * 1_000) {
    return null;
  }
  const selected = includeRaw == null || includeRaw.trim().length === 0
    ? [...defaultProviderIds]
    : [...new Set(includeRaw.split(',').map((item) => item.trim()).filter(Boolean))];
  if (selected.length === 0 || selected.length > providerIds.length || selected.some((id) => !providerIdSet.has(id))) {
    return null;
  }
  return {
    latitude,
    longitude,
    radiusKm: Math.round(radiusKm),
    locale,
    observedAt: observedAt.toISOString(),
    providerIds: selected,
  };
}

async function sentinelProvider({ id, collection, query, fetcher, timeoutMs, now, stacBaseUrl }) {
  const category = 'surface';
  const box = pointBox(query.latitude, query.longitude, query.radiusKm);
  const start = new Date(now.getTime() - 21 * 24 * 60 * 60 * 1_000);
  const payload = {
    collections: [collection],
    bbox: [box.west, box.south, box.east, box.north],
    datetime: `${start.toISOString()}/${now.toISOString()}`,
    limit: 5,
    sortby: [{ field: 'properties.datetime', direction: 'desc' }],
  };
  if (id === 'sentinel2') payload.query = { 'eo:cloud_cover': { lte: 70 } };
  const sourceInfo = source({
    id: `copernicus-${id}`,
    title: id === 'sentinel2' ? 'Sentinel-2 Level-2A catalogue' : 'Sentinel-1 GRD catalogue',
    publisher: 'Copernicus Data Space Ecosystem',
    url: `${stacBaseUrl}/collections/${collection}`,
    license: 'Copernicus data terms',
    version: 'STAC 1.1',
  });
  try {
    const body = await fetchJson(fetcher, `${stacBaseUrl}/search`, {
      timeoutMs,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'User-Agent': 'LumaNest/1.0' },
      body: JSON.stringify(payload),
    });
    const features = Array.isArray(body?.features) ? body.features : [];
    const feature = features.find((item) => iso(item?.properties?.datetime ?? item?.properties?.start_datetime));
    if (feature == null) return noData(id, category, now, sourceInfo);
    const capturedAt = iso(feature.properties.datetime ?? feature.properties.start_datetime);
    const cloud = Number(feature.properties?.['eo:cloud_cover']);
    const selfLink = Array.isArray(feature.links)
      ? feature.links.find((item) => item?.rel === 'self' && boundedUrl(item?.href))?.href
      : null;
    const summary = id === 'sentinel2'
      ? `最近目录影像采集于 ${capturedAt.slice(0, 10)}${Number.isFinite(cloud) ? `，云量约 ${Math.round(cloud)}%` : ''}。当前接入目录元数据；雪线、植被和水体指数需由 Raster Worker 计算后才能形成结论。`
      : `最近雷达产品采集于 ${capturedAt.slice(0, 10)}。雷达可为多云地区的水体和明显地表变化提供后续分析入口，当前不直接生成现场结论。`;
    return providerResult({
      id,
      category,
      status: 'ready',
      now,
      ttlMs: referenceTtlMs,
      sourceInfo,
      signals: [signal({
        providerId: id,
        kind: id === 'sentinel2' ? 'opticalAcquisition' : 'radarAcquisition',
        category,
        title: id === 'sentinel2' ? '近期光学卫星观测' : '近期雷达卫星观测',
        summary,
        verification: 'observed',
        observedAt: capturedAt,
        expiresAt: new Date(Date.parse(capturedAt) + 30 * 24 * 60 * 60 * 1_000),
        sourceUrl: selfLink ?? sourceInfo.url,
      })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function normalizedGatewayProvider({
  id,
  category,
  url,
  token = '',
  query,
  fetcher,
  timeoutMs,
  now,
  sourceInfo,
  allowedKinds = null,
  allowedVerifications = null,
}) {
  if (!url) return unconfigured(id, category, now);
  try {
    const endpoint = new URL(url);
    endpoint.searchParams.set('lat', String(query.latitude));
    endpoint.searchParams.set('lon', String(query.longitude));
    endpoint.searchParams.set('radiusKm', String(query.radiusKm));
    endpoint.searchParams.set('at', query.observedAt);
    endpoint.searchParams.set('locale', query.locale);
    const headers = { 'User-Agent': 'LumaNest/1.0' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const body = await fetchJson(fetcher, endpoint, { timeoutMs, headers });
    const items = Array.isArray(body?.signals) ? body.signals : [];
    const normalized = items.slice(0, 8).map((item) => {
      const kind = boundedText(item?.kind, 64) ?? 'providerSignal';
      const verification = ['authoritative', 'observed', 'model', 'reference', 'candidate'].includes(item?.verification)
        ? item.verification : 'model';
      if (allowedKinds != null && !allowedKinds.has(kind)) return null;
      if (allowedVerifications != null && !allowedVerifications.has(verification)) return null;
      return signal({
        providerId: id,
        kind,
        category,
        title: item?.title,
        summary: item?.summary,
        verification,
        observedAt: item?.observedAt ?? body?.observedAt ?? now,
        expiresAt: item?.expiresAt ?? body?.expiresAt ?? new Date(now.getTime() + readyTtlMs),
        sourceUrl: item?.sourceUrl ?? body?.sourceUrl ?? sourceInfo.url,
      });
    }).filter(Boolean);
    return normalized.length === 0
      ? noData(id, category, now, sourceInfo)
      : providerResult({ id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo, signals: normalized });
  } catch {
    return unavailable(id, category, now);
  }
}

async function officialNoticesProvider({ query, fetcher, timeoutMs, now, configuration }) {
  const id = 'officialNotices';
  const category = 'operations';
  if (configuration.officialNoticeGatewayUrl) {
    return normalizedGatewayProvider({
      id,
      category,
      url: configuration.officialNoticeGatewayUrl,
      token: configuration.officialNoticeGatewayToken,
      query,
      fetcher,
      timeoutMs,
      now,
      sourceInfo: source({
        id: 'official-notice-gateway',
        title: 'Reviewed official notices',
        publisher: 'Configured government and venue sources',
        url: configuration.officialNoticeGatewayUrl,
        license: 'Source-specific',
        version: 'normalized gateway v1',
      }),
      allowedKinds: new Set(['closure', 'roadClosure', 'fireRestriction', 'regulation', 'reopening', 'eventChange']),
      allowedVerifications: new Set(['authoritative', 'reference']),
    });
  }
  const enabledSources = configuration.officialNoticeSources.filter((item) => item.enabled);
  if (enabledSources.length === 0) return unconfigured(id, category, now, '需要在控制台配置审核公告源');
  const sourceInfo = source({
    id: 'official-notice-registry',
    title: 'Reviewed official notice feeds',
    publisher: 'Configured government and venue sources',
    url: enabledSources[0].homepageUrl,
    license: 'Source-specific',
    version: 'feed registry v1',
  });
  try {
    const loaded = await loadOfficialNoticeItems({
      sources: enabledSources,
      query,
      fetcher,
      timeoutMs,
      now,
    });
    if (loaded.items.length === 0) {
      return loaded.checkedSources > 0 && loaded.unavailableSources === loaded.checkedSources
        ? unavailable(id, category, now)
        : noData(id, category, now, sourceInfo, '当前范围没有仍有效的官方公告');
    }
    return providerResult({
      id,
      category,
      status: 'ready',
      now,
      ttlMs: readyTtlMs,
      sourceInfo,
      signals: loaded.items.map((item) => signal({
        providerId: id,
        kind: item.kind,
        category,
        title: item.title,
        summary: item.summary,
        verification: item.safetyEligible || (item.authoritative && !officialNoticeSafetyKinds.has(item.kind))
          ? 'authoritative' : 'reference',
        observedAt: item.observedAt,
        expiresAt: item.expiresAt,
        sourceUrl: item.sourceUrl,
      })),
    });
  } catch {
    return unavailable(id, category, now);
  }
}

function finiteMetadata(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

async function sentinelRasterSignals({ query, fetcher, timeoutMs, now, url, token }) {
  if (!url) return [];
  try {
    const endpoint = new URL(url);
    endpoint.searchParams.set('lat', String(query.latitude));
    endpoint.searchParams.set('lon', String(query.longitude));
    endpoint.searchParams.set('radiusKm', String(query.radiusKm));
    endpoint.searchParams.set('at', query.observedAt);
    const headers = { 'User-Agent': 'LumaNest/1.0 SentinelRasterClient' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const body = await fetchJson(fetcher, endpoint, { timeoutMs, headers });
    const observations = Array.isArray(body?.observations) ? body.observations : [];
    const metrics = {
      ndvi: ['vegetationIndexChange', '植被指数变化', 'NDVI'],
      ndsi: ['snowIndexChange', '积雪指数变化', 'NDSI'],
      ndwi: ['waterIndexChange', '水体指数变化', 'NDWI'],
      surfaceChange: ['surfaceChange', '地表变化线索', '变化指数'],
    };
    return observations.slice(0, 4).flatMap((item) => {
      const definition = metrics[item?.metric];
      const observedAt = iso(item?.observedAt);
      const comparisonStart = iso(item?.comparisonStart);
      const comparisonEnd = iso(item?.comparisonEnd);
      const sourceUrl = boundedUrl(item?.sourceUrl);
      const delta = Number(item?.delta);
      const cloudCoverage = Number(item?.cloudCoverage);
      const resolution = Number(item?.spatialResolutionMeters);
      const confidence = ['limited', 'medium', 'high'].includes(item?.confidence)
        ? item.confidence : null;
      if (definition == null || !observedAt || !comparisonStart || !comparisonEnd || !sourceUrl ||
          Date.parse(comparisonEnd) <= Date.parse(comparisonStart) ||
          !finiteMetadata(delta, -2, 2) || !finiteMetadata(cloudCoverage, 0, 100) ||
          !finiteMetadata(resolution, 1, 1_000) || confidence == null) return [];
      const sign = delta > 0 ? '+' : '';
      const summary = `${comparisonStart.slice(0, 10)} 至 ${comparisonEnd.slice(0, 10)} 的 ${definition[2]} 差值为 ${sign}${delta.toFixed(3)}，云量约 ${Math.round(cloudCoverage)}%，空间分辨率 ${Math.round(resolution)} 米，置信等级 ${confidence}。这是遥感变化线索，不代表现场已进入最佳状态。`;
      return [signal({
        providerId: 'sentinel2',
        kind: definition[0],
        category: 'surface',
        title: definition[1],
        summary,
        verification: confidence === 'high' ? 'observed' : 'model',
        observedAt,
        expiresAt: item?.expiresAt ?? new Date(now.getTime() + 24 * 60 * 60 * 1_000),
        sourceUrl,
      })].filter(Boolean);
    });
  } catch {
    return [];
  }
}

function parseAeronet(text) {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const headerIndex = lines.findIndex((line) => line.includes('AERONET_Site') && line.includes('Longitude'));
  if (headerIndex < 0) return null;
  const headers = lines[headerIndex].split(',').map((item) => item.trim());
  const rows = lines.slice(headerIndex + 1).map((line) => line.split(',')).filter((row) => row.length === headers.length);
  if (rows.length === 0) return null;
  const row = rows.at(-1);
  const value = (name) => row[headers.indexOf(name)]?.trim();
  const aodKey = headers.find((name) => name === 'AOD_500nm' || name === 'AOD_440nm');
  const aod = Number(aodKey == null ? NaN : value(aodKey));
  const date = value('Date(dd:mm:yyyy)');
  const time = value('Time(hh:mm:ss)');
  const parts = date?.split(':').map(Number);
  const observedAt = parts?.length === 3
    ? new Date(Date.UTC(parts[2], parts[1] - 1, parts[0], ...(time?.split(':').map(Number) ?? [0, 0, 0])))
    : null;
  return Number.isFinite(aod) && observedAt != null && Number.isFinite(observedAt.getTime())
    ? { site: value('AERONET_Site') ?? 'AERONET station', aod, wavelength: aodKey, observedAt }
    : null;
}

async function aeronetProvider({ query, fetcher, timeoutMs, now, baseUrl }) {
  const id = 'aeronet';
  const category = 'atmosphere';
  const sourceInfo = source({
    id: 'nasa-aeronet', title: 'AERONET Version 3', publisher: 'NASA GSFC',
    url: `${baseUrl}/new_web/webtool_inv_v3.html`, license: 'NASA data policy', version: 'V3',
  });
  const box = pointBox(query.latitude, query.longitude, Math.min(query.radiusKm, 50));
  const start = new Date(now.getTime() - 2 * 24 * 60 * 60 * 1_000);
  const url = new URL('/cgi-bin/print_web_data_v3', baseUrl);
  const params = {
    year: start.getUTCFullYear(), month: start.getUTCMonth() + 1, day: start.getUTCDate(), hour: 0,
    year2: now.getUTCFullYear(), month2: now.getUTCMonth() + 1, day2: now.getUTCDate(), hour2: 23,
    AOD10: 1, AVG: 10, if_no_html: 1,
    lat1: box.south, lat2: box.north, lon1: box.west, lon2: box.east,
  };
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  try {
    const parsed = parseAeronet(await fetchText(fetcher, url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } }));
    if (parsed == null) return noData(id, category, now, sourceInfo, '附近没有近期可用的 AERONET 站点实测');
    return providerResult({
      id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo,
      signals: [signal({
        providerId: id, kind: 'aerosolOpticalDepth', category, title: '地面气溶胶实测',
        summary: `${parsed.site} 最近 ${parsed.wavelength} 气溶胶光学厚度为 ${parsed.aod.toFixed(3)}。站点观测只代表站点附近，不直接等同于当前位置通透度。`,
        verification: 'observed', observedAt: parsed.observedAt,
        expiresAt: new Date(parsed.observedAt.getTime() + 12 * 60 * 60 * 1_000), sourceUrl: sourceInfo.url,
      })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function osmProvider({ query, fetcher, timeoutMs, now, overpassUrl }) {
  const id = 'osm';
  const category = 'outdoor';
  const sourceInfo = source({
    id: 'openstreetmap-overpass', title: 'OpenStreetMap Overpass API', publisher: 'OpenStreetMap contributors',
    url: 'https://www.openstreetmap.org/copyright', license: 'ODbL-1.0', version: 'Overpass QL',
  });
  const radius = Math.min(50_000, query.radiusKm * 1_000);
  const q = `[out:json][timeout:12];(nwr(around:${radius},${query.latitude},${query.longitude})["tourism"="viewpoint"];nwr(around:${radius},${query.latitude},${query.longitude})["highway"="path"];nwr(around:${radius},${query.latitude},${query.longitude})["highway"="rest_area"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="shelter"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="drinking_water"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="parking"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="fuel"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="toilets"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"~"^(restaurant|cafe|fast_food)$"];nwr(around:${radius},${query.latitude},${query.longitude})["historic"];);out tags center qt 160;`;
  try {
    const body = await fetchJson(fetcher, overpassUrl, {
      timeoutMs,
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'User-Agent': 'LumaNest/1.0' },
      body: new URLSearchParams({ data: q }).toString(),
    });
    const elements = Array.isArray(body?.elements) ? body.elements : [];
    if (elements.length === 0) return noData(id, category, now, sourceInfo);
    const counts = {
      viewpoint: 0, path: 0, shelter: 0, water: 0, historic: 0,
      parking: 0, fuel: 0, toilets: 0, food: 0, restArea: 0,
    };
    for (const item of elements) {
      const tags = item?.tags ?? {};
      if (tags.tourism === 'viewpoint') counts.viewpoint += 1;
      if (tags.highway === 'path') counts.path += 1;
      if (tags.highway === 'rest_area') counts.restArea += 1;
      if (tags.amenity === 'shelter') counts.shelter += 1;
      if (tags.amenity === 'drinking_water') counts.water += 1;
      if (tags.amenity === 'parking') counts.parking += 1;
      if (tags.amenity === 'fuel') counts.fuel += 1;
      if (tags.amenity === 'toilets') counts.toilets += 1;
      if (['restaurant', 'cafe', 'fast_food'].includes(tags.amenity)) counts.food += 1;
      if (tags.historic != null) counts.historic += 1;
    }
    const summary = `公开地图标注：观景点 ${counts.viewpoint}、步道 ${counts.path}、停车 ${counts.parking}、加油 ${counts.fuel}、餐饮 ${counts.food}、饮水 ${counts.water}、厕所 ${counts.toilets}、庇护设施 ${counts.shelter}、休息区 ${counts.restArea}、历史对象 ${counts.historic}。标注不代表当前开放、营业或现场安全。`;
    return providerResult({
      id, category, status: 'ready', now, ttlMs: referenceTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'outdoorMapInventory', category, title: '户外地图语义', summary,
        verification: 'reference', observedAt: now, expiresAt: new Date(now.getTime() + referenceTtlMs),
        sourceUrl: sourceInfo.url, attributes: counts })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function wikidataProvider({ query, fetcher, timeoutMs, now, endpoint }) {
  const id = 'wikidata';
  const category = 'culture';
  const sourceInfo = source({
    id: 'wikidata-query-service', title: 'Wikidata Query Service', publisher: 'Wikimedia Foundation and contributors',
    url: 'https://www.wikidata.org/wiki/Wikidata:Data_access', license: 'CC0-1.0', version: 'SPARQL 1.1',
  });
  const language = query.locale.toLowerCase().startsWith('zh') ? 'zh' : 'en';
  const sparql = `SELECT ?item ?itemLabel ?instanceLabel WHERE { SERVICE wikibase:around { ?item wdt:P625 ?location . bd:serviceParam wikibase:center "Point(${query.longitude} ${query.latitude})"^^geo:wktLiteral . bd:serviceParam wikibase:radius "${Math.min(query.radiusKm, 50)}" . } OPTIONAL { ?item wdt:P31 ?instance . } SERVICE wikibase:label { bd:serviceParam wikibase:language "${language},en". } } LIMIT 12`;
  const url = new URL(endpoint);
  url.searchParams.set('query', sparql);
  url.searchParams.set('format', 'json');
  try {
    const body = await fetchJson(fetcher, url, { timeoutMs, headers: { Accept: 'application/sparql-results+json', 'User-Agent': 'LumaNest/1.0' } });
    const rows = Array.isArray(body?.results?.bindings) ? body.results.bindings : [];
    const labels = [...new Set(rows.map((row) => boundedText(row?.itemLabel?.value, 80)).filter(Boolean))];
    if (labels.length === 0) return noData(id, category, now, sourceInfo);
    return providerResult({
      id, category, status: 'ready', now, ttlMs: referenceTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'culturalEntities', category, title: '附近文化实体',
        summary: `知识图谱检索到 ${labels.length} 个附近实体，包括 ${labels.slice(0, 4).join('、')}。这些条目用于实体消歧和检索种子，不代替官方开放信息。`,
        verification: 'reference', observedAt: now, expiresAt: new Date(now.getTime() + referenceTtlMs), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function commonsProvider({ query, fetcher, timeoutMs, now, apiUrl }) {
  const id = 'wikimediaCommons';
  const category = 'culture';
  const sourceInfo = source({
    id: 'wikimedia-commons-geosearch', title: 'Wikimedia Commons GeoSearch', publisher: 'Wikimedia contributors',
    url: 'https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia',
    license: 'Per-file license', version: 'MediaWiki Action API',
  });
  const url = new URL(apiUrl);
  const params = {
    action: 'query', generator: 'geosearch', ggsprimary: 'all', ggsnamespace: 6,
    ggsradius: Math.min(10_000, query.radiusKm * 1_000), ggscoord: `${query.latitude}|${query.longitude}`,
    prop: 'info', inprop: 'url', ggslimit: 25, format: 'json', formatversion: 2,
  };
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  try {
    const body = await fetchJson(fetcher, url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } });
    const pages = Array.isArray(body?.query?.pages) ? body.query.pages : [];
    const titles = pages.map((item) => boundedText(item?.title?.replace(/^File:/, ''), 80)).filter(Boolean);
    if (titles.length === 0) return noData(id, category, now, sourceInfo);
    return providerResult({
      id, category, status: 'ready', now, ttlMs: referenceTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'licensedMediaIndex', category, title: '附近开放媒体资料',
        summary: `附近检索到 ${titles.length} 个 Commons 文件条目。图片必须逐项核验作者、许可和署名要求，当前不会自动下载或用于地点真实性判断。`,
        verification: 'reference', observedAt: now, expiresAt: new Date(now.getTime() + referenceTtlMs), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function gbifProvider({ query, fetcher, timeoutMs, now, baseUrl }) {
  const id = 'gbif';
  const category = 'wildlife';
  const sourceInfo = source({
    id: 'gbif-occurrence-api', title: 'GBIF Occurrence API', publisher: 'GBIF data publishers',
    url: 'https://techdocs.gbif.org/en/openapi/v1/occurrence', license: 'Record-specific open licenses', version: 'v1',
  });
  const box = pointBox(query.latitude, query.longitude, query.radiusKm);
  const geometry = `POLYGON((${box.west} ${box.south},${box.east} ${box.south},${box.east} ${box.north},${box.west} ${box.north},${box.west} ${box.south}))`;
  const url = new URL('/v1/occurrence/search', baseUrl);
  url.searchParams.set('geometry', geometry);
  url.searchParams.set('hasCoordinate', 'true');
  url.searchParams.set('occurrenceStatus', 'PRESENT');
  url.searchParams.set('limit', '0');
  try {
    const body = await fetchJson(fetcher, url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } });
    const count = Number(body?.count);
    if (!Number.isInteger(count) || count <= 0) return noData(id, category, now, sourceInfo);
    return providerResult({
      id, category, status: 'ready', now, ttlMs: referenceTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'historicalOccurrenceInventory', category, title: '历史生态记录',
        summary: `当前粗略范围内有 ${count.toLocaleString('en-US')} 条公开物种观测记录。记录可能跨越多年，不表示动物当前出现；敏感物种坐标不会在前端展示。`,
        verification: 'reference', observedAt: now, expiresAt: new Date(now.getTime() + referenceTtlMs), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}


async function inaturalistProvider({ query, fetcher, timeoutMs, now, baseUrl }) {
  const id = 'inaturalist';
  const category = 'wildlife';
  const sourceInfo = source({
    id: 'inaturalist-observations-api',
    title: 'iNaturalist Observations API',
    publisher: 'iNaturalist community',
    url: 'https://www.inaturalist.org/pages/api+reference',
    license: 'Observation-specific licences; aggregate metadata only',
    version: 'v1',
  });
  const box = pointBox(query.latitude, query.longitude, Math.min(query.radiusKm, 50));
  const start = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1_000);
  const url = new URL('/v1/observations', baseUrl);
  const parameters = {
    taxon_id: 3,
    quality_grade: 'research',
    captive: 'false',
    geo: 'true',
    d1: dateOnly(start),
    nelat: box.north.toFixed(5),
    nelng: box.east.toFixed(5),
    swlat: box.south.toFixed(5),
    swlng: box.west.toFixed(5),
    per_page: 30,
    order_by: 'observed_on',
    order: 'desc',
  };
  Object.entries(parameters).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  try {
    const body = await fetchJson(fetcher, url, {
      timeoutMs,
      headers: { 'User-Agent': 'LumaNest/1.0 ecology-context' },
    });
    const total = Number(body?.total_results);
    const observations = Array.isArray(body?.results) ? body.results : [];
    if (!Number.isInteger(total) || total <= 0 || observations.length === 0) {
      return noData(id, category, now, sourceInfo, '近九十日没有可用的研究级公开鸟类观察摘要');
    }
    const taxa = new Set(observations.map((item) => Number(item?.taxon?.id)).filter(Number.isInteger));
    const latest = observations
      .map((item) => iso(item?.time_observed_at ?? item?.observed_on))
      .filter(Boolean)
      .sort()
      .at(-1) ?? now.toISOString();
    return providerResult({
      id,
      category,
      status: 'ready',
      now,
      ttlMs: readyTtlMs,
      sourceInfo,
      signals: [signal({
        providerId: id,
        kind: 'recentCommunityBirdSummary',
        category,
        title: '近期公开社区观察',
        summary: `近九十日当前粗略范围有 ${total.toLocaleString('en-US')} 条研究级公开鸟类观察；最近返回样本涉及 ${taxa.size} 个分类单元。社区记录不代表动物当前仍在现场，也不用于推算出现概率或生成精确物种导航。`,
        verification: 'candidate',
        observedAt: latest,
        expiresAt: new Date(now.getTime() + 6 * 60 * 60 * 1_000),
        sourceUrl: sourceInfo.url,
        attributes: {
          observationCount: Math.min(total, 1_000),
          sampledTaxaCount: Math.min(taxa.size, 1_000),
          lookbackDays: 90,
        },
      })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function ebirdProvider({ query, fetcher, timeoutMs, now, baseUrl, token }) {
  const id = 'ebird';
  const category = 'wildlife';
  if (!token) return unconfigured(id, category, now, '需要 eBird API Token');
  const sourceInfo = source({
    id: 'ebird-api-v2', title: 'eBird API 2.0', publisher: 'Cornell Lab of Ornithology',
    url: 'https://documenter.getpostman.com/view/664302/S1ENwy59', license: 'eBird data terms', version: '2.0',
  });
  const url = new URL('/v2/data/obs/geo/recent', baseUrl);
  url.searchParams.set('lat', String(query.latitude));
  url.searchParams.set('lng', String(query.longitude));
  url.searchParams.set('dist', String(Math.min(50, query.radiusKm)));
  url.searchParams.set('back', '7');
  url.searchParams.set('maxResults', '100');
  try {
    const body = await fetchJson(fetcher, url, { timeoutMs, headers: { 'X-eBirdApiToken': token, 'User-Agent': 'LumaNest/1.0' } });
    const observations = Array.isArray(body) ? body : [];
    const species = new Set(observations.map((item) => boundedText(item?.sciName, 120)).filter(Boolean));
    if (species.size === 0) return noData(id, category, now, sourceInfo, '近七日没有可用的公开鸟类摘要');
    const latest = observations.map((item) => iso(item?.obsDt)).filter(Boolean).sort().at(-1) ?? now.toISOString();
    return providerResult({
      id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'recentBirdSummary', category, title: '近期鸟类投稿摘要',
        summary: `近七日公开摘要包含 ${species.size} 种鸟类。投稿记录不保证现场可见，且不会展示敏感物种精确位置。`,
        verification: 'observed', observedAt: latest, expiresAt: new Date(now.getTime() + 12 * 60 * 60 * 1_000), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return [];
  const headers = lines[0].split(',').map((item) => item.trim());
  return lines.slice(1).map((line) => {
    const fields = line.split(',');
    return Object.fromEntries(headers.map((header, index) => [header, fields[index]?.trim()]));
  });
}

async function firmsProvider({ query, fetcher, timeoutMs, now, baseUrl, mapKey }) {
  const id = 'firms';
  const category = 'fire';
  if (!mapKey) return unconfigured(id, category, now, '需要 NASA FIRMS MAP_KEY');
  const sourceInfo = source({
    id: 'nasa-firms-area-api', title: 'NASA FIRMS Area API', publisher: 'NASA LANCE FIRMS',
    url: 'https://firms.modaps.eosdis.nasa.gov/api/area/', license: 'NASA Earthdata policy', version: 'Area API v4',
  });
  const box = pointBox(query.latitude, query.longitude, query.radiusKm);
  const area = `${box.west.toFixed(4)},${box.south.toFixed(4)},${box.east.toFixed(4)},${box.north.toFixed(4)}`;
  const url = `${baseUrl}/api/area/csv/${encodeURIComponent(mapKey)}/VIIRS_NOAA20_NRT/${area}/1`;
  try {
    const rows = parseCsv(await fetchText(fetcher, url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } }));
    if (rows.length === 0) return noData(id, category, now, sourceInfo, '近一日没有检测到卫星热异常');
    const maxFrp = rows.reduce((max, row) => Math.max(max, Number(row.frp) || 0), 0);
    return providerResult({
      id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'thermalAnomaly', category, title: '卫星热异常线索',
        summary: `近一日当前粗略范围内检测到 ${rows.length} 个 VIIRS 热异常点${maxFrp > 0 ? `，最高辐射功率约 ${maxFrp.toFixed(1)} MW` : ''}。热异常不等同于山火，需继续核对林草、消防或地方公告。`,
        verification: 'candidate', observedAt: now, expiresAt: new Date(now.getTime() + 3 * 60 * 60 * 1_000), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function horizonsProvider({ query, fetcher, timeoutMs, now, baseUrl }) {
  const id = 'jplHorizons';
  const category = 'astronomy';
  const sourceInfo = source({
    id: 'jpl-horizons-api', title: 'JPL Horizons API', publisher: 'NASA Jet Propulsion Laboratory',
    url: 'https://ssd-api.jpl.nasa.gov/doc/horizons.html', license: 'NASA data policy', version: 'API 1.3',
  });
  const stop = new Date(now.getTime() + 6 * 60 * 60 * 1_000);
  const url = new URL('/api/horizons.api', baseUrl);
  const parameters = {
    format: 'json', COMMAND: "'301'", OBJ_DATA: "'NO'", MAKE_EPHEM: "'YES'",
    EPHEM_TYPE: "'OBSERVER'", CENTER: "'coord@399'", COORD_TYPE: "'GEODETIC'",
    SITE_COORD: `'${query.longitude},${query.latitude},0'`, START_TIME: `'${now.toISOString()}'`,
    STOP_TIME: `'${stop.toISOString()}'`, STEP_SIZE: "'60 m'", QUANTITIES: "'4,9,20'", CSV_FORMAT: "'YES'",
  };
  Object.entries(parameters).forEach(([key, value]) => url.searchParams.set(key, value));
  try {
    const body = await fetchJson(fetcher, url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } });
    if (typeof body?.result !== 'string' || !body.result.includes('$$SOE') || !body.result.includes('$$EOE')) {
      return noData(id, category, now, sourceInfo);
    }
    return providerResult({
      id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'observerEphemeris', category, title: '外部天体星历校验',
        summary: 'JPL Horizons 已返回当前位置未来六小时的月球观测星历。主拍摄判断仍使用本地天文链；该源用于长尾天体和结果校验。',
        verification: 'authoritative', observedAt: now, expiresAt: stop, sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

async function swpcProvider({ fetcher, timeoutMs, now, baseUrl }) {
  const id = 'noaaSwpc';
  const category = 'spaceWeather';
  const sourceInfo = source({
    id: 'noaa-swpc-kp', title: 'NOAA Planetary K-index', publisher: 'NOAA Space Weather Prediction Center',
    url: `${baseUrl}/products/noaa-planetary-k-index.json`, license: 'US Government public data', version: 'JSON product',
  });
  try {
    const body = await fetchJson(fetcher, sourceInfo.url, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } });
    if (!Array.isArray(body) || body.length < 2 || !Array.isArray(body[0])) return noData(id, category, now, sourceInfo);
    const headers = body[0];
    const row = body.at(-1);
    const timestamp = iso(row[headers.indexOf('time_tag')]);
    const kp = Number(row[headers.indexOf('Kp')]);
    if (!timestamp || !finite(kp, 0, 9)) return noData(id, category, now, sourceInfo);
    return providerResult({
      id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'planetaryKIndex', category, title: '地磁活动',
        summary: `最近行星 K 指数为 ${kp.toFixed(1)}。中国大部分地区通常不具备可见极光条件，只有强地磁事件且纬度合适时才进入临时机会链。`,
        verification: 'observed', observedAt: timestamp, expiresAt: new Date(Date.parse(timestamp) + 3 * 60 * 60 * 1_000), sourceUrl: sourceInfo.url })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}

export class ProviderFactsService {
  constructor({
    fetcher = fetch,
    now = () => new Date(),
    timeoutMs = 12_000,
    cache = new Map(),
    configuration = null,
    sentinelStacBaseUrl = configuredUrl(process.env.LUMANEST_SENTINEL_STAC_URL) || 'https://stac.dataspace.copernicus.eu/v1',
    sentinelRasterGatewayUrl = configuredUrl(process.env.LUMANEST_SENTINEL_RASTER_GATEWAY_URL),
    sentinelRasterToken = configuredToken(process.env.LUMANEST_SENTINEL_RASTER_TOKEN),
    camsGatewayUrl = configuredUrl(process.env.LUMANEST_CAMS_GATEWAY_URL),
    camsApiKey = configuredToken(process.env.LUMANEST_CAMS_API_KEY),
    aeronetBaseUrl = configuredUrl(process.env.LUMANEST_AERONET_BASE_URL) || 'https://aeronet.gsfc.nasa.gov',
    officialNoticeGatewayUrl = configuredUrl(process.env.LUMANEST_OFFICIAL_NOTICE_GATEWAY_URL),
    officialNoticeGatewayToken = configuredToken(process.env.LUMANEST_OFFICIAL_NOTICE_GATEWAY_TOKEN),
    officialNoticeSources = [],
    overpassUrl = configuredUrl(process.env.LUMANEST_OVERPASS_URL) || 'https://overpass-api.de/api/interpreter',
    wikidataEndpoint = configuredUrl(process.env.LUMANEST_WIKIDATA_SPARQL_URL) || 'https://query.wikidata.org/sparql',
    commonsApiUrl = configuredUrl(process.env.LUMANEST_COMMONS_API_URL) || 'https://commons.wikimedia.org/w/api.php',
    gbifBaseUrl = configuredUrl(process.env.LUMANEST_GBIF_BASE_URL) || 'https://api.gbif.org',
    inaturalistBaseUrl = configuredUrl(process.env.LUMANEST_INATURALIST_BASE_URL) || 'https://api.inaturalist.org',
    ebirdBaseUrl = configuredUrl(process.env.LUMANEST_EBIRD_BASE_URL) || 'https://api.ebird.org',
    ebirdToken = configuredToken(process.env.LUMANEST_EBIRD_API_TOKEN),
    firmsBaseUrl = configuredUrl(process.env.LUMANEST_FIRMS_BASE_URL) || 'https://firms.modaps.eosdis.nasa.gov',
    firmsMapKey = configuredToken(process.env.LUMANEST_FIRMS_MAP_KEY, 128),
    marineGatewayUrl = configuredUrl(process.env.LUMANEST_COPERNICUS_MARINE_GATEWAY_URL),
    marineApiKey = configuredToken(process.env.LUMANEST_COPERNICUS_MARINE_API_KEY),
    horizonsBaseUrl = configuredUrl(process.env.LUMANEST_JPL_HORIZONS_URL) || 'https://ssd.jpl.nasa.gov',
    swpcBaseUrl = configuredUrl(process.env.LUMANEST_SWPC_BASE_URL) || 'https://services.swpc.noaa.gov',
  } = {}) {
    this.fetcher = fetcher;
    this.now = now;
    this.defaultTimeoutMs = timeoutMs;
    this.cache = cache;
    const fallback = validateProviderSources({
      ...providerSourceDefaults(),
      sentinelStacBaseUrl,
      sentinelRasterGatewayUrl,
      sentinelRasterToken,
      camsGatewayUrl,
      camsApiKey,
      aeronetBaseUrl,
      officialNoticeGatewayUrl,
      officialNoticeGatewayToken,
      officialNoticeSources,
      overpassUrl,
      wikidataEndpoint,
      commonsApiUrl,
      gbifBaseUrl,
      inaturalistBaseUrl,
      ebirdBaseUrl,
      ebirdToken,
      firmsBaseUrl,
      firmsMapKey,
      marineGatewayUrl,
      marineApiKey,
      horizonsBaseUrl,
      swpcBaseUrl,
    });
    this.configuration = typeof configuration === 'function'
      ? () => validateProviderSources(configuration(), { base: fallback })
      : () => fallback;
    this.inFlight = new Map();
    this.metrics = new Map(providerIds.map((id) => [id, {
      requestTotal: 0,
      readyTotal: 0,
      noDataTotal: 0,
      unavailableTotal: 0,
      unconfiguredTotal: 0,
      lastStatus: 'unknown',
      lastSuccessAt: null,
      lastFailureAt: null,
      lastLatencyMs: null,
      lastSignalCount: 0,
      lastErrorCode: null,
    }]));
    this.cacheMetrics = { hits: 0, misses: 0, coalesced: 0 };
  }

  async facts(query) {
    const now = this.now();
    const configuration = this.configuration();
    const key = cacheKey(query, providerConfigurationFingerprint(configuration));
    const cached = readCache(this.cache, key, now);
    if (cached != null) {
      this.cacheMetrics.hits += 1;
      return { ...cached, cacheStatus: 'hit' };
    }
    if (this.inFlight.has(key)) {
      this.cacheMetrics.coalesced += 1;
      const coalesced = await this.inFlight.get(key);
      return { ...structuredClone(coalesced), cacheStatus: 'coalesced' };
    }
    this.cacheMetrics.misses += 1;
    const request = this.#load(query, now, configuration).then((value) => {
      writeCache(this.cache, key, value);
      return value;
    }).finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, request);
    return request;
  }

  async #load(query, now, configuration) {
    const timeoutMs = Math.min(this.defaultTimeoutMs, configuration.timeoutMs);
    const calls = {
      sentinel1: () => sentinelProvider({ id: 'sentinel1', collection: 'sentinel-1-grd', query, fetcher: this.fetcher, timeoutMs, now, stacBaseUrl: configuration.sentinelStacBaseUrl }),
      sentinel2: () => sentinelProvider({ id: 'sentinel2', collection: 'sentinel-2-l2a', query, fetcher: this.fetcher, timeoutMs, now, stacBaseUrl: configuration.sentinelStacBaseUrl }),
      cams: () => normalizedGatewayProvider({
        id: 'cams', category: 'atmosphere', url: configuration.camsGatewayUrl,
        token: configuration.camsApiKey, query, fetcher: this.fetcher, timeoutMs, now,
        sourceInfo: source({ id: 'copernicus-cams', title: 'CAMS atmospheric composition', publisher: 'Copernicus Atmosphere Monitoring Service', url: 'https://ads.atmosphere.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway v1' }),
        allowedKinds: new Set(['aerosolOpticalDepth', 'dustLoad', 'blackCarbon', 'smokeTransport', 'visibilityModel']),
        allowedVerifications: new Set(['model', 'observed']),
      }),
      aeronet: () => aeronetProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.aeronetBaseUrl }),
      officialNotices: () => officialNoticesProvider({ query, fetcher: this.fetcher, timeoutMs, now, configuration }),
      osm: () => osmProvider({ query, fetcher: this.fetcher, timeoutMs, now, overpassUrl: configuration.overpassUrl }),
      wikidata: () => wikidataProvider({ query, fetcher: this.fetcher, timeoutMs, now, endpoint: configuration.wikidataEndpoint }),
      wikimediaCommons: () => commonsProvider({ query, fetcher: this.fetcher, timeoutMs, now, apiUrl: configuration.commonsApiUrl }),
      gbif: () => gbifProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.gbifBaseUrl }),
      inaturalist: () => inaturalistProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.inaturalistBaseUrl }),
      ebird: () => ebirdProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.ebirdBaseUrl, token: configuration.ebirdToken }),
      firms: () => firmsProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.firmsBaseUrl, mapKey: configuration.firmsMapKey }),
      copernicusMarine: () => normalizedGatewayProvider({
        id: 'copernicusMarine', category: 'marine', url: configuration.marineGatewayUrl,
        token: configuration.marineApiKey, query, fetcher: this.fetcher, timeoutMs, now,
        sourceInfo: source({ id: 'copernicus-marine', title: 'Copernicus Marine Toolbox gateway', publisher: 'Copernicus Marine Service', url: 'https://marine.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway v1' }),
        allowedKinds: new Set(['significantWaveHeight', 'waveDirection', 'wavePeriod', 'current', 'seaLevelAnomaly']),
        allowedVerifications: new Set(['model', 'observed']),
      }),
      jplHorizons: () => horizonsProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.horizonsBaseUrl }),
      noaaSwpc: () => swpcProvider({ fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.swpcBaseUrl }),
    };
    const providers = await Promise.all(query.providerIds.map(async (id) => {
      const started = Date.now();
      let result;
      if (!configuration.enabled || !configuration.enabledProviders.includes(id)) {
        result = unconfigured(id, 'other', now, '已在控制台关闭');
      } else {
        try {
          result = await calls[id]();
          if (id === 'sentinel2' && result.status === 'ready') {
            const derivatives = await sentinelRasterSignals({
              query,
              fetcher: this.fetcher,
              timeoutMs,
              now,
              url: configuration.sentinelRasterGatewayUrl,
              token: configuration.sentinelRasterToken,
            });
            if (derivatives.length > 0) {
              result = { ...result, signals: [...derivatives, ...result.signals].slice(0, 8) };
            }
          }
        } catch {
          result = unavailable(id, 'other', now);
        }
      }
      this.#record(id, result, Date.now() - started, now);
      return result;
    }));
    const readyCount = providers.filter((item) => item.status === 'ready').length;
    const status = readyCount === 0 ? 'unavailable' : readyCount === providers.length ? 'ready' : 'partial';
    const expiresAt = providers.map((item) => Date.parse(item.expiresAt)).filter(Number.isFinite)
      .reduce((minimum, value) => Math.min(minimum, value), now.getTime() + unavailableTtlMs);
    return {
      contractVersion: 1,
      requestedCoordinate: {
        latitude: Number(query.latitude.toFixed(5)),
        longitude: Number(query.longitude.toFixed(5)),
        system: 'wgs84',
      },
      radiusKm: query.radiusKm,
      generatedAt: now.toISOString(),
      expiresAt: new Date(expiresAt).toISOString(),
      status,
      cacheStatus: 'miss',
      providers,
    };
  }

  #record(id, result, latencyMs, now) {
    const metric = this.metrics.get(id);
    metric.requestTotal += 1;
    metric.lastStatus = result.status;
    metric.lastLatencyMs = latencyMs;
    metric.lastSignalCount = result.signals.length;
    metric[`${result.status}Total`] = (metric[`${result.status}Total`] ?? 0) + 1;
    if (result.status === 'ready' || result.status === 'noData') {
      metric.lastSuccessAt = now.toISOString();
      metric.lastErrorCode = null;
    } else {
      metric.lastFailureAt = now.toISOString();
      metric.lastErrorCode = result.status === 'unconfigured' ? 'not_configured' : 'upstream_unavailable';
    }
  }

  async authoritativeSafetyNotices(query) {
    const result = await this.facts({ ...query, providerIds: ['officialNotices'] });
    const provider = result.providers.find((item) => item.id === 'officialNotices');
    if (provider?.status !== 'ready') return [];
    const now = this.now();
    return provider.signals.flatMap((item) => {
      if (item.verification !== 'authoritative' || !officialNoticeSafetyKinds.has(item.kind) ||
          Date.parse(item.expiresAt) <= now.getTime()) return [];
      const id = createHash('sha256').update(`${item.id}|${item.sourceUrl}`).digest('hex').slice(0, 12);
      const severity = item.kind === 'roadClosure' || item.kind === 'fireRestriction' ? 'warning' : 'caution';
      const guidance = item.kind === 'roadClosure'
        ? ['不要按原路线继续前进', '以交通或景区官方公告为准']
        : item.kind === 'fireRestriction'
          ? ['遵守禁火与封闭要求', '不要进入受限林区或草原']
          : ['确认恢复开放前不要进入', '以发布机构最新公告为准'];
      return [{
        id,
        observedAt: item.observedAt,
        expiresAt: item.expiresAt,
        severity,
        title: item.title,
        description: item.summary,
        guidance,
        source: `官方公告 · ${provider.source?.publisher ?? '审核来源'}`,
      }];
    }).slice(0, 4);
  }

  async testProvider({ providerId, latitude, longitude, radiusKm = 25, locale = 'zh-CN' }) {
    if (!providerIdSet.has(providerId) || !finite(latitude, -90, 90) ||
        !finite(longitude, -180, 180) || !finite(radiusKm, 1, maximumRadiusKm)) {
      return { ok: false, error: 'invalid_request' };
    }
    const started = Date.now();
    const now = this.now();
    const configuration = this.configuration();
    const result = await this.#load({
      latitude,
      longitude,
      radiusKm: Math.round(radiusKm),
      locale,
      observedAt: now.toISOString(),
      providerIds: [providerId],
    }, now, configuration);
    const provider = result.providers[0];
    return {
      ok: provider.status !== 'unavailable',
      providerId,
      status: provider.status,
      signalCount: provider.signals.length,
      latencyMs: Date.now() - started,
      traceId: createHash('sha256').update(`${providerId}|${now.toISOString()}|${provider.status}`).digest('hex').slice(0, 16),
      error: provider.status === 'unavailable' ? 'upstream_unavailable' : null,
    };
  }

  healthSnapshot() {
    const configuration = this.configuration();
    const labels = new Map(publicProviderSourceCatalog().map((item) => [item.id, item.label]));
    return {
      provider: 'providerHub',
      enabled: configuration.enabled,
      checkedAt: this.now().toISOString(),
      configurationRevision: providerConfigurationFingerprint(configuration),
      cache: { ...this.cacheMetrics, entries: this.cache.size, inFlight: this.inFlight.size },
      providers: providerIds.map((id) => ({
        id,
        label: labels.get(id) ?? id,
        enabled: configuration.enabledProviders.includes(id),
        configured: providerConfigured(id, configuration),
        ...structuredClone(this.metrics.get(id)),
      })),
    };
  }

  clearCache() {
    this.cache.clear();
    this.inFlight.clear();
  }

  toPrometheus() {
    const lines = [];
    for (const [id, metric] of this.metrics) {
      lines.push(`lumanest_provider_requests_total{provider="${id}"} ${metric.requestTotal}`);
      lines.push(`lumanest_provider_ready_total{provider="${id}"} ${metric.readyTotal}`);
      lines.push(`lumanest_provider_unavailable_total{provider="${id}"} ${metric.unavailableTotal}`);
      lines.push(`lumanest_provider_last_latency_ms{provider="${id}"} ${metric.lastLatencyMs ?? 0}`);
    }
    lines.push(`lumanest_provider_cache_hits_total ${this.cacheMetrics.hits}`);
    lines.push(`lumanest_provider_cache_misses_total ${this.cacheMetrics.misses}`);
    return `${lines.join('\n')}\n`;
  }
}

export const supportedProviderIds = providerIds;
