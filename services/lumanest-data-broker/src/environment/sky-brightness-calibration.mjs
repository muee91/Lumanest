import { readFileSync } from 'node:fs';

const maximumCells = 200_000;
const maximumDistanceKm = 50;
const earthRadiusKm = 6371.0088;

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function boundedText(value, maximum) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= maximum
    ? value.trim()
    : null;
}

function radians(value) {
  return value * Math.PI / 180;
}

function distanceKm(latitudeA, longitudeA, latitudeB, longitudeB) {
  const deltaLatitude = radians(latitudeB - latitudeA);
  const deltaLongitude = radians(longitudeB - longitudeA);
  const a = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(latitudeA)) * Math.cos(radians(latitudeB)) *
      Math.sin(deltaLongitude / 2) ** 2;
  return 2 * earthRadiusKm * Math.asin(Math.min(1, Math.sqrt(a)));
}

function validatedBundle(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value) ||
      value.contractVersion !== 1 || !Array.isArray(value.cells) || value.cells.length > maximumCells) return null;
  const dataset = value.dataset;
  if (dataset == null || typeof dataset !== 'object' || Array.isArray(dataset)) return null;
  const id = boundedText(dataset.id, 120);
  const source = boundedText(dataset.source, 160);
  const attribution = boundedText(dataset.attribution, 240);
  const license = boundedText(dataset.license, 80);
  const generatedAt = new Date(dataset.generatedAt);
  if (id == null || source == null || attribution == null || license == null ||
      !Number.isFinite(generatedAt.getTime())) return null;
  const cells = [];
  for (const cell of value.cells) {
    if (cell == null || typeof cell !== 'object' || Array.isArray(cell) ||
        !finite(cell.latitude, -90, 90) || !finite(cell.longitude, -180, 180) ||
        !Number.isInteger(cell.sampleCount) || cell.sampleCount < 1 || cell.sampleCount > 10_000_000) continue;
    const sqmMedian = cell.sqmMedian == null ? null : finite(cell.sqmMedian, 10, 30) ? cell.sqmMedian : null;
    const limitingMagnitudeMedian = cell.limitingMagnitudeMedian == null
      ? null
      : finite(cell.limitingMagnitudeMedian, -2, 9) ? cell.limitingMagnitudeMedian : null;
    if (sqmMedian == null && limitingMagnitudeMedian == null) continue;
    const observedFrom = cell.observedFrom == null ? null : new Date(cell.observedFrom);
    const observedTo = cell.observedTo == null ? null : new Date(cell.observedTo);
    cells.push(Object.freeze({
      latitude: cell.latitude,
      longitude: cell.longitude,
      sampleCount: cell.sampleCount,
      sqmMedian,
      limitingMagnitudeMedian,
      observedFrom: observedFrom != null && Number.isFinite(observedFrom.getTime())
        ? observedFrom.toISOString()
        : null,
      observedTo: observedTo != null && Number.isFinite(observedTo.getTime())
        ? observedTo.toISOString()
        : null,
    }));
  }
  return Object.freeze({
    dataset: Object.freeze({ id, source, attribution, license, generatedAt: generatedAt.toISOString() }),
    cells: Object.freeze(cells),
  });
}

export class SkyBrightnessCalibrationStore {
  constructor({ status = 'unconfigured', bundle = null, error = null } = {}) {
    this.status = status;
    this.bundle = bundle;
    this.error = error;
  }

  static fromFile(path) {
    if (typeof path !== 'string' || path.trim().length === 0) return new SkyBrightnessCalibrationStore();
    try {
      const bundle = validatedBundle(JSON.parse(readFileSync(path.trim(), 'utf8')));
      return bundle == null
        ? new SkyBrightnessCalibrationStore({ status: 'unavailable', error: 'invalid_calibration_bundle' })
        : new SkyBrightnessCalibrationStore({ status: 'ready', bundle });
    } catch {
      return new SkyBrightnessCalibrationStore({ status: 'unavailable', error: 'calibration_bundle_unavailable' });
    }
  }

  lookup({ latitude, longitude }) {
    if (this.status !== 'ready' || this.bundle == null) {
      return {
        status: this.status,
        sampleCount: 0,
        sqmMedian: null,
        limitingMagnitudeMedian: null,
        distanceKm: null,
        source: null,
        limitation: this.error,
      };
    }
    let nearest = null;
    for (const cell of this.bundle.cells) {
      const distance = distanceKm(latitude, longitude, cell.latitude, cell.longitude);
      if (distance > maximumDistanceKm || cell.sampleCount < 3) continue;
      if (nearest == null || distance < nearest.distanceKm ||
          (distance === nearest.distanceKm && cell.sampleCount > nearest.cell.sampleCount)) {
        nearest = { cell, distanceKm: distance };
      }
    }
    if (nearest == null) {
      return {
        status: 'unavailable',
        sampleCount: 0,
        sqmMedian: null,
        limitingMagnitudeMedian: null,
        distanceKm: null,
        source: this.bundle.dataset,
        limitation: 'no_nearby_ground_calibration',
      };
    }
    return {
      status: 'ready',
      sampleCount: nearest.cell.sampleCount,
      sqmMedian: nearest.cell.sqmMedian,
      limitingMagnitudeMedian: nearest.cell.limitingMagnitudeMedian,
      distanceKm: nearest.distanceKm,
      observedFrom: nearest.cell.observedFrom,
      observedTo: nearest.cell.observedTo,
      source: this.bundle.dataset,
      limitation: nearest.distanceKm > 10 ? 'ground_calibration_distant' : null,
    };
  }
}

export { validatedBundle as validateSkyBrightnessCalibrationBundle };
