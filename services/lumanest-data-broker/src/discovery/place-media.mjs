import { createHash } from 'node:crypto';

const commonsApiUrl = 'https://commons.wikimedia.org/w/api.php';
const commonsImageHost = 'upload.wikimedia.org';
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

function metadataValue(metadata, key) {
  return boundedText(metadata?.[key]?.value, 600);
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
  const coordinateMatched = distance != null && distance <= 1_500;

  // A broad keyword result is not enough. The exact place name must be present
  // in Commons metadata, or the media itself must be geotagged near the POI.
  if (!nameMatched && !coordinateMatched) return null;

  const city = normalizedMatchText(request.city);
  const cityMatched = city.length >= 2 && normalizedMatchText(searchable).includes(city);
  const score = (nameMatched ? 100 : 0) +
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
      proxyPath: `/v1/explore/media/${Buffer.from(imageUrl.toString(), 'utf8').toString('base64url')}`,
      title: canonicalTitle,
      attribution: 'Wikimedia Commons',
      ...(artist == null ? {} : { creator: artist }),
      ...(license == null ? {} : { license }),
      sourceUrl: `https://commons.wikimedia.org/?curid=${page.pageid}`,
      matchBasis: coordinateMatched ? 'coordinate' : 'name',
    },
  };
}

export function parsePlaceMediaRequest(searchParams) {
  const name = boundedText(searchParams.get('name'), 160);
  const city = boundedText(searchParams.get('city'), 80);
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  if (name == null || [...name].length < 2 || !validPoint(latitude, longitude)) return null;
  return Object.freeze({ name, city, latitude, longitude });
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
    const response = await fetcher(url, {
      redirect: 'error',
      signal: AbortSignal.timeout(Math.min(timeoutMs, 10_000)),
      headers: { 'User-Agent': 'LumaNest/1.0 PlaceMediaResolver' },
    });
    if (!response.ok || !response.headers.get('content-type')?.toLowerCase().includes('json')) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    const payload = await response.json().catch(() => null);
    const pages = Array.isArray(payload?.query?.pages) ? payload.query.pages : [];
    const ranked = pages
      .map((page) => candidateFromPage(page, request))
      .filter(Boolean)
      .sort((first, second) => second.score - first.score);
    return { ok: true, media: ranked[0]?.media ?? null };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

export function decodedVerifiedMediaUrl(token) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{16,2800}$/.test(token)) return null;
  try {
    return commonsImageUrl(Buffer.from(token, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

export const verifiedPlaceMediaContentTypes = supportedMimeTypes;
