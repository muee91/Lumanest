import { apiErrorCodes } from '../../api/error-codes.mjs';

import { readFileSync } from 'node:fs';

import { wgs84ToGcj02 } from '../../context/amap-evidence.mjs';

const amapBaseUrl = 'https://restapi.amap.com';
const aliasesFile = new URL('../../providers/sunsetbot/city_aliases.json', import.meta.url);
const configuredNames = JSON.parse(readFileSync(aliasesFile, 'utf8'));

export function normalizeCityName(value) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim().replace(/\s+/g, '');
  if (!trimmed) return '';
  const aliased = configuredNames.aliases[trimmed] ?? trimmed;
  return aliased.replace(/(?:特别行政区|壮族自治区|回族自治区|维吾尔自治区|自治区|自治州|地区|市|盟)$/u, '');
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

export function parseAmapCityCandidates(body) {
  const address = body?.status === '1' && body.regeocode?.addressComponent;
  if (address == null || typeof address !== 'object' || Array.isArray(address)) return null;
  const city = normalizeCityName(stringValue(address.city));
  const province = normalizeCityName(stringValue(address.province));
  const requestedCity = city || province;
  if (!requestedCity) return null;
  const candidates = [];
  // A provider miss for a prefecture city must not silently turn into a
  // prediction for its province capital. Only use the province when AMap did
  // not provide a city at all (for example a municipality-level address).
  for (const value of city ? [city] : [province]) {
    if (value && !candidates.includes(value)) candidates.push(value);
    const alias = normalizeCityName(configuredNames.aliases[value]);
    if (alias && !candidates.includes(alias)) candidates.push(alias);
    const fallback = normalizeCityName(configuredNames.fallbacks[value]);
    if (fallback && !candidates.includes(fallback)) candidates.push(fallback);
  }
  return { requestedCity, candidates };
}

export async function resolveSkyOpportunityCity({
  latitude,
  longitude,
  amapWebKey,
  fetcher = fetch,
  timeoutMs = 5_000,
}) {
  if (!amapWebKey) return { ok: false, error: apiErrorCodes.notConfigured };
  const gcj = wgs84ToGcj02({ latitude, longitude });
  const url = new URL('/v3/geocode/regeo', amapBaseUrl);
  url.searchParams.set('location', `${gcj.longitude},${gcj.latitude}`);
  url.searchParams.set('extensions', 'base');
  url.searchParams.set('key', amapWebKey);
  try {
    const response = await fetcher(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const length = Number.parseInt(response.headers.get('content-length') ?? '', 10);
    if (!response.ok || (Number.isFinite(length) && length > 1024 * 1024)) {
      return { ok: false, error: apiErrorCodes.upstreamUnavailable };
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > 1024 * 1024) return { ok: false, error: apiErrorCodes.responseTooLarge };
    const parsed = parseAmapCityCandidates(JSON.parse(new TextDecoder().decode(bytes)));
    return parsed == null
      ? { ok: false, error: apiErrorCodes.cityUnavailable }
      : { ok: true, ...parsed };
  } catch {
    return { ok: false, error: apiErrorCodes.upstreamUnavailable };
  }
}
