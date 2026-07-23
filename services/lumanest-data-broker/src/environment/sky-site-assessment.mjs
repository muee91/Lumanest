const degreesToRadians = Math.PI / 180;
const radiansToDegrees = 180 / Math.PI;
const galacticCenterRightAscensionDegrees = 266.41683;
const galacticCenterDeclinationDegrees = -29.00781;
const assessmentAlgorithmVersion = 'sky-site-assessment.1';
const galacticModelVersion = 'iau-galactic-center-j2000.1';
const solarModelVersion = 'solar-position-low-precision.1';

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

function julianDate(value) {
  return value.getTime() / 86_400_000 + 2_440_587.5;
}

function greenwichMeanSiderealDegrees(value) {
  const jd = julianDate(value);
  const centuries = (jd - 2_451_545.0) / 36_525;
  return normalizeDegrees(
    280.46061837 + 360.98564736629 * (jd - 2_451_545.0) +
    0.000387933 * centuries * centuries - centuries * centuries * centuries / 38_710_000,
  );
}

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
  const latitudeRadians = latitude * degreesToRadians;
  const declinationRadians = declinationDegrees * degreesToRadians;
  const hourAngleDegrees = signedDegrees(
    greenwichMeanSiderealDegrees(observedAt) + longitude - rightAscensionDegrees,
  );
  const hourAngleRadians = hourAngleDegrees * degreesToRadians;
  const altitudeRadians = Math.asin(
    Math.sin(latitudeRadians) * Math.sin(declinationRadians) +
    Math.cos(latitudeRadians) * Math.cos(declinationRadians) * Math.cos(hourAngleRadians),
  );
  const azimuthRadians = Math.atan2(
    Math.sin(hourAngleRadians),
    Math.cos(hourAngleRadians) * Math.sin(latitudeRadians) -
      Math.tan(declinationRadians) * Math.cos(latitudeRadians),
  );
  return {
    azimuthDegrees: normalizeDegrees(azimuthRadians * radiansToDegrees + 180),
    altitudeDegrees: altitudeRadians * radiansToDegrees,
    hourAngleDegrees,
  };
}

function solarEquatorial(observedAt) {
  const days = julianDate(observedAt) - 2_451_545.0;
  const meanAnomaly = normalizeDegrees(357.5291 + 0.98560028 * days);
  const meanAnomalyRadians = meanAnomaly * degreesToRadians;
  const equationOfCenter = 1.9148 * Math.sin(meanAnomalyRadians) +
    0.0200 * Math.sin(2 * meanAnomalyRadians) +
    0.0003 * Math.sin(3 * meanAnomalyRadians);
  const eclipticLongitude = normalizeDegrees(meanAnomaly + equationOfCenter + 180 + 102.9372);
  const longitudeRadians = eclipticLongitude * degreesToRadians;
  const obliquity = (23.4393 - 3.563e-7 * days) * degreesToRadians;
  return {
    rightAscensionDegrees: normalizeDegrees(
      Math.atan2(Math.sin(longitudeRadians) * Math.cos(obliquity), Math.cos(longitudeRadians)) *
        radiansToDegrees,
    ),
    declinationDegrees: Math.asin(
      Math.sin(obliquity) * Math.sin(longitudeRadians),
    ) * radiansToDegrees,
  };
}

export function astronomicalGeometry({ latitude, longitude, observedAt }) {
  const galacticCenter = equatorialToHorizontal({
    rightAscensionDegrees: galacticCenterRightAscensionDegrees,
    declinationDegrees: galacticCenterDeclinationDegrees,
    latitude,
    longitude,
    observedAt,
  });
  const sunEquatorial = solarEquatorial(observedAt);
  const sun = equatorialToHorizontal({
    ...sunEquatorial,
    latitude,
    longitude,
    observedAt,
  });
  if (galacticCenter == null || sun == null) return null;
  return {
    galacticCenter: {
      azimuthDegrees: galacticCenter.azimuthDegrees,
      altitudeDegrees: galacticCenter.altitudeDegrees,
      modelVersion: galacticModelVersion,
    },
    sun: {
      azimuthDegrees: sun.azimuthDegrees,
      altitudeDegrees: sun.altitudeDegrees,
      modelVersion: solarModelVersion,
    },
    astronomicalNight: sun.altitudeDegrees <= -18,
  };
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
