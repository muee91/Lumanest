import { apiErrorCodes } from '../api/error-codes.mjs';

const defaultBaseUrl = 'https://api.open-meteo.com';
const hourlyVariables = Object.freeze([
  'cloud_cover',
  'cloud_cover_low',
  'cloud_cover_mid',
  'cloud_cover_high',
  'visibility',
  'precipitation_probability',
  'precipitation',
  'relative_humidity_2m',
  'wind_speed_10m',
  'wind_gusts_10m',
]);
const cacheTtlMilliseconds = 15 * 60 * 1_000;
const staleTtlMilliseconds = 60 * 60 * 1_000;
const maximumCacheEntries = 256;

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function sanitizedBaseUrl(value) {
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  try {
    const url = new URL(value.trim());
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
    return url;
  } catch {
    return null;
  }
}

function coordinateCell(latitude, longitude) {
  return `${latitude.toFixed(2)}:${longitude.toFixed(2)}`;
}

function cacheKey(latitude, longitude, hours) {
  return `${coordinateCell(latitude, longitude)}:${Math.ceil(hours / 6) * 6}`;
}

function boundedArray(value, length) {
  return Array.isArray(value) && value.length === length ? value : null;
}

function nullableNumber(value, minimum, maximum) {
  return value == null ? null : finite(value, minimum, maximum) ? value : null;
}

function parseForecast(payload) {
  const hourly = payload?.hourly;
  if (hourly == null || typeof hourly !== 'object' || Array.isArray(hourly) || !Array.isArray(hourly.time)) {
    return null;
  }
  const length = hourly.time.length;
  if (length === 0 || length > 400) return null;
  const arrays = Object.fromEntries(hourlyVariables.map((name) => [name, boundedArray(hourly[name], length)]));
  if (Object.values(arrays).some((value) => value == null)) return null;
  const points = [];
  let previous = -Infinity;
  for (let index = 0; index < length; index += 1) {
    const validAt = new Date(hourly.time[index]);
    const timestamp = validAt.getTime();
    if (!Number.isFinite(timestamp) || timestamp <= previous) continue;
    previous = timestamp;
    const point = {
      validAt: validAt.toISOString(),
      totalCloudCoverPercent: nullableNumber(arrays.cloud_cover[index], 0, 100),
      lowCloudCoverPercent: nullableNumber(arrays.cloud_cover_low[index], 0, 100),
      middleCloudCoverPercent: nullableNumber(arrays.cloud_cover_mid[index], 0, 100),
      highCloudCoverPercent: nullableNumber(arrays.cloud_cover_high[index], 0, 100),
      visibilityMeters: nullableNumber(arrays.visibility[index], 0, 100_000),
      precipitationProbabilityPercent: nullableNumber(arrays.precipitation_probability[index], 0, 100),
      precipitationMm: nullableNumber(arrays.precipitation[index], 0, 500),
      relativeHumidityPercent: nullableNumber(arrays.relative_humidity_2m[index], 0, 100),
      windSpeedKmh: nullableNumber(arrays.wind_speed_10m[index], 0, 400),
      windGustKmh: nullableNumber(arrays.wind_gusts_10m[index], 0, 500),
    };
    const available = Object.entries(point).some(([key, value]) => key !== 'validAt' && value != null);
    if (available) points.push(Object.freeze(point));
  }
  return points.length === 0 ? null : Object.freeze(points);
}

function cloned(value, cacheStatus, stale) {
  return {
    ...structuredClone(value),
    cacheStatus,
    isStaleCache: stale,
  };
}

export class OpenMeteoNightSkyForecast {
  constructor({
    baseUrl = defaultBaseUrl,
    fetcher = fetch,
    now = () => new Date(),
    timeoutMs = 8_000,
    cache = new Map(),
  } = {}) {
    this.baseUrl = sanitizedBaseUrl(baseUrl);
    this.fetcher = fetcher;
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.cache = cache;
    this.inFlight = new Map();
  }

  async forecast({ latitude, longitude, hours = 72 }) {
    if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180) ||
        !Number.isInteger(hours) || hours < 6 || hours > 96 || this.baseUrl == null) {
      return { ok: false, error: this.baseUrl == null ? apiErrorCodes.unconfigured : apiErrorCodes.invalidRequest };
    }
    const instant = this.now();
    const key = cacheKey(latitude, longitude, hours);
    const cached = this.cache.get(key);
    if (cached != null && cached.expiresAt > instant.getTime()) {
      return { ok: true, body: cloned(cached.body, 'hit', false) };
    }
    const stale = cached != null && cached.staleUntil > instant.getTime() ? cached.body : null;
    if (this.inFlight.has(key)) return this.inFlight.get(key);
    const operation = this.#fetch({ latitude, longitude, hours, instant })
      .then((result) => {
        if (result.ok) {
          this.cache.delete(key);
          this.cache.set(key, {
            body: result.body,
            expiresAt: instant.getTime() + cacheTtlMilliseconds,
            staleUntil: instant.getTime() + staleTtlMilliseconds,
          });
          while (this.cache.size > maximumCacheEntries) this.cache.delete(this.cache.keys().next().value);
          return { ok: true, body: cloned(result.body, 'miss', false) };
        }
        return stale == null
          ? result
          : { ok: true, body: cloned(stale, 'stale', true) };
      })
      .finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, operation);
    return operation;
  }

  async #fetch({ latitude, longitude, hours, instant }) {
    const url = new URL('/v1/forecast', this.baseUrl);
    url.searchParams.set('latitude', String(latitude));
    url.searchParams.set('longitude', String(longitude));
    url.searchParams.set('hourly', hourlyVariables.join(','));
    url.searchParams.set('timezone', 'GMT');
    url.searchParams.set('forecast_hours', String(Math.min(96, hours + 2)));
    url.searchParams.set('past_hours', '2');
    url.searchParams.set('cell_selection', 'land');
    try {
      const response = await this.fetcher(url, {
        signal: AbortSignal.timeout(this.timeoutMs),
        headers: { 'User-Agent': 'LumaNest/1.0 NightSkyForecast' },
      });
      const payload = await response.json();
      const points = response.ok ? parseForecast(payload) : null;
      if (points == null) return { ok: false, error: apiErrorCodes.upstreamUnavailable };
      const fetchedAt = instant.toISOString();
      return {
        ok: true,
        body: {
          source: 'open-meteo-best-match',
          modelSelection: 'best_match',
          attribution: 'Open-Meteo weather forecast',
          license: 'CC-BY-4.0',
          fetchedAt,
          expiresAt: new Date(instant.getTime() + cacheTtlMilliseconds).toISOString(),
          points,
        },
      };
    } catch {
      return { ok: false, error: apiErrorCodes.upstreamUnavailable };
    }
  }
}

export const openMeteoNightSkyHourlyVariables = hourlyVariables;
