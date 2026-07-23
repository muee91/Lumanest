const horizonAlgorithmVersion = 'terrain-horizon-radial.1';
const horizonReadyTtlMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const horizonUnversionedTtlMilliseconds = 24 * 60 * 60 * 1_000;
const unavailableTtlMilliseconds = 15 * 60 * 1_000;
const unconfiguredTtlMilliseconds = 5 * 60 * 1_000;
const expectedAzimuthStepDegrees = 5;
const expectedSampleCount = 360 / expectedAzimuthStepDegrees;

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function exactObject(value, keys) {
  return value != null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
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

function boundedRevision(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._:-]{1,120}$/.test(value.trim())
    ? value.trim()
    : '';
}

function coordinate(point) {
  return {
    latitude: Number(point.latitude.toFixed(5)),
    longitude: Number(point.longitude.toFixed(5)),
    system: 'wgs84',
  };
}

function metadata(point, instant, ttlMilliseconds, cacheStatus = 'miss') {
  return {
    sampledCoordinate: coordinate(point),
    generatedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + ttlMilliseconds).toISOString(),
    cacheStatus,
  };
}

export function unavailableTerrainHorizon(status, point, instant, cacheStatus = 'miss') {
  const ttl = status === 'unconfigured' ? unconfiguredTtlMilliseconds : unavailableTtlMilliseconds;
  return {
    status,
    algorithmVersion: horizonAlgorithmVersion,
    datasetRevision: null,
    resolutionMeters: null,
    observer: null,
    azimuthStepDegrees: expectedAzimuthStepDegrees,
    maximumDistanceKm: 40,
    sampleSpacingMeters: null,
    refractionCoefficient: 0.13,
    coverageRatio: null,
    samples: [],
    ...metadata(point, instant, ttl, cacheStatus),
    source: null,
  };
}

function validatedHorizonPayload(payload, expectedDatasetRevision) {
  if (!exactObject(payload, [
    'status', 'algorithmVersion', 'datasetRevision', 'resolutionMeters', 'sourceId',
    'attribution', 'observer', 'azimuthStepDegrees', 'maximumDistanceKm',
    'sampleSpacingMeters', 'refractionCoefficient', 'coverageRatio', 'samples',
  ]) || payload.status !== 'ready' || payload.algorithmVersion !== horizonAlgorithmVersion) return null;
  const datasetRevision = boundedRevision(payload.datasetRevision);
  if (datasetRevision.length === 0 ||
      (expectedDatasetRevision.length > 0 && datasetRevision !== expectedDatasetRevision) ||
      !finite(payload.resolutionMeters, 1, 1_000) ||
      typeof payload.sourceId !== 'string' || payload.sourceId.length < 1 || payload.sourceId.length > 120 ||
      typeof payload.attribution !== 'string' || payload.attribution.length < 1 || payload.attribution.length > 240 ||
      payload.azimuthStepDegrees !== expectedAzimuthStepDegrees || payload.maximumDistanceKm !== 40 ||
      !finite(payload.sampleSpacingMeters, 30, 500) ||
      !finite(payload.refractionCoefficient, 0, 0.3) || !finite(payload.coverageRatio, 0, 1) ||
      !Array.isArray(payload.samples) || payload.samples.length !== expectedSampleCount) return null;
  const observer = payload.observer;
  if (!exactObject(observer, [
    'elevationMeters', 'sampledLatitude', 'sampledLongitude', 'heightMeters',
  ]) || !finite(observer.elevationMeters, -500, 9_000) ||
      !finite(observer.sampledLatitude, -90, 90) || !finite(observer.sampledLongitude, -180, 180) ||
      !finite(observer.heightMeters, 0, 20)) return null;
  const samples = [];
  for (let index = 0; index < expectedSampleCount; index += 1) {
    const item = payload.samples[index];
    if (!exactObject(item, [
      'azimuthDegrees', 'horizonAltitudeDegrees', 'obstructionDistanceKm',
      'obstructionElevationMeters', 'coverageRatio',
    ]) || item.azimuthDegrees !== index * expectedAzimuthStepDegrees ||
        !finite(item.coverageRatio, 0, 1)) return null;
    const absent = item.horizonAltitudeDegrees === null && item.obstructionDistanceKm === null &&
      item.obstructionElevationMeters === null;
    const present = finite(item.horizonAltitudeDegrees, -90, 90) &&
      finite(item.obstructionDistanceKm, 0.03, 40) &&
      finite(item.obstructionElevationMeters, -500, 9_000);
    if (!absent && !present) return null;
    samples.push({
      azimuthDegrees: item.azimuthDegrees,
      horizonAltitudeDegrees: item.horizonAltitudeDegrees,
      obstructionDistanceKm: item.obstructionDistanceKm,
      obstructionElevationMeters: item.obstructionElevationMeters,
      coverageRatio: item.coverageRatio,
    });
  }
  return {
    datasetRevision,
    resolutionMeters: payload.resolutionMeters,
    observer: {
      elevationMeters: observer.elevationMeters,
      sampledCoordinate: coordinate({
        latitude: observer.sampledLatitude,
        longitude: observer.sampledLongitude,
      }),
      heightMeters: observer.heightMeters,
    },
    azimuthStepDegrees: expectedAzimuthStepDegrees,
    maximumDistanceKm: 40,
    sampleSpacingMeters: payload.sampleSpacingMeters,
    refractionCoefficient: payload.refractionCoefficient,
    coverageRatio: payload.coverageRatio,
    samples,
    source: {
      id: payload.sourceId,
      revision: datasetRevision,
      attribution: payload.attribution,
    },
  };
}

export async function fetchTerrainHorizon({
  point,
  serviceUrl,
  serviceToken,
  expectedDatasetRevision,
  fetcher,
  timeoutMs,
  instant,
}) {
  const baseUrl = sanitizedBaseUrl(serviceUrl);
  if (baseUrl == null || typeof serviceToken !== 'string' || serviceToken.length === 0) {
    return unavailableTerrainHorizon('unconfigured', point, instant);
  }
  const url = new URL('/v1/dem/horizon', baseUrl);
  url.searchParams.set('latitude', String(point.latitude));
  url.searchParams.set('longitude', String(point.longitude));
  try {
    const response = await fetcher(url, {
      signal: AbortSignal.timeout(timeoutMs),
      headers: { Authorization: `Bearer ${serviceToken}` },
    });
    const payload = await response.json();
    const validated = response.ok
      ? validatedHorizonPayload(payload, expectedDatasetRevision)
      : null;
    if (validated == null) return unavailableTerrainHorizon('unavailable', point, instant);
    const ttl = expectedDatasetRevision.length > 0
      ? horizonReadyTtlMilliseconds
      : horizonUnversionedTtlMilliseconds;
    return {
      status: 'ready',
      algorithmVersion: horizonAlgorithmVersion,
      datasetRevision: validated.datasetRevision,
      resolutionMeters: validated.resolutionMeters,
      observer: validated.observer,
      azimuthStepDegrees: validated.azimuthStepDegrees,
      maximumDistanceKm: validated.maximumDistanceKm,
      sampleSpacingMeters: validated.sampleSpacingMeters,
      refractionCoefficient: validated.refractionCoefficient,
      coverageRatio: validated.coverageRatio,
      samples: validated.samples,
      ...metadata(validated.observer.sampledCoordinate, instant, ttl),
      source: validated.source,
    };
  } catch {
    return unavailableTerrainHorizon('unavailable', point, instant);
  }
}
