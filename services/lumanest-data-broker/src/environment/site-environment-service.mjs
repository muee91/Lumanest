const openMeteoBaseUrl = 'https://api.open-meteo.com';
const terrainReadyTtlMilliseconds = 90 * 24 * 60 * 60 * 1_000;
const nightSkyReadyTtlMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const nightSkyUnversionedTtlMilliseconds = 24 * 60 * 60 * 1_000;
const unavailableCacheTtlMilliseconds = 15 * 60 * 1_000;
const unconfiguredCacheTtlMilliseconds = 5 * 60 * 1_000;
const maximumCacheEntries = 512;
const terrainDatasetRevision = 'copernicus-dem-glo90-2021';

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

function boundedToken(value) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= 512
    ? value.trim()
    : '';
}

function boundedRevision(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._:-]{1,120}$/.test(value.trim())
    ? value.trim()
    : '';
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

function normalizedPoint(query, decimals = 3) {
  return {
    latitude: Number(query.latitude.toFixed(decimals)),
    longitude: Number(query.longitude.toFixed(decimals)),
  };
}

function coordinate(point) {
  return {
    latitude: Number(point.latitude.toFixed(5)),
    longitude: Number(point.longitude.toFixed(5)),
    system: 'wgs84',
  };
}

function cacheKey(prefix, point, revision) {
  return `${prefix}:${revision}:${point.latitude.toFixed(3)}:${point.longitude.toFixed(3)}`;
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
  return { ...structuredClone(entry.fact), cacheStatus: 'hit' };
}

function writeCache(cache, key, fact) {
  cache.delete(key);
  cache.set(key, {
    fact: structuredClone(fact),
    expiresAt: Date.parse(fact.expiresAt),
  });
  while (cache.size > maximumCacheEntries) cache.delete(cache.keys().next().value);
}

function factMetadata(point, instant, ttlMilliseconds, cacheStatus = 'miss') {
  return {
    sampledCoordinate: coordinate(point),
    generatedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + ttlMilliseconds).toISOString(),
    cacheStatus,
  };
}

function unavailableTerrain(point, instant, cacheStatus = 'miss') {
  return {
    status: 'unavailable',
    elevationMeters: null,
    ...factMetadata(point, instant, unavailableCacheTtlMilliseconds, cacheStatus),
    source: null,
  };
}

function unavailableNightSkyBackground(status, point, instant, cacheStatus = 'miss') {
  const ttl = status === 'unconfigured'
    ? unconfiguredCacheTtlMilliseconds
    : unavailableCacheTtlMilliseconds;
  return {
    status,
    radiance: null,
    radianceUnit: 'nW/cm2/sr',
    relativeRadianceBand: null,
    classificationVersion: 'viirs-relative-radiance.1',
    datasetYear: null,
    datasetRevision: null,
    resolutionMeters: null,
    ...factMetadata(point, instant, ttl, cacheStatus),
    source: null,
  };
}

async function elevationFact(point, fetcher, timeoutMs, instant) {
  const url = new URL('/v1/elevation', openMeteoBaseUrl);
  url.searchParams.set('latitude', String(point.latitude));
  url.searchParams.set('longitude', String(point.longitude));
  try {
    const response = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
    const payload = await response.json();
    const elevation = Array.isArray(payload?.elevation) ? payload.elevation[0] : null;
    if (!response.ok || !finite(elevation, -500, 9_000)) {
      return unavailableTerrain(point, instant);
    }
    return {
      status: 'ready',
      elevationMeters: elevation,
      ...factMetadata(point, instant, terrainReadyTtlMilliseconds),
      source: {
        id: 'open-meteo-elevation',
        dataset: 'Copernicus DEM GLO-90 2021',
        revision: terrainDatasetRevision,
        resolutionMeters: 90,
        attribution: 'Copernicus DEM · Open-Meteo',
      },
    };
  } catch {
    return unavailableTerrain(point, instant);
  }
}

