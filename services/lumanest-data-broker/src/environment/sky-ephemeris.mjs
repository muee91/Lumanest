import { apiErrorCodes } from '../api/error-codes.mjs';

import * as Astronomy from 'astronomy-engine';

import {
  equatorialToHorizontal,
  interpolateTerrainHorizon,
} from './sky-site-assessment.mjs';

const galacticCenterRightAscensionDegrees = 266.41683;
const galacticCenterDeclinationDegrees = -29.00781;
const ephemerisModelVersion = 'astronomy-engine-2.1.19';
const moonInterferenceModelVersion = 'moon-directional-interference.1';
const degreesToRadians = Math.PI / 180;
const radiansToDegrees = 180 / Math.PI;

function finite(value, minimum = -Infinity, maximum = Infinity) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function normalizeDegrees(value) {
  return ((value % 360) + 360) % 360;
}

function angularSeparation(a, b) {
  const altitudeA = a.altitudeDegrees * degreesToRadians;
  const altitudeB = b.altitudeDegrees * degreesToRadians;
  const azimuthDifference = (a.azimuthDegrees - b.azimuthDegrees) * degreesToRadians;
  const cosine = Math.sin(altitudeA) * Math.sin(altitudeB) +
    Math.cos(altitudeA) * Math.cos(altitudeB) * Math.cos(azimuthDifference);
  return Math.acos(Math.max(-1, Math.min(1, cosine))) * radiansToDegrees;
}

function horizontalBody(body, observedAt, observer) {
  const equatorial = Astronomy.Equator(body, observedAt, observer, true, true);
  const horizontal = Astronomy.Horizon(
    observedAt,
    observer,
    equatorial.ra,
    equatorial.dec,
    'normal',
  );
  return {
    azimuthDegrees: normalizeDegrees(horizontal.azimuth),
    altitudeDegrees: horizontal.altitude,
  };
}

function moonInterferenceBand({ illuminationFraction, altitudeDegrees, separationDegrees, terrainBlocked }) {
  if (terrainBlocked || altitudeDegrees <= -1) return 'low';
  const altitudeFactor = Math.max(0, Math.min(1, (altitudeDegrees + 1) / 35));
  const separationFactor = Math.max(0.15, 1 - Math.min(180, separationDegrees) / 180);
  const index = illuminationFraction * altitudeFactor * separationFactor;
  if (index < 0.12) return 'low';
  if (index < 0.35) return 'moderate';
  return 'high';
}

export function skyEphemeris({ latitude, longitude, elevationMeters = 0, observedAt, horizon = null }) {
  if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180) ||
      !finite(elevationMeters, -500, 9_000) || !(observedAt instanceof Date) ||
      !Number.isFinite(observedAt.getTime())) return null;
  try {
    const observer = new Astronomy.Observer(latitude, longitude, elevationMeters);
    const sun = horizontalBody(Astronomy.Body.Sun, observedAt, observer);
    const moon = horizontalBody(Astronomy.Body.Moon, observedAt, observer);
    const galacticCenter = equatorialToHorizontal({
      rightAscensionDegrees: galacticCenterRightAscensionDegrees,
      declinationDegrees: galacticCenterDeclinationDegrees,
      latitude,
      longitude,
      observedAt,
    });
    if (galacticCenter == null) return null;
    const illumination = Astronomy.Illumination(Astronomy.Body.Moon, observedAt);
    const moonTerrain = interpolateTerrainHorizon(horizon, moon.azimuthDegrees);
    const moonTerrainClearanceDegrees = moonTerrain == null
      ? null
      : moon.altitudeDegrees - moonTerrain.horizonAltitudeDegrees;
    const terrainBlocked = moonTerrainClearanceDegrees != null && moonTerrainClearanceDegrees <= 0;
    const separationDegrees = angularSeparation(moon, galacticCenter);
    const illuminationFraction = finite(illumination.phase_fraction, 0, 1)
      ? illumination.phase_fraction
      : null;
    if (illuminationFraction == null || !finite(illumination.phase_angle, 0, 180)) return null;
    return {
      modelVersion: ephemerisModelVersion,
      observedAt: observedAt.toISOString(),
      astronomicalNight: sun.altitudeDegrees <= -18,
      sun: {
        ...sun,
        modelVersion: ephemerisModelVersion,
      },
      galacticCenter: {
        azimuthDegrees: galacticCenter.azimuthDegrees,
        altitudeDegrees: galacticCenter.altitudeDegrees,
        modelVersion: 'iau-galactic-center-j2000.1',
      },
      moon: {
        ...moon,
        illuminationFraction,
        phaseAngleDegrees: illumination.phase_angle,
        apparentMagnitude: finite(illumination.mag, -30, 30) ? illumination.mag : null,
        angularSeparationFromGalacticCenterDegrees: separationDegrees,
        terrainStatus: moonTerrain == null ? horizon?.status ?? 'unavailable' : 'ready',
        terrainHorizonAltitudeDegrees: moonTerrain?.horizonAltitudeDegrees ?? null,
        terrainClearanceDegrees: moonTerrainClearanceDegrees,
        terrainBlocked,
        interferenceBand: moonInterferenceBand({
          illuminationFraction,
          altitudeDegrees: moon.altitudeDegrees,
          separationDegrees,
          terrainBlocked,
        }),
        interferenceModelVersion: moonInterferenceModelVersion,
        modelVersion: ephemerisModelVersion,
      },
    };
  } catch {
    return null;
  }
}

export const skyEphemerisVersion = ephemerisModelVersion;
