import { apiErrorCodes } from '../api/error-codes.mjs';

import { createHash } from 'node:crypto';

const commonsApiUrl = 'https://commons.wikimedia.org/w/api.php';
const wikidataApiUrl = 'https://www.wikidata.org/w/api.php';
const commonsImageHost = 'upload.wikimedia.org';
const amapImageHosts = new Set(['aos-comment.amap.com', 'store.is.autonavi.com']);
const supportedMimeTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

function boundedText(value, maximum = 240) {
  if (typeof value !== 'string') return null;
  const normalized = value
    .replace(/<br\s*\/?>/giu, ' ')
    .replace(/<[^>]*>/gu, ' ')
    .replace(/&nbsp;|&#160;/giu, ' ')
    .replace(/&amp;/giu, '&')
    .replace(/&quot;/giu, '"')
    .replace(/&#39;|&apos;/giu, "'")
    .replace(/\s+/gu, ' ')
    .trim();
  return normalized.length > 0 ? [...normalized].slice(0, maximum).join('') : null;
}

function normalizedMatchText(value) {
  return (boundedText(value, 1_200) ?? '')
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN')
    .replace(/[\p{P}\p{S}\s]/gu, '');
}

function validPoint(latitude, longitude) {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

function distanceMeters(first, second) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(second.latitude - first.latitude);
  const dLon = radians(second.longitude - first.longitude);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(first.latitude)) * Math.cos(radians(second.latitude)) *
    Math.sin(dLon / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function commonsImageUrl(value) {
  if (typeof value !== 'string' || value.length > 2_000) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      url.hostname.toLowerCase() === commonsImageHost ? url : null;
  } catch {
    return null;
  }
}

export function amapPlaceMediaUrl(value) {
  if (typeof value !== 'string' || value.length > 2_000) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      amapImageHosts.has(url.hostname.toLowerCase()) ? url : null;
  } catch {
    return null;
  }
}

export function placeMediaProxyPath(url) {
  return `/v1/explore/media/${Buffer.from(url.toString(), 'utf8').toString('base64url')}`;
}

function metadataValue(metadata, key) {
  return boundedText(metadata?.[key]?.value, 600);
}

function claimValue(entity, property) {
  const claims = Array.isArray(entity?.claims?.[property]) ? entity.claims[property] : [];
  return claims.flatMap((claim) => {
    const value = claim?.mainsnak?.datavalue?.value;
    return value == null ? [] : [value];
  });
}

function entityNames(entity) {
  const labels = Object.values(entity?.labels ?? {}).map((label) => label?.value);
  const aliases = Object.values(entity?.aliases ?? {})
    .flatMap((values) => Array.isArray(values) ? values : [])
    .map((alias) => alias?.value);
  return [...labels, ...aliases]
    .map((value) => boundedText(value, 160))
    .filter(Boolean);
}

function entityCoordinate(entity) {
  for (const value of claimValue(entity, 'P625')) {
    if (validPoint(value?.latitude, value?.longitude)) {
      return { latitude: value.latitude, longitude: value.longitude };
    }
  }
  return null;
}

function pageCoordinate(page) {
  const coordinate = Array.isArray(page?.coordinates) ? page.coordinates[0] : null;
  const latitude = coordinate?.lat;
  const longitude = coordinate?.lon;
  return validPoint(latitude, longitude) ? { latitude, longitude } : null;
}

function candidateFromPage(page, request) {
  const info = Array.isArray(page?.imageinfo) ? page.imageinfo[0] : null;
  if (info == null || !supportedMimeTypes.has(info.mime)) return null;
  const imageUrl = commonsImageUrl(info.thumburl ?? info.url);
  if (imageUrl == null) return null;
  const metadata = info.extmetadata ?? {};
  const searchable = [
    page.title,
    metadataValue(metadata, 'ObjectName'),
    metadataValue(metadata, 'ImageDescription'),
    metadataValue(metadata, 'Categories'),
    metadataValue(metadata, 'Credit'),
  ].filter(Boolean).join(' ');
  const normalizedName = normalizedMatchText(request.name);
  const nameMatched = normalizedName.length >= 3 &&
    normalizedMatchText(searchable).includes(normalizedName);
  const coordinate = pageCoordinate(page);
  const distance = coordinate == null ? null : distanceMeters(request, coordinate);
  const coordinateMatched = distance != null && distance <= 250;

  const city = normalizedMatchText(request.city);
  const cityMatched = city.length >= 2 && normalizedMatchText(searchable).includes(city);
  // A nearby image alone can be a different shop, building, or view. It must
  // name the requested POI, and for a city-scoped lookup have city or tight
  // coordinate corroboration before it can enter the product.
  if (!nameMatched || (city.length >= 2 && !cityMatched && !coordinateMatched)) return null;

  const score = 100 +
    (coordinateMatched ? Math.max(40, 100 - (distance / 25)) : 0) +
    (cityMatched ? 10 : 0);
  const license = metadataValue(metadata, 'LicenseShortName') ??
    metadataValue(metadata, 'UsageTerms');
  const artist = metadataValue(metadata, 'Artist');
  const canonicalTitle = boundedText(page.title?.replace(/^File:/u, ''), 160) ?? request.name;
  return {
    score,
    media: {
      id: createHash('sha256').update(imageUrl.toString()).digest('hex').slice(0, 24),
      kind: 'photo',
      proxyPath: placeMediaProxyPath(imageUrl),
      title: canonicalTitle,
      attribution: 'Wikimedia Commons',
      sourceTier: 'primary',
      ...(artist == null ? {} : { creator: artist }),
      ...(license == null ? {} : { license }),
      sourceUrl: `https://commons.wikimedia.org/?curid=${page.pageid}`,
      matchBasis: 'name',
    },
  };
}

function mediaFromEntityPage(page, request, names, canonicalFiles) {
  const info = Array.isArray(page?.imageinfo) ? page.imageinfo[0] : null;
  if (info == null || !supportedMimeTypes.has(info.mime)) return null;
  const imageUrl = commonsImageUrl(info.thumburl ?? info.url);
  if (imageUrl == null) return null;
  const canonicalTitle = boundedText(page.title?.replace(/^File:/u, ''), 160);
  if (canonicalTitle == null) return null;
  const metadata = info.extmetadata ?? {};
  const normalizedTitle = normalizedMatchText(canonicalTitle);
  const namesMatch = names
    .map(normalizedMatchText)
    .filter((name) => name.length >= 3)
    .some((name) => normalizedTitle.includes(name));
  const coordinate = pageCoordinate(page);
  const coordinateMatched = coordinate != null && distanceMeters(request, coordinate) <= 750;
  const canonical = canonicalFiles.has(canonicalTitle.normalize('NFKC'));
  // P18 is the entity's reviewed representative image. Other structured-data
  // results must still name the entity or be tightly geotagged to the place.
  if (!canonical && !namesMatch && !coordinateMatched) return null;
  const license = metadataValue(metadata, 'LicenseShortName') ??
    metadataValue(metadata, 'UsageTerms');
  const artist = metadataValue(metadata, 'Artist');
  return {
    id: createHash('sha256').update(imageUrl.toString()).digest('hex').slice(0, 24),
    kind: 'photo',
    proxyPath: placeMediaProxyPath(imageUrl),
    title: canonicalTitle,
    attribution: 'Wikimedia Commons',
    sourceTier: 'primary',
    ...(artist == null ? {} : { creator: artist }),
    ...(license == null ? {} : { license }),
    sourceUrl: `https://commons.wikimedia.org/?curid=${page.pageid}`,
    matchBasis: 'wikidataEntity',
  };
}

async function fetchJson(url, fetcher, timeoutMs) {
  const response = await fetcher(url, {
    redirect: 'error',
    signal: AbortSignal.timeout(Math.min(timeoutMs, 10_000)),
    headers: { 'User-Agent': 'LumaNest/1.0 PlaceMediaResolver' },
  });
  if (!response.ok || !response.headers.get('content-type')?.toLowerCase().includes('json')) {
    return null;
  }
  return response.json().catch(() => null);
}

async function searchWikidataPlaceMedia({ request, fetcher, timeoutMs }) {
  const searchUrl = new URL(wikidataApiUrl);
  searchUrl.search = new URLSearchParams({
    action: 'wbsearchentities',
    format: 'json',
    language: 'zh',
    uselang: 'zh',
    type: 'item',
    limit: '6',
    search: request.name,
  }).toString();
  const searchPayload = await fetchJson(searchUrl, fetcher, timeoutMs);
  const ids = Array.isArray(searchPayload?.search)
    ? searchPayload.search.map((item) => item?.id).filter((id) => /^Q[1-9][0-9]*$/u.test(id))
    : [];
  if (ids.length === 0) return [];

  const entitiesUrl = new URL(wikidataApiUrl);
  entitiesUrl.search = new URLSearchParams({
    action: 'wbgetentities',
    format: 'json',
    ids: ids.join('|'),
    props: 'claims|labels|aliases',
    languages: 'zh|zh-hans|en',
    languagefallback: '1',
  }).toString();
  const entitiesPayload = await fetchJson(entitiesUrl, fetcher, timeoutMs);
  const normalizedRequestName = normalizedMatchText(request.name);
  const entities = Object.values(entitiesPayload?.entities ?? {}).flatMap((entity) => {
    const names = entityNames(entity);
    const nameMatched = names
      .map(normalizedMatchText)
      .some((name) => name === normalizedRequestName);
    const coordinate = entityCoordinate(entity);
    const distance = coordinate == null ? null : distanceMeters(request, coordinate);
    return nameMatched && distance != null && distance <= 5_000
      ? [{ entity, names, distance }]
      : [];
  }).sort((first, second) => first.distance - second.distance);
  const selected = entities[0];
  if (selected == null || !/^Q[1-9][0-9]*$/u.test(selected.entity.id)) return [];

  const canonicalFiles = new Set(
    claimValue(selected.entity, 'P18')
      .filter((value) => typeof value === 'string' && value.length <= 240)
      .map((value) => value.normalize('NFKC')),
  );
  const commonsRequests = [];
  if (canonicalFiles.size > 0) {
    const canonicalUrl = new URL(commonsApiUrl);
    canonicalUrl.search = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      titles: [...canonicalFiles].map((title) => `File:${title}`).join('|'),
      prop: 'imageinfo|coordinates',
      iiprop: 'url|mime|extmetadata',
      iiurlwidth: '1280',
    }).toString();
    commonsRequests.push(canonicalUrl);
  }
  const depictsUrl = new URL(commonsApiUrl);
  depictsUrl.search = new URLSearchParams({
    action: 'query',
    format: 'json',
    formatversion: '2',
    generator: 'search',
    gsrsearch: `haswbstatement:P180=${selected.entity.id} filetype:bitmap`,
    gsrnamespace: '6',
    gsrlimit: '16',
    prop: 'imageinfo|coordinates',
    iiprop: 'url|mime|extmetadata',
    iiurlwidth: '1280',
  }).toString();
  commonsRequests.push(depictsUrl);
  const payloads = await Promise.all(
    commonsRequests.map((url) => fetchJson(url, fetcher, timeoutMs)),
  );
  const result = [];
  const seen = new Set();
  for (const payload of payloads) {
    const pages = Array.isArray(payload?.query?.pages) ? payload.query.pages : [];
    for (const page of pages) {
      const media = mediaFromEntityPage(page, request, selected.names, canonicalFiles);
      const identity = Number.isInteger(page?.pageid) ? `page:${page.pageid}` : media?.id;
      if (media != null && identity != null && seen.add(identity)) result.push(media);
      if (result.length >= 3) return result;
    }
  }
  return result;
}