async function nightSkyBackgroundFact({
  point,
  rasterServiceUrl,
  rasterServiceToken,
  expectedDatasetRevision,
  fetcher,
  timeoutMs,
  instant,
}) {
  const baseUrl = sanitizedBaseUrl(rasterServiceUrl);
  if (baseUrl == null || rasterServiceToken.length === 0) {
    return unavailableNightSkyBackground('unconfigured', point, instant);
  }
  const url = new URL('/v1/viirs/sample', baseUrl);
  url.searchParams.set('latitude', String(point.latitude));
  url.searchParams.set('longitude', String(point.longitude));
  try {
    const response = await fetcher(url, {
      signal: AbortSignal.timeout(timeoutMs),
      headers: { Authorization: `Bearer ${rasterServiceToken}` },
    });
    const payload = await response.json();
    const radiance = Number(payload?.radiance);
    const datasetYear = Number(payload?.datasetYear);
    const datasetRevision = boundedRevision(payload?.datasetRevision);
    const resolutionMeters = Number(payload?.resolutionMeters);
    const sampledLatitude = Number(payload?.sampledLatitude);
    const sampledLongitude = Number(payload?.sampledLongitude);
    if (!response.ok || payload?.status !== 'ready' || !finite(radiance, 0, 1_000_000) ||
        !Number.isInteger(datasetYear) || datasetYear < 2012 || datasetYear > 2100 ||
        datasetRevision.length === 0 ||
        (expectedDatasetRevision.length > 0 && datasetRevision !== expectedDatasetRevision) ||
        !finite(resolutionMeters, 1, 10_000) ||
        !finite(sampledLatitude, -90, 90) || !finite(sampledLongitude, -180, 180) ||
        typeof payload?.sourceId !== 'string' ||
        payload.sourceId.length === 0 || payload.sourceId.length > 120) {
      return unavailableNightSkyBackground('unavailable', point, instant);
    }
    const sampledPoint = { latitude: sampledLatitude, longitude: sampledLongitude };
    const ttl = expectedDatasetRevision.length > 0
      ? nightSkyReadyTtlMilliseconds
      : nightSkyUnversionedTtlMilliseconds;
    return {
      status: 'ready',
      radiance,
      radianceUnit: 'nW/cm2/sr',
      relativeRadianceBand: relativeRadianceBand(radiance),
      classificationVersion: 'viirs-relative-radiance.1',
      datasetYear,
      datasetRevision,
      resolutionMeters,
      ...factMetadata(sampledPoint, instant, ttl),
      source: {
        id: payload.sourceId,
        revision: datasetRevision,
        attribution: typeof payload.attribution === 'string' && payload.attribution.length <= 240
          ? payload.attribution
          : 'VIIRS nighttime lights',
      },
    };
  } catch {
    return unavailableNightSkyBackground('unavailable', point, instant);
  }
}

export class SiteEnvironmentService {
  constructor({
    rasterServiceUrl = '',
    rasterServiceToken = process.env.LUMANEST_RASTER_SERVICE_TOKEN?.trim() ?? '',
    rasterDatasetRevision = process.env.LUMANEST_RASTER_DATASET_REVISION?.trim() ?? '',
    fetcher = fetch,
    now = () => new Date(),
    timeoutMs = 8_000,
    terrainCache = new Map(),
    nightSkyCache = new Map(),
  } = {}) {
    this.rasterServiceUrl = rasterServiceUrl;
    this.rasterServiceToken = boundedToken(rasterServiceToken);
    this.rasterDatasetRevision = boundedRevision(rasterDatasetRevision);
    this.fetcher = fetcher;
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.terrainCache = terrainCache;
    this.nightSkyCache = nightSkyCache;
    this.terrainInFlight = new Map();
    this.nightSkyInFlight = new Map();
  }

  async facts(query) {
    const instant = this.now();
    const [terrain, nightSkyBackground] = await Promise.all([
      this.#terrain(query, instant),
      this.#nightSky(query, instant),
    ]);
    return {
      contractVersion: 2,
      requestedCoordinate: coordinate(query),
      terrain,
      nightSkyBackground,
      generatedAt: instant.toISOString(),
    };
  }

  async #terrain(query, instant) {
    const point = normalizedPoint(query);
    const key = cacheKey('terrain', point, terrainDatasetRevision);
    const cached = readCache(this.terrainCache, key, instant);
    if (cached != null) return cached;
    if (this.terrainInFlight.has(key)) {
      const fact = await this.terrainInFlight.get(key);
      return { ...structuredClone(fact), cacheStatus: 'coalesced' };
    }
    const request = elevationFact(point, this.fetcher, this.timeoutMs, instant)
      .then((fact) => {
        writeCache(this.terrainCache, key, fact);
        return fact;
      })
      .finally(() => this.terrainInFlight.delete(key));
    this.terrainInFlight.set(key, request);
    return request;
  }

  async #nightSky(query, instant) {
    const point = normalizedPoint(query);
    const revision = this.rasterDatasetRevision || 'service-reported';
    const baseUrl = sanitizedBaseUrl(this.rasterServiceUrl);
    const key = cacheKey(`night-sky:${baseUrl?.origin ?? 'unconfigured'}`, point, revision);
    const cached = readCache(this.nightSkyCache, key, instant);
    if (cached != null) return cached;
    if (this.nightSkyInFlight.has(key)) {
      const fact = await this.nightSkyInFlight.get(key);
      return { ...structuredClone(fact), cacheStatus: 'coalesced' };
    }
    const request = nightSkyBackgroundFact({
      point,
      rasterServiceUrl: this.rasterServiceUrl,
      rasterServiceToken: this.rasterServiceToken,
      expectedDatasetRevision: this.rasterDatasetRevision,
      fetcher: this.fetcher,
      timeoutMs: this.timeoutMs,
      instant,
    }).then((fact) => {
      writeCache(this.nightSkyCache, key, fact);
      return fact;
    }).finally(() => this.nightSkyInFlight.delete(key));
    this.nightSkyInFlight.set(key, request);
    return request;
  }
}
