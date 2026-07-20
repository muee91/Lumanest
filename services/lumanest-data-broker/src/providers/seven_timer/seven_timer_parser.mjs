import {
  cloudCoverRanges,
  humidityRanges,
  mappedRange,
  meteoWindSpeedRanges,
  precipitationAmountRanges,
  seeingRanges,
  snowDepthRanges,
  transparencyRanges,
  windSpeedRanges,
} from './seven_timer_mappings.mjs';

const products = new Set(['astro', 'meteo', 'two']);
const missingStrings = new Set(['', '-9999']);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value) ? value : null;
}

function present(value) {
  if (value == null || value === -9999) return null;
  if (typeof value === 'string' && missingStrings.has(value.trim())) return null;
  return value;
}

function finite(value) {
  const normalized = present(value);
  return typeof normalized === 'number' && Number.isFinite(normalized) ? normalized : null;
}

function integer(value) {
  const normalized = finite(value);
  return Number.isInteger(normalized) ? normalized : null;
}

function text(value) {
  const normalized = present(value);
  return typeof normalized === 'string' && normalized.trim().length > 0
    ? normalized.trim()
    : null;
}

function parseSourceInit(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})(\d{2})(\d{2})(\d{2})$/.exec(value);
  if (match == null) return null;
  const [year, month, day, hour] = match.slice(1).map(Number);
  const date = new Date(Date.UTC(year, month - 1, day, hour));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day || date.getUTCHours() !== hour) return null;
  return date;
}

function sourceStatus(sourceInitAt, now) {
  const ageHours = Math.max(0, now.getTime() - sourceInitAt.getTime()) / 3_600_000;
  if (ageHours <= 9) return 'fresh';
  if (ageHours <= 15) return 'aging';
  return 'stale';
}

function validAt(sourceInitAt, raw) {
  const timepoint = integer(raw?.timepoint);
  if (timepoint == null || timepoint < 0) return null;
  return new Date(sourceInitAt.getTime() + timepoint * 3_600_000).toISOString();
}

function range(value, ranges, unit) {
  return mappedRange(integer(value), ranges, unit);
}

function wind(value, { numericDirection = false, ranges = windSpeedRanges } = {}) {
  const raw = object(value);
  if (raw == null) return null;
  const speed = range(raw.speed, ranges, 'mps');
  const direction = numericDirection ? finite(raw.direction) : text(raw.direction);
  const validDirection = numericDirection
    ? direction != null && direction >= 0 && direction <= 360 ? direction : null
    : direction;
  if (speed == null && validDirection == null) return null;
  return numericDirection
    ? { directionDegrees: validDirection, speed }
    : { direction: validDirection, speed };
}

function precipitationType(value) {
  return {
    none: 'none', rain: 'rain', snow: 'snow', frzr: 'freezing_rain', icep: 'ice_pellets',
  }[text(value)] ?? null;
}

function astroPoint(raw, sourceInitAt) {
  const value = object(raw);
  const at = validAt(sourceInitAt, value);
  if (value == null || at == null) return null;
  return {
    validAt: at,
    cloudCover: range(value.cloudcover, cloudCoverRanges, 'percent'),
    seeing: range(value.seeing, seeingRanges, 'arcsec'),
    transparency: range(value.transparency, transparencyRanges, 'mag_per_airmass'),
    humidity: range(value.rh2m, humidityRanges, 'percent'),
    wind: wind(value.wind10m),
    temperatureCelsius: finite(value.temp2m),
    liftedIndex: finite(value.lifted_index),
    precipitationType: precipitationType(value.prec_type),
  };
}

function humidityProfile(value) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const raw = object(entry);
    const layer = text(raw?.layer);
    const humidity = range(raw?.rh, humidityRanges, 'percent');
    return layer != null && /^\d{3}mb$/.test(layer) && humidity != null
      ? [{ layer, humidity }]
      : [];
  });
}

function windProfile(value) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const raw = object(entry);
    const layer = text(raw?.layer);
    const value = wind(raw, { numericDirection: true, ranges: meteoWindSpeedRanges });
    return layer != null && /^\d{3}mb$/.test(layer) && value != null
      ? [{ layer, ...value }]
      : [];
  });
}

function meteoPoint(raw, sourceInitAt) {
  const value = object(raw);
  const at = validAt(sourceInitAt, value);
  if (value == null || at == null) return null;
  const type = precipitationType(value.prec_type);
  const amount = range(value.prec_amount, precipitationAmountRanges, 'mm_per_hour');
  return {
    validAt: at,
    totalCloudCover: range(value.cloudcover, cloudCoverRanges, 'percent'),
    lowCloudCover: range(value.lowcloud, cloudCoverRanges, 'percent'),
    middleCloudCover: range(value.midcloud, cloudCoverRanges, 'percent'),
    highCloudCover: range(value.highcloud, cloudCoverRanges, 'percent'),
    humidityProfile: humidityProfile(value.rh_profile),
    windProfile: windProfile(value.wind_profile),
    pressureMslHpa: finite(value.msl_pressure),
    precipitation: type == null && amount == null ? null : { type, amount },
    snowDepth: range(value.snow_depth, snowDepthRanges, 'cm'),
  };
}

function twoPoint(raw, sourceInitAt) {
  const value = object(raw);
  const at = validAt(sourceInitAt, value);
  if (value == null || at == null) return null;
  const temperature = object(value.temp2m);
  return {
    validAt: at,
    cloudCover: range(value.cloudcover, cloudCoverRanges, 'percent'),
    temperatureMinCelsius: finite(temperature?.min),
    temperatureMaxCelsius: finite(temperature?.max),
    humidity: range(value.rh2m, humidityRanges, 'percent'),
    wind: wind(value.wind10m),
    liftedIndex: finite(value.lifted_index),
    weatherCode: text(value.weather),
  };
}

export function parseSevenTimerResponse(body, { product, now = new Date() }) {
  if (!products.has(product)) return { ok: false, error: 'invalid_product' };
  const root = object(body);
  if (root == null || root.product !== product || !Array.isArray(root.dataseries)) {
    return { ok: false, error: 'invalid_body' };
  }
  const sourceInitAt = parseSourceInit(root.init);
  if (sourceInitAt == null) return { ok: false, error: 'invalid_init' };
  const parser = { astro: astroPoint, meteo: meteoPoint, two: twoPoint }[product];
  const points = [];
  let previousTimepoint = -1;
  for (const entry of root.dataseries) {
    const timepoint = integer(object(entry)?.timepoint);
    if (timepoint == null || timepoint < 0 || timepoint <= previousTimepoint) continue;
    previousTimepoint = timepoint;
    const point = parser(entry, sourceInitAt);
    if (point != null) points.push(point);
  }
  if (points.length === 0) return { ok: false, error: 'empty_dataseries' };
  return {
    ok: true,
    value: {
      source: '7timer',
      product,
      sourceInitAt: sourceInitAt.toISOString(),
      sourceStatus: sourceStatus(sourceInitAt, now),
      points,
    },
  };
}