export function parsePlaceMediaRequest(searchParams) {
  const name = boundedText(searchParams.get('name'), 160);
  const city = boundedText(searchParams.get('city'), 80);
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  if (name == null || [...name].length < 2 || !validPoint(latitude, longitude)) return null;
  const poiId = boundedText(searchParams.get('poiId'), 80);
  if (poiId != null && !/^[A-Za-z0-9_-]{1,80}$/.test(poiId)) return null;
  return Object.freeze({ name, city, latitude, longitude, poiId });
}

export async function searchVerifiedPlaceMedia({ request, fetcher = fetch, timeoutMs = 8_000 }) {
  const url = new URL(commonsApiUrl);
  url.search = new URLSearchParams({
    action: 'query',
    format: 'json',
    formatversion: '2',
    generator: 'search',
    gsrsearch: `intitle:"${request.name}" filetype:bitmap`,
    gsrnamespace: '6',
    gsrlimit: '12',
    prop: 'imageinfo|coordinates',
    iiprop: 'url|mime|extmetadata',
    iiurlwidth: '1280',
  }).toString();
  try {
    const payload = await fetchJson(url, fetcher, timeoutMs);
    if (payload == null) return { ok: false, error: apiErrorCodes.upstreamUnavailable };
    const pages = Array.isArray(payload?.query?.pages) ? payload.query.pages : [];
    const ranked = pages
      .map((page) => candidateFromPage(page, request))
      .filter(Boolean)
      .sort((first, second) => second.score - first.score);
    const exact = ranked.slice(0, 3).map((candidate) => candidate.media);
    if (exact.length >= 3) return { ok: true, media: exact };
    let entityMedia = [];
    try {
      entityMedia = await searchWikidataPlaceMedia({ request, fetcher, timeoutMs });
    } catch {
      // Wikidata expands translated-title recall. Its failure must not discard
      // Commons media that already passed the strict local evidence checks.
    }
    const seen = new Set(
      exact.flatMap((media) => [media.id, media.sourceUrl]),
    );
    return {
      ok: true,
      media: [
        ...exact,
        ...entityMedia.filter((media) => {
          if (seen.has(media.id) || seen.has(media.sourceUrl)) return false;
          seen.add(media.id);
          seen.add(media.sourceUrl);
          return true;
        }),
      ].slice(0, 3),
    };
  } catch {
    return { ok: false, error: apiErrorCodes.upstreamUnavailable };
  }
}

export function decodedVerifiedMediaUrl(token) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{16,2800}$/.test(token)) return null;
  try {
    const value = Buffer.from(token, 'base64url').toString('utf8');
    return commonsImageUrl(value) ?? amapPlaceMediaUrl(value);
  } catch {
    return null;
  }
}

export const verifiedPlaceMediaContentTypes = supportedMimeTypes;
