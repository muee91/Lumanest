import * as Astronomy from 'astronomy-engine';

const galacticCenterRightAscensionDegrees = 266.41683;
const galacticCenterDeclinationDegrees = -29.00781;
const assessmentAlgorithmVersion = 'sky-site-assessment.2';
const galacticModelVersion = 'iau-galactic-center-j2000.1';
const solarModelVersion = 'astronomy-engine-2.1.19';

function finite(value, minimum = -Infinity, maximum = Infinity) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function normalizeDegrees(value) {
  return ((value % 360) + 360) % 360;
}

function signedDegrees(value) {
  const normalized = normalizeDegrees(value);
  return normalized > 180 ? normalized - 360 : normalized;
}

function angularSeparationDegrees(a, b) {
  if (!finite(a) || !finite(b)) return null;
  return Math.abs(signedDegrees(a - b));
}

// Astronomy Engine is the sole owner of sidereal time and horizontal geometry.
// Galactic-center coordinates remain the fixed J2000 catalog values in this contract.
export function equatorialToHorizontal({
  rightAscensionDegrees,
  declinationDegrees,
  latitude,
  longitude,
  observedAt,
}) {
  if (!finite(rightAscensionDegrees, 0, 360) || !finite(declinationDegrees, -90, 90) ||
      !finite(latitude, -90, 90) || !finite(longitude, -180, 180) ||
      !(observedAt instanceof Date) || !Number.isFinite(observedAt.getTime())) return null;
  try {
    const observer = new Astronomy.Observer(latitude, longitude, 0);
    const horizontal = Astronomy.Horizon(
      observedAt, observer, rightAscensionDegrees / 15, declinationDegrees, 'none',
    );
    return {
      azimuthDegrees: normalizeDegrees(horizontal.azimuth),
      altitudeDegrees: horizontal.altitude,
      hourAngleDegrees: signedDegrees(
        Astronomy.SiderealTime(observedAt) * 15 + longitude - rightAscensionDegrees,
      ),
    };
  } catch {
    return null;
  }
}

export function horizontalBody(body, observedAt, observer) {
  const equatorial = Astronomy.Equator(body, observedAt, observer, true, true);
  const horizontal = Astronomy.Horizon(
    observedAt, observer, equatorial.ra, equatorial.dec, 'normal',
  );
  return {
    azimuthDegrees: normalizeDegrees(horizontal.azimuth),
    altitudeDegrees: horizontal.altitude,
  };
}

export function astronomicalGeometry({ latitude, longitude, observedAt }) {
  if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180) ||
      !(observedAt instanceof Date) || !Number.isFinite(observedAt.getTime())) return null;
  try {
    const observer = new Astronomy.Observer(latitude, longitude, 0);
    const galacticCenter = equatorialToHorizontal({
      rightAscensionDegrees: galacticCenterRightAscensionDegrees,
      declinationDegrees: galacticCenterDeclinationDegrees,
      latitude,
      longitude,
      observedAt,
    });
    const sun = horizontalBody(Astronomy.Body.Sun, observedAt, observer);
    if (galacticCenter == null) return null;
    return {
      galacticCenter: {
        azimuthDegrees: galacticCenter.azimuthDegrees,
        altitudeDegrees: galacticCenter.altitudeDegrees,
        modelVersion: galacticModelVersion,
      },
      sun: {
        ...sun,
        modelVersion: solarModelVersion,
      },
      astronomicalNight: sun.altitudeDegrees <= -18,
    };
  } catch {
    return null;
  }
}

function interpolatedValue(a, b, fraction) {
  if (!finite(a) && !finite(b)) return null;
  if (!finite(a)) return b;
  if (!finite(b)) return a;
  return a + (b - a) * fraction;
}

export function interpolateTerrainHorizon(horizon, azimuthDegrees) {
  if (horizon?.status !== 'ready' || !Array.isArray(horizon.samples) ||
      !Number.isInteger(horizon.azimuthStepDegrees) || horizon.azimuthStepDegrees <= 0 ||
      360 % horizon.azimuthStepDegrees !== 0) return null;
  const expectedLength = 360 / horizon.azimuthStepDegrees;
  if (horizon.samples.length !== expectedLength) return null;
  const position = normalizeDegrees(azimuthDegrees) / horizon.azimuthStepDegrees;
  const lowerIndex = Math.floor(position) % expectedLength;
  const upperIndex = (lowerIndex + 1) % expectedLength;
  const fraction = position - Math.floor(position);
  const lower = horizon.samples[lowerIndex];
  const upper = horizon.samples[upperIndex];
  const horizonAltitudeDegrees = interpolatedValue(
    lower?.horizonAltitudeDegrees,
    upper?.horizonAltitudeDegrees,
    fraction,
  );
  if (!finite(horizonAltitudeDegrees, -90, 90)) return null;
  return {
    horizonAltitudeDegrees,
    obstructionDistanceKm: interpolatedValue(
      lower?.obstructionDistanceKm,
      upper?.obstructionDistanceKm,
      fraction,
    ),
    obstructionElevationMeters: interpolatedValue(
      lower?.obstructionElevationMeters,
      upper?.obstructionElevationMeters,
      fraction,
    ),
    coverageRatio: interpolatedValue(lower?.coverageRatio, upper?.coverageRatio, fraction),
  };
}

function radianceBand(radiance) {
  if (!finite(radiance, 0, 1_000_000)) return null;
  if (radiance <= 0.15) return 'veryDark';
  if (radiance <= 0.5) return 'dark';
  if (radiance <= 2) return 'moderate';
  if (radiance <= 10) return 'bright';
  return 'veryBright';
}

