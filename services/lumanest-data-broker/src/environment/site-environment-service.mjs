const openMeteoBaseUrl = 'https://api.open-meteo.com';
const terrainReadyTtlMilliseconds = 90 * 24 * 60 * 60 * 1_000;
const nightSkyReadyTtlMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const nightSkyUnversionedTtlMilliseconds = 24 * 60 * 60 * 1_000;
const unavailableCacheTtlMilliseconds = 15 * 60 * 1_000;
const unconfiguredCacheTtlMilliseconds = 5 * 60 * 1_000;
const maximumCacheEntries = 512;
const terrainDatasetRevision = 'copernicus-dem-glo90-2021';
const spatialAnalysisVersion = 'viirs-spatial-radiance.1';
const neighborhoodRadiiKm = Object.freeze([1, 5, 20]);
const lightDomeDirections = Object.freeze([
  Object.freeze({ direction: 'north', azimuthCenterDegrees: 0 }),
  Object.freeze({ direction: 'northeast', azimuthCenterDegrees: 45 }),
  Object.freeze({ direction: 'east', azimuthCenterDegrees: 90 }),
  Object.freeze({ direction: 'southeast', azimuthCenterDegrees: 135 }),
  Object.freeze({ direction: 'south', azimuthCenterDegrees: 180 }),
  Object.freeze({ direction: 'southwest', azimuthCenterDegrees: 225 }),
  Object.freeze({ direction: 'west', azimuthCenterDegrees: 270 }),
  Object.freeze({ direction: 'northwest', azimuthCenterDegrees: 315 }),
]);

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

function objectWithExactKeys(value, keys) {
  return value != null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
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

function validatedSummary(value) {
  const sampleCount = value.sampleCount;
  const coverageRatio = value.coverageRatio;
  const median = value.median;
  const p90 = value.p90;
  const maximum = value.maximum;
  if (!Number.isInteger(sampleCount) || sampleCount < 0 || sampleCount > 10_000_000 ||
      !finite(coverageRatio, 0, 1)) return null;
  if (sampleCount === 0) {
    if (median !== null || p90 !== null || maximum !== null) return null;
    return { sampleCount, coverageRatio, median: null, p90: null, maximum: null };
  }
  if (!finite(median, 0, 1_000_000) || !finite(p90, 0, 1_000_000) ||
      !finite(maximum, 0, 1_000_000) || median > p90 || p90 > maximum) return null;
  return { sampleCount, coverageRatio, median, p90, maximum };
}

function validatedSpatialAnalysis(value) {
  if (!objectWithExactKeys(value, [
    'analysisVersion', 'maximumRadiusKm', 'neighborhoods', 'lightDomes',
  ]) || value.analysisVersion !== spatialAnalysisVersion || value.maximumRadiusKm !== 20 ||
      !Array.isArray(value.neighborhoods) || value.neighborhoods.length !== neighborhoodRadiiKm.length) {
    return null;
  }
  const neighborhoods = [];
  for (let index = 0; index < neighborhoodRadiiKm.length; index += 1) {
    const item = value.neighborhoods[index];
    if (!objectWithExactKeys(item, [
      'radiusKm', 'sampleCount', 'coverageRatio', 'median', 'p90', 'maximum',
    ]) || item.radiusKm !== neighborhoodRadiiKm[index]) return null;
    const summary = validatedSummary(item);
    if (summary == null) return null;
    neighborhoods.push({
      radiusKm: item.radiusKm,
      ...summary,
      relativeRadianceBand: summary.p90 == null ? null : relativeRadianceBand(summary.p90),
    });
  }

  const lightDomes = value.lightDomes;
  if (!objectWithExactKeys(lightDomes, [
    'innerRadiusKm', 'outerRadiusKm', 'sectorCount', 'dominantDirection',
    'dominantAzimuthDegrees', 'sectors',
  ]) || lightDomes.innerRadiusKm !== 1 || lightDomes.outerRadiusKm !== 20 ||
      lightDomes.sectorCount !== lightDomeDirections.length ||
      !Array.isArray(lightDomes.sectors) || lightDomes.sectors.length !== lightDomeDirections.length) {
    return null;
  }
  const sectors = [];
  for (let index = 0; index < lightDomeDirections.length; index += 1) {
    const expected = lightDomeDirections[index];
    const item = lightDomes.sectors[index];
    if (!objectWithExactKeys(item, [
      'direction', 'azimuthCenterDegrees', 'sampleCount', 'coverageRatio',
      'median', 'p90', 'maximum', 'peakDistanceKm',
    ]) || item.direction !== expected.direction ||
        item.azimuthCenterDegrees !== expected.azimuthCenterDegrees) return null;
    const summary = validatedSummary(item);
    if (summary == null) return null;
    const peakDistanceKm = item.peakDistanceKm;
    if ((summary.sampleCount === 0 && peakDistanceKm !== null) ||
        (summary.sampleCount > 0 && !finite(peakDistanceKm, 1, 20))) return null;
    sectors.push({
      direction: item.direction,
      azimuthCenterDegrees: item.azimuthCenterDegrees,
      ...summary,
      peakDistanceKm,
      relativeRadianceBand: summary.p90 == null ? null : relativeRadianceBand(summary.p90),
    });
  }
  const usable = sectors.filter((sector) => sector.sampleCount > 0);
  const dominant = usable.reduce((best, sector) => {
    if (best == null) return sector;
    if (sector.p90 > best.p90 ||
        (sector.p90 === best.p90 && sector.maximum > best.maximum) ||
        (sector.p90 === best.p90 && sector.maximum === best.maximum &&
          sector.sampleCount > best.sampleCount)) return sector;
    return best;
  }, null);
  if (dominant == null) {
    if (lightDomes.dominantDirection !== null || lightDomes.dominantAzimuthDegrees !== null) return null;
  } else if (lightDomes.dominantDirection !== dominant.direction ||
      lightDomes.dominantAzimuthDegrees !== dominant.azimuthCenterDegrees) return null;

  return {
    analysisVersion: spatialAnalysisVersion,
    maximumRadiusKm: 20,
    neighborhoods,
    lightDomes: {
      innerRadiusKm: 1,
      outerRadiusKm: 20,
      sectorCount: lightDomeDirections.length,
      dominantDirection: dominant?.direction ?? null,
      dominantAzimuthDegrees: dominant?.azimuthCenterDegrees ?? null,
      sectors,
    },
  };
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
    spatialAnalysis: null,
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
    const spatialAnalysis = validatedSpatialAnalysis(payload?.spatialAnalysis);
    if (!response.ok || payload?.status !== 'ready' || !finite(radiance, 0, 1_000_000) ||
        !Number.isInteger(datasetYear) || datasetYear < 2012 || datasetYear > 2100 ||
        datasetRevision.length === 0 ||
        (expectedDatasetRevision.length > 0 && datasetRevision !== expectedDatasetRevision) ||
        !finite(resolutionMeters, 1, 10_000) || spatialAnalysis == null ||
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
      spatialAnalysis,
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
      contractVersion: 3,
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
