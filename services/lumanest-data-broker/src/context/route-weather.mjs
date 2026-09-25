import { apiErrorCodes } from '../api/error-codes.mjs';

import { buildRouteCorridorIntelligence } from './route-corridor-intelligence.mjs';

const maximumRouteWeatherSamples = 5;
const maximumForecastDeltaMilliseconds = 90 * 60 * 1_000;
const maximumForecastHorizonMilliseconds = 24 * 60 * 60 * 1_000;
const allowedRouteWeatherKeys = new Set(['routeId', 'samples']);
const allowedRouteWeatherSampleKeys = new Set([
  'latitude', 'longitude', 'system', 'expectedAt', 'progress',
]);

function exactKeys(value, allowed) {
  return value != null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function validFinite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

export function validRouteWeatherRequest(body, observedAt = new Date()) {
  if (!exactKeys(body, allowedRouteWeatherKeys) ||
      typeof body.routeId !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(body.routeId) ||
      !Array.isArray(body.samples) || body.samples.length < 2 ||
      body.samples.length > maximumRouteWeatherSamples) return false;
  const now = observedAt.getTime();
  if (!Number.isFinite(now)) return false;
  let previousProgress = -1;
  for (const sample of body.samples) {
    if (!exactKeys(sample, allowedRouteWeatherSampleKeys) || sample.system !== 'wgs84' ||
        !validFinite(sample.latitude, -90, 90) ||
        !validFinite(sample.longitude, -180, 180) ||
        !validFinite(sample.progress, 0, 1) || sample.progress <= previousProgress ||
        typeof sample.expectedAt !== 'string') return false;
    const expectedAt = new Date(sample.expectedAt).getTime();
    if (!Number.isFinite(expectedAt) || expectedAt < now - 15 * 60 * 1_000 ||
        expectedAt > now + maximumForecastHorizonMilliseconds) return false;
    previousProgress = sample.progress;
  }
  return true;
}

function closestHourlyForecast(hourly, expectedAt) {
  if (!Array.isArray(hourly)) return null;
  let closest = null;
  let closestDelta = Number.POSITIVE_INFINITY;
  for (const forecast of hourly) {
    if (forecast == null || typeof forecast !== 'object') continue;
    const forecastAt = new Date(forecast.at).getTime();
    if (!Number.isFinite(forecastAt)) continue;
    const delta = Math.abs(forecastAt - expectedAt.getTime());
    if (delta < closestDelta) {
      closest = forecast;
      closestDelta = delta;
    }
  }
  return closestDelta <= maximumForecastDeltaMilliseconds ? closest : null;
}

function sanitizedSample(sample, weather) {
  if (!weather?.ok) return null;
  const expectedAt = new Date(sample.expectedAt);
  const forecast = closestHourlyForecast(weather.body?.forecast?.hourly, expectedAt);
  if (forecast == null || typeof forecast.condition !== 'string' ||
      typeof forecast.windSpeedMps !== 'number' ||
      typeof forecast.precipitationMm !== 'number') return null;
  const forecastAt = new Date(forecast.at);
  if (!Number.isFinite(forecastAt.getTime())) return null;
  return {
    progress: sample.progress,
    expectedAt: expectedAt.toISOString(),
    forecastAt: forecastAt.toISOString(),
    condition: forecast.condition,
    cloudCoverPercent: typeof forecast.cloudCoverPercent === 'number' ? forecast.cloudCoverPercent : null,
    windSpeedMps: forecast.windSpeedMps,
    precipitationMm: forecast.precipitationMm,
    visibilityKm: typeof forecast.visibilityKm === 'number' ? forecast.visibilityKm : null,
    thunder: forecast.thunder === true,
    stale: weather.cache === 'stale',
  };
}

export async function routeWeatherForecast({
  body,
  fetchWeather,
  fetchCorridorFacts = null,
  observe = null,
  now = () => new Date(),
}) {
  const generatedAt = now();
  const results = await Promise.all(body.samples.map(async (sample) => {
    const [weather, corridor] = await Promise.all([
      Promise.resolve().then(() => fetchWeather({ latitude: sample.latitude, longitude: sample.longitude })).catch(() => null),
      typeof fetchCorridorFacts === 'function'
        ? Promise.resolve().then(() => fetchCorridorFacts(sample)).catch(() => null)
        : Promise.resolve(null),
    ]);
    return { weather: sanitizedSample(sample, weather), corridor };
  }));
  const samples = results.map((item) => item.weather).filter((sample) => sample != null);
  if (samples.length === 0) return { ok: false, error: apiErrorCodes.upstreamUnavailable };
  const corridor = buildRouteCorridorIntelligence({
    body,
    providerResults: results.map((item) => item.corridor),
    generatedAt,
  });
  if (typeof observe === 'function') observe(corridor);
  return {
    ok: true,
    body: {
      routeId: body.routeId,
      generatedAt: generatedAt.toISOString(),
      source: 'QWeather',
      coverage: samples.length === body.samples.length ? 'full' : 'partial',
      requestedSamples: body.samples.length,
      availableSamples: samples.length,
      samples,
      corridor,
    },
  };
}