export function interpolateDirectionalLight(spatialAnalysis, azimuthDegrees) {
  const lightDomes = spatialAnalysis?.lightDomes;
  if (!Array.isArray(lightDomes?.sectors) || lightDomes.sectors.length !== 8) return null;
  const position = normalizeDegrees(azimuthDegrees) / 45;
  const lowerIndex = Math.floor(position) % 8;
  const upperIndex = (lowerIndex + 1) % 8;
  const fraction = position - Math.floor(position);
  const lower = lightDomes.sectors[lowerIndex];
  const upper = lightDomes.sectors[upperIndex];
  const p90 = interpolatedValue(lower?.p90, upper?.p90, fraction);
  if (!finite(p90, 0, 1_000_000)) return null;
  const nearest = lightDomes.sectors[Math.round(position) % 8];
  return {
    direction: nearest.direction,
    azimuthDegrees: normalizeDegrees(azimuthDegrees),
    p90,
    relativeRadianceBand: radianceBand(p90),
    coverageRatio: interpolatedValue(lower?.coverageRatio, upper?.coverageRatio, fraction),
    dominantDirection: lightDomes.dominantDirection,
    dominantAzimuthDegrees: lightDomes.dominantAzimuthDegrees,
    dominantAngularSeparationDegrees: angularSeparationDegrees(
      azimuthDegrees,
      lightDomes.dominantAzimuthDegrees,
    ),
  };
}

export function createSkySiteAssessment({
  latitude,
  longitude,
  observedAt,
  horizon,
  nightSkyBackground,
}) {
  const geometry = astronomicalGeometry({ latitude, longitude, observedAt });
  if (geometry == null) {
    return {
      status: 'unavailable',
      conditionBand: 'insufficientData',
      algorithmVersion: assessmentAlgorithmVersion,
      observedAt: observedAt.toISOString(),
      geometry: null,
      terrain: { status: 'unavailable' },
      lightPollution: { status: 'unavailable' },
      limitations: ['astronomical_geometry_unavailable'],
    };
  }
  const terrainDirection = interpolateTerrainHorizon(
    horizon,
    geometry.galacticCenter.azimuthDegrees,
  );
  const directionalLight = nightSkyBackground?.status === 'ready'
    ? interpolateDirectionalLight(
        nightSkyBackground.spatialAnalysis,
        geometry.galacticCenter.azimuthDegrees,
      )
    : null;
  const terrainClearanceDegrees = terrainDirection == null
    ? null
    : geometry.galacticCenter.altitudeDegrees - terrainDirection.horizonAltitudeDegrees;
  const limitations = [];
  if (!geometry.astronomicalNight) limitations.push('not_astronomical_night');
  if (geometry.galacticCenter.altitudeDegrees <= 0) {
    limitations.push('galactic_center_below_geometric_horizon');
  }
  if (terrainDirection == null) limitations.push('terrain_horizon_unavailable');
  else {
    if (!finite(terrainDirection.coverageRatio, 0, 1) || terrainDirection.coverageRatio < 0.7) {
      limitations.push('terrain_coverage_limited');
    }
    if (terrainClearanceDegrees <= 0) limitations.push('galactic_center_terrain_blocked');
    else if (terrainClearanceDegrees < 3) limitations.push('terrain_clearance_limited');
  }
  if (directionalLight == null) limitations.push('directional_light_pollution_unavailable');
  else {
    if (!finite(directionalLight.coverageRatio, 0, 1) || directionalLight.coverageRatio < 0.7) {
      limitations.push('light_pollution_coverage_limited');
    }
    if (['bright', 'veryBright'].includes(directionalLight.relativeRadianceBand)) {
      limitations.push('directional_light_pollution_high');
    } else if (directionalLight.relativeRadianceBand === 'moderate') {
      limitations.push('directional_light_pollution_moderate');
    }
  }

  let conditionBand;
  if (!geometry.astronomicalNight || geometry.galacticCenter.altitudeDegrees <= 0 ||
      (terrainClearanceDegrees != null && terrainClearanceDegrees <= 0)) {
    conditionBand = 'unavailable';
  } else if (terrainDirection == null || directionalLight == null ||
      terrainDirection.coverageRatio < 0.7 || directionalLight.coverageRatio < 0.7) {
    conditionBand = 'insufficientData';
  } else if (terrainClearanceDegrees < 3 ||
      ['moderate', 'bright', 'veryBright'].includes(directionalLight.relativeRadianceBand)) {
    conditionBand = 'conditional';
  } else {
    conditionBand = 'favorable';
  }

  return {
    status: 'ready',
    conditionBand,
    algorithmVersion: assessmentAlgorithmVersion,
    observedAt: observedAt.toISOString(),
    geometry,
    terrain: terrainDirection == null
      ? { status: horizon?.status ?? 'unavailable' }
      : {
          status: 'ready',
          horizonAltitudeDegrees: terrainDirection.horizonAltitudeDegrees,
          clearanceDegrees: terrainClearanceDegrees,
          obstructionDistanceKm: terrainDirection.obstructionDistanceKm,
          obstructionElevationMeters: terrainDirection.obstructionElevationMeters,
          coverageRatio: terrainDirection.coverageRatio,
          sourceRevision: horizon.datasetRevision,
          algorithmVersion: horizon.algorithmVersion,
        },
    lightPollution: directionalLight == null
      ? { status: nightSkyBackground?.status ?? 'unavailable' }
      : { status: 'ready', ...directionalLight },
    limitations,
  };
}
