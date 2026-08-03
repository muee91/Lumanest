import { createHash } from 'node:crypto';

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
  'ebird',
  'firms',
  'copernicusMarine',
  'jplHorizons',
  'noaaSwpc',
]);
const providerIdSet = new Set(providerIds);
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

function signal({ providerId, kind, category, title, summary, verification, observedAt, expiresAt, sourceUrl }) {
  const safeTitle = boundedText(title, 120);
  const safeSummary = boundedText(summary, 360);
  const safeObservedAt = iso(observedAt);
  const safeExpiresAt = iso(expiresAt);
  const safeSourceUrl = boundedUrl(sourceUrl);
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

function cacheKey(query) {
  return [
    query.latitude.toFixed(2), query.longitude.toFixed(2), query.radiusKm,
    query.locale, query.providerIds.join(','),
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
    ? [...providerIds]
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

async function normalizedGatewayProvider({ id, category, url, query, fetcher, timeoutMs, now, sourceInfo }) {
  if (!url) return unconfigured(id, category, now);
  try {
    const endpoint = new URL(url);
    endpoint.searchParams.set('lat', String(query.latitude));
    endpoint.searchParams.set('lon', String(query.longitude));
    endpoint.searchParams.set('radiusKm', String(query.radiusKm));
    endpoint.searchParams.set('at', query.observedAt);
    endpoint.searchParams.set('locale', query.locale);
    const body = await fetchJson(fetcher, endpoint, { timeoutMs, headers: { 'User-Agent': 'LumaNest/1.0' } });
    const items = Array.isArray(body?.signals) ? body.signals : [];
    const normalized = items.slice(0, 8).map((item) => signal({
      providerId: id,
      kind: boundedText(item?.kind, 64) ?? 'providerSignal',
      category,
      title: item?.title,
      summary: item?.summary,
      verification: ['authoritative', 'observed', 'model', 'reference', 'candidate'].includes(item?.verification)
        ? item.verification : 'model',
      observedAt: item?.observedAt ?? body?.observedAt ?? now,
      expiresAt: item?.expiresAt ?? body?.expiresAt ?? new Date(now.getTime() + readyTtlMs),
      sourceUrl: item?.sourceUrl ?? body?.sourceUrl ?? sourceInfo.url,
    })).filter(Boolean);
    return normalized.length === 0
      ? noData(id, category, now, sourceInfo)
      : providerResult({ id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo, signals: normalized });
  } catch {
    return unavailable(id, category, now);
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
  const q = `[out:json][timeout:12];(nwr(around:${radius},${query.latitude},${query.longitude})["tourism"="viewpoint"];nwr(around:${radius},${query.latitude},${query.longitude})["highway"="path"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="shelter"];nwr(around:${radius},${query.latitude},${query.longitude})["amenity"="drinking_water"];nwr(around:${radius},${query.latitude},${query.longitude})["historic"];);out tags center qt 100;`;
  try {
    const body = await fetchJson(fetcher, overpassUrl, {
      timeoutMs,
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'User-Agent': 'LumaNest/1.0' },
      body: new URLSearchParams({ data: q }).toString(),
    });
    const elements = Array.isArray(body?.elements) ? body.elements : [];
    if (elements.length === 0) return noData(id, category, now, sourceInfo);
    const counts = { viewpoint: 0, path: 0, shelter: 0, water: 0, historic: 0 };
    for (const item of elements) {
      const tags = item?.tags ?? {};
      if (tags.tourism === 'viewpoint') counts.viewpoint += 1;
      if (tags.highway === 'path') counts.path += 1;
      if (tags.amenity === 'shelter') counts.shelter += 1;
      if (tags.amenity === 'drinking_water') counts.water += 1;
      if (tags.historic != null) counts.historic += 1;
    }
    const summary = `公开地图标注：观景点 ${counts.viewpoint}、步道 ${counts.path}、避雨/庇护设施 ${counts.shelter}、饮水点 ${counts.water}、历史对象 ${counts.historic}。标注不代表当前开放或现场安全。`;
    return providerResult({
      id, category, status: 'ready', now, ttlMs: referenceTtlMs, sourceInfo,
      signals: [signal({ providerId: id, kind: 'outdoorMapInventory', category, title: '户外地图语义', summary,
        verification: 'reference', observedAt: now, expiresAt: new Date(now.getTime() + referenceTtlMs), sourceUrl: sourceInfo.url })],
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
    timeoutMs = 8_000,
    cache = new Map(),
    sentinelStacBaseUrl = configuredUrl(process.env.LUMANEST_SENTINEL_STAC_URL) || 'https://stac.dataspace.copernicus.eu/v1',
    camsGatewayUrl = configuredUrl(process.env.LUMANEST_CAMS_GATEWAY_URL),
    aeronetBaseUrl = configuredUrl(process.env.LUMANEST_AERONET_BASE_URL) || 'https://aeronet.gsfc.nasa.gov',
    officialNoticeGatewayUrl = configuredUrl(process.env.LUMANEST_OFFICIAL_NOTICE_GATEWAY_URL),
    overpassUrl = configuredUrl(process.env.LUMANEST_OVERPASS_URL) || 'https://overpass-api.de/api/interpreter',
    wikidataEndpoint = configuredUrl(process.env.LUMANEST_WIKIDATA_SPARQL_URL) || 'https://query.wikidata.org/sparql',
    commonsApiUrl = configuredUrl(process.env.LUMANEST_COMMONS_API_URL) || 'https://commons.wikimedia.org/w/api.php',
    gbifBaseUrl = configuredUrl(process.env.LUMANEST_GBIF_BASE_URL) || 'https://api.gbif.org',
    ebirdBaseUrl = configuredUrl(process.env.LUMANEST_EBIRD_BASE_URL) || 'https://api.ebird.org',
    ebirdToken = configuredToken(process.env.LUMANEST_EBIRD_API_TOKEN),
    firmsBaseUrl = configuredUrl(process.env.LUMANEST_FIRMS_BASE_URL) || 'https://firms.modaps.eosdis.nasa.gov',
    firmsMapKey = configuredToken(process.env.LUMANEST_FIRMS_MAP_KEY, 128),
    marineGatewayUrl = configuredUrl(process.env.LUMANEST_COPERNICUS_MARINE_GATEWAY_URL),
    horizonsBaseUrl = configuredUrl(process.env.LUMANEST_JPL_HORIZONS_URL) || 'https://ssd.jpl.nasa.gov',
    swpcBaseUrl = configuredUrl(process.env.LUMANEST_SWPC_BASE_URL) || 'https://services.swpc.noaa.gov',
  } = {}) {
    this.fetcher = fetcher;
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.cache = cache;
    this.config = {
      sentinelStacBaseUrl, camsGatewayUrl, aeronetBaseUrl, officialNoticeGatewayUrl,
      overpassUrl, wikidataEndpoint, commonsApiUrl, gbifBaseUrl, ebirdBaseUrl,
      ebirdToken, firmsBaseUrl, firmsMapKey, marineGatewayUrl, horizonsBaseUrl, swpcBaseUrl,
    };
    this.inFlight = new Map();
  }

  async facts(query) {
    const now = this.now();
    const key = cacheKey(query);
    const cached = readCache(this.cache, key, now);
    if (cached != null) return { ...cached, cacheStatus: 'hit' };
    if (this.inFlight.has(key)) {
      const coalesced = await this.inFlight.get(key);
      return { ...structuredClone(coalesced), cacheStatus: 'coalesced' };
    }
    const request = this.#load(query, now).then((value) => {
      writeCache(this.cache, key, value);
      return value;
    }).finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, request);
    return request;
  }

  async #load(query, now) {
    const calls = {
      sentinel1: () => sentinelProvider({ id: 'sentinel1', collection: 'sentinel-1-grd', query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, stacBaseUrl: this.config.sentinelStacBaseUrl }),
      sentinel2: () => sentinelProvider({ id: 'sentinel2', collection: 'sentinel-2-l2a', query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, stacBaseUrl: this.config.sentinelStacBaseUrl }),
      cams: () => normalizedGatewayProvider({ id: 'cams', category: 'atmosphere', url: this.config.camsGatewayUrl, query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, sourceInfo: source({ id: 'copernicus-cams', title: 'CAMS atmospheric composition', publisher: 'Copernicus Atmosphere Monitoring Service', url: 'https://ads.atmosphere.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway' }) }),
      aeronet: () => aeronetProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.aeronetBaseUrl }),
      officialNotices: () => normalizedGatewayProvider({ id: 'officialNotices', category: 'operations', url: this.config.officialNoticeGatewayUrl, query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, sourceInfo: source({ id: 'official-notice-gateway', title: 'Reviewed official notices', publisher: 'Configured government and venue sources', url: this.config.officialNoticeGatewayUrl || 'https://www.gov.cn/', license: 'Source-specific', version: 'normalized gateway v1' }) }),
      osm: () => osmProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, overpassUrl: this.config.overpassUrl }),
      wikidata: () => wikidataProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, endpoint: this.config.wikidataEndpoint }),
      wikimediaCommons: () => commonsProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, apiUrl: this.config.commonsApiUrl }),
      gbif: () => gbifProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.gbifBaseUrl }),
      ebird: () => ebirdProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.ebirdBaseUrl, token: this.config.ebirdToken }),
      firms: () => firmsProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.firmsBaseUrl, mapKey: this.config.firmsMapKey }),
      copernicusMarine: () => normalizedGatewayProvider({ id: 'copernicusMarine', category: 'marine', url: this.config.marineGatewayUrl, query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, sourceInfo: source({ id: 'copernicus-marine', title: 'Copernicus Marine Toolbox gateway', publisher: 'Copernicus Marine Service', url: 'https://marine.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway' }) }),
      jplHorizons: () => horizonsProvider({ query, fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.horizonsBaseUrl }),
      noaaSwpc: () => swpcProvider({ fetcher: this.fetcher, timeoutMs: this.timeoutMs, now, baseUrl: this.config.swpcBaseUrl }),
    };
    const providers = await Promise.all(query.providerIds.map(async (id) => {
      try {
        return await calls[id]();
      } catch {
        return unavailable(id, 'other', now);
      }
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
}

export const supportedProviderIds = providerIds;
