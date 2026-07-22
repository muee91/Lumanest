const openMeteoBaseUrl = 'https://api.open-meteo.com';
const resolvedCacheTtlMilliseconds = 24 * 60 * 60 * 1_000;
const degradedCacheTtlMilliseconds = 15 * 60 * 1_000;
const maximumCacheEntries = 512;

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

export function validSiteEnvironmentQuery(searchParams) {
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180)) return null;
  return { latitude, longitude };
}

export function relativeRadianceBand(radiance) {
  if (!finite(radiance, 0, 1_000_000)) return null;
  if (radiance <= 0.15) return 'veryDark';
  if (radiance <= 0.5) return 'dark';
  if (radiance <= 2) return 'moderate';
  if (radiance <= 10) return 'bright';
  return 'veryBright';
}

function cacheKey(query) {
  return `${query.latitude.toFixed(3)}:${query.longitude.toFixed(3)}`;
}

function readCache(cache, key, instant) {
  const entry = cache.get(key);
  if (entry == null) return null;
  if (entry.expiresAt <= instant.getTime()) {
    cache.delete(key);
    return null;
  }
  cache.delete(key);
  cache.set(key, entry);
  return structuredClone(entry.body);
}

function writeCache(cache, key, body, instant) {
  const complete = body.terrain.status === 'ready' && body.nightSkyBackground.status === 'ready';
  cache.delete(key);
  cache.set(key, {
    body: structuredClone(body),
    expiresAt: instant.getTime() + (complete
      ? resolvedCacheTtlMilliseconds
      : degradedCacheTtlMilliseconds),
  });
  while (cache.size > maximumCacheEntries) cache.delete(cache.keys().next().value);
}

function unavailableTerrain() {
  return {
    status: 'unavailable',
    elevationMeters: null,
    source: null,
  };
}

function unavailableNightSkyBackground(status) {
  return {
    status,
    radiance: null,
    radianceUnit: 'nW/cm2/sr',
    relativeRadianceBand: null,
    classificationVersion: 'viirs-relative-radiance.1',
    datasetYear: null,
    resolutionMeters: null,
    source: null,
  };
}

async function elevationFact(query, fetcher, timeoutMs) {
  const url = new URL('/v1/elevation', openMeteoBaseUrl);
  url.searchParams.set('latitude', String(query.latitude));
  url.searchParams.set('longitude', String(query.longitude));
  try {
    const response = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const payload = await response.json();
    const elevation = Array.isArray(payload?.elevation) ? payload.elevation[0] : null;
    if (!response.ok || !finite(elevation, -500, 9_000)) return unavailableTerrain();
    return {
      status: 'ready',
      elevationMeters: elevation,
      source: {
        id: 'open-meteo-elevation',
        dataset: 'Copernicus DEM GLO-90 2021',
        resolutionMeters: 90,
        attribution: 'Copernicus DEM · Open-Meteo',
      },
    };
  } catch {
    return unavailableTerrain();
  }
}

async function nightSkyBackgroundFact(query, rasterServiceUrl, fetcher, timeoutMs) {
  const baseUrl = sanitizedBaseUrl(rasterServiceUrl);
  if (baseUrl == null) return unavailableNightSkyBackground('unconfigured');
  const url = new URL('/v1/viirs/sample', baseUrl);
  url.searchParams.set('latitude', String(query.latitude));
  url.searchParams.set('longitude', String(query.longitude));
  try {
    const response = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const payload = await response.json();
    const radiance = Number(payload?.radiance);
    const datasetYear = Number(payload?.datasetYear);
    const resolutionMeters = Number(payload?.resolutionMeters);
    if (!response.ok || payload?.status !== 'ready' || !finite(radiance, 0, 1_000_000) ||
        !Number.isInteger(datasetYear) || datasetYear < 2012 || datasetYear > 2100 ||
        !finite(resolutionMeters, 1, 10_000) || typeof payload?.sourceId !== 'string' ||
        payload.sourceId.length === 0 || payload.sourceId.length > 120) {
      return unavailableNightSkyBackground('unavailable');
    }
    return {
      status: 'ready',
      radiance,
      radianceUnit: 'nW/cm2/sr',
      relativeRadianceBand: relativeRadianceBand(radiance),
      classificationVersion: 'viirs-relative-radiance.1',
      datasetYear,
      resolutionMeters,
      source: {
        id: payload.sourceId,
        attribution: typeof payload.attribution === 'string' && payload.attribution.length <= 240
          ? payload.attribution
          : 'VIIRS nighttime lights',
      },
    };
  } catch {
    return unavailableNightSkyBackground('unavailable');
  }
}

export class SiteEnvironmentService {
  constructor({
    rasterServiceUrl = '',
    fetcher = fetch,
    now = () => new Date(),
    timeoutMs = 8_000,
    cache = new Map(),
  } = {}) {
    this.rasterServiceUrl = rasterServiceUrl;
    this.fetcher = fetcher;
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.cache = cache;
    this.inFlight = new Map();
  }

  async facts(query) {
    const instant = this.now();
    const key = cacheKey(query);
    const cached = readCache(this.cache, key, instant);
    if (cached != null) return { ...cached, cacheStatus: 'hit' };
    if (this.inFlight.has(key)) return this.inFlight.get(key);
    const request = this.#load(query, key, instant).finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, request);
    return request;
  }

  async #load(query, key, instant) {
    const [terrain, nightSkyBackground] = await Promise.all([
      elevationFact(query, this.fetcher, this.timeoutMs),
      nightSkyBackgroundFact(
        query,
        this.rasterServiceUrl,
        this.fetcher,
        this.timeoutMs,
      ),
    ]);
    const body = {
      contractVersion: 1,
      coordinate: {
        latitude: Number(query.latitude.toFixed(5)),
        longitude: Number(query.longitude.toFixed(5)),
        system: 'wgs84',
      },
      terrain,
      nightSkyBackground,
      generatedAt: instant.toISOString(),
      expiresAt: new Date(instant.getTime() + (terrain.status === 'ready' &&
        nightSkyBackground.status === 'ready'
        ? resolvedCacheTtlMilliseconds
        : degradedCacheTtlMilliseconds)).toISOString(),
      cacheStatus: 'miss',
    };
    writeCache(this.cache, key, body, instant);
    return body;
  }
}
