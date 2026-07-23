import {
  interpolateDirectionalLight,
  interpolateTerrainHorizon,
} from './sky-site-assessment.mjs';
import { skyEphemeris } from './sky-ephemeris.mjs';

const stepMinutes = 15;
const stepMilliseconds = stepMinutes * 60 * 1_000;
const contractVersion = 1;
const algorithmVersion = 'sky-window-forecast.1';
const conditionOrder = Object.freeze({ unavailable: 0, insufficientData: 1, conditional: 2, favorable: 3 });
const criticalWeatherFields = Object.freeze([
  'totalCloudCoverPercent',
  'visibilityMeters',
  'precipitationProbabilityPercent',
  'precipitationMm',
]);

function finite(value, minimum = -Infinity, maximum = Infinity) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function coordinate(value) {
  return {
    latitude: Number(value.latitude.toFixed(5)),
    longitude: Number(value.longitude.toFixed(5)),
    system: 'wgs84',
  };
}

function exactUtc(value) {
  if (typeof value !== 'string' || value.length < 20 || value.length > 40 || !value.endsWith('Z')) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

export function validSkyWindowQuery(searchParams, now = new Date()) {
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  const start = exactUtc(searchParams.get('start'));
  const hours = Number(searchParams.get('hours') ?? 72);
  const locale = searchParams.get('locale') ?? 'zh-CN';
  if (!finite(latitude, -90, 90) || !finite(longitude, -180, 180) || start == null ||
      !Number.isInteger(hours) || hours < 6 || hours > 72 || !['zh-CN', 'en'].includes(locale)) return null;
  const delta = start.getTime() - now.getTime();
  if (delta < -30 * 60 * 1_000 || delta > 24 * 60 * 60 * 1_000) return null;
  return { latitude, longitude, startAt: start.toISOString(), hours, locale };
}

function sortedPoints(points) {
  if (!Array.isArray(points)) return [];
  return points.flatMap((point) => {
    const timestamp = Date.parse(point?.validAt ?? '');
    return Number.isFinite(timestamp) ? [{ ...point, timestamp }] : [];
  }).sort((a, b) => a.timestamp - b.timestamp);
}

function interpolateNumber(lower, upper, fraction, name, conservative = false) {
  const a = lower?.[name];
  const b = upper?.[name];
  if (!finite(a) && !finite(b)) return null;
  if (!finite(a)) return b;
  if (!finite(b)) return a;
  return conservative ? Math.max(a, b) : a + (b - a) * fraction;
}

function interpolatedWeather(points, timestamp) {
  if (points.length === 0) return null;
  let upperIndex = points.findIndex((point) => point.timestamp >= timestamp);
  if (upperIndex < 0) upperIndex = points.length - 1;
  const upper = points[upperIndex];
  const lower = points[Math.max(0, upperIndex - 1)];
  if (Math.min(Math.abs(timestamp - lower.timestamp), Math.abs(timestamp - upper.timestamp)) > 2 * 60 * 60 * 1_000) {
    return null;
  }
  const span = Math.max(1, upper.timestamp - lower.timestamp);
  const fraction = lower === upper ? 0 : Math.max(0, Math.min(1, (timestamp - lower.timestamp) / span));
  return {
    source: 'open-meteo-best-match',
    totalCloudCoverPercent: interpolateNumber(lower, upper, fraction, 'totalCloudCoverPercent'),
    lowCloudCoverPercent: interpolateNumber(lower, upper, fraction, 'lowCloudCoverPercent'),
    middleCloudCoverPercent: interpolateNumber(lower, upper, fraction, 'middleCloudCoverPercent'),
    highCloudCoverPercent: interpolateNumber(lower, upper, fraction, 'highCloudCoverPercent'),
    visibilityMeters: interpolateNumber(lower, upper, fraction, 'visibilityMeters'),
    precipitationProbabilityPercent: interpolateNumber(
      lower,
      upper,
      fraction,
      'precipitationProbabilityPercent',
      true,
    ),
    precipitationMm: interpolateNumber(lower, upper, fraction, 'precipitationMm', true),
    relativeHumidityPercent: interpolateNumber(lower, upper, fraction, 'relativeHumidityPercent'),
    windSpeedKmh: interpolateNumber(lower, upper, fraction, 'windSpeedKmh'),
    windGustKmh: interpolateNumber(lower, upper, fraction, 'windGustKmh', true),
  };
}

function rangeMidpoint(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null;
  const minimum = value.min;
  const maximum = value.max;
  if (finite(minimum) && finite(maximum)) return (minimum + maximum) / 2;
  if (finite(minimum)) return minimum;
  if (finite(maximum)) return maximum;
  return null;
}

function nearestSevenTimer(points, timestamp) {
  let nearest = null;
  for (const point of points) {
    const distance = Math.abs(point.timestamp - timestamp);
    if (nearest == null || distance < nearest.distance) nearest = { point, distance };
  }
  if (nearest == null || nearest.distance > 2 * 60 * 60 * 1_000) return null;
  const cloudCoverPercent = rangeMidpoint(nearest.point.cloudCover);
  return {
    source: '7timer',
    validAt: new Date(nearest.point.timestamp).toISOString(),
    cloudCoverPercent,
    seeingArcseconds: rangeMidpoint(nearest.point.seeing),
    transparencyMagPerAirmass: rangeMidpoint(nearest.point.transparency),
    humidityPercent: rangeMidpoint(nearest.point.humidity),
    sourceAgeStatus: nearest.point.sourceStatus ?? null,
  };
}

function weatherAgreement(weather, auxiliary) {
  if (weather?.totalCloudCoverPercent == null || auxiliary?.cloudCoverPercent == null) return 'unavailable';
  const difference = Math.abs(weather.totalCloudCoverPercent - auxiliary.cloudCoverPercent);
  if (difference <= 20) return 'aligned';
  if (difference <= 40) return 'mixed';
  return 'conflicting';
}

function atmosphereAssessment(weather) {
  if (weather == null || criticalWeatherFields.some((name) => weather[name] == null)) {
    return { status: 'unavailable', conditionBand: 'insufficientData', limitations: ['weather_forecast_unavailable'] };
  }
  const limitations = [];
  const hardBlocked = weather.precipitationMm > 0.1 ||
    weather.precipitationProbabilityPercent >= 60 ||
    weather.totalCloudCoverPercent >= 85 ||
    weather.visibilityMeters < 5_000 ||
    (weather.windGustKmh != null && weather.windGustKmh >= 50);
  if (weather.precipitationMm > 0.1 || weather.precipitationProbabilityPercent >= 60) {
    limitations.push('precipitation_likely');
  }
  if (weather.totalCloudCoverPercent >= 85) limitations.push('cloud_cover_blocking');
  else if (weather.totalCloudCoverPercent >= 50) limitations.push('cloud_cover_limited');
  if (weather.lowCloudCoverPercent != null && weather.lowCloudCoverPercent >= 50) {
    limitations.push('low_cloud_cover_limited');
  }
  if (weather.visibilityMeters < 5_000) limitations.push('visibility_poor');
  else if (weather.visibilityMeters < 15_000) limitations.push('visibility_limited');
  if (weather.relativeHumidityPercent != null && weather.relativeHumidityPercent >= 95) {
    limitations.push('humidity_very_high');
  }
  if (weather.windGustKmh != null && weather.windGustKmh >= 50) limitations.push('wind_gust_blocking');
  else if (weather.windGustKmh != null && weather.windGustKmh >= 35) limitations.push('wind_gust_limited');
  const conditional = limitations.some((item) => [
    'cloud_cover_limited', 'low_cloud_cover_limited', 'visibility_limited',
    'humidity_very_high', 'wind_gust_limited',
  ].includes(item));
  return {
    status: 'ready',
    conditionBand: hardBlocked ? 'unavailable' : conditional ? 'conditional' : 'favorable',
    limitations,
  };
}

function evaluatePoint({ timestamp, query, horizon, nightSkyBackground, weather, auxiliary }) {
  const observedAt = new Date(timestamp);
  const elevationMeters = horizon?.observer?.elevationMeters ?? 0;
  const ephemeris = skyEphemeris({
    latitude: query.latitude,
    longitude: query.longitude,
    elevationMeters,
    observedAt,
    horizon,
  });
  const limitations = [];
  const atmosphere = atmosphereAssessment(weather);
  limitations.push(...atmosphere.limitations);
  if (ephemeris == null) limitations.push('ephemeris_unavailable');
  const galacticCenter = ephemeris?.galacticCenter ?? null;
  const terrain = galacticCenter == null ? null : interpolateTerrainHorizon(horizon, galacticCenter.azimuthDegrees);
  const terrainClearanceDegrees = terrain == null || galacticCenter == null
    ? null
    : galacticCenter.altitudeDegrees - terrain.horizonAltitudeDegrees;
  const directionalLight = galacticCenter == null || nightSkyBackground?.status !== 'ready'
    ? null
    : interpolateDirectionalLight(nightSkyBackground.spatialAnalysis, galacticCenter.azimuthDegrees);

  if (ephemeris != null && !ephemeris.astronomicalNight) limitations.push('not_astronomical_night');
  if (galacticCenter != null && galacticCenter.altitudeDegrees <= 0) {
    limitations.push('galactic_center_below_geometric_horizon');
  }
  if (terrain == null) limitations.push('terrain_horizon_unavailable');
  else {
    if (terrain.coverageRatio == null || terrain.coverageRatio < 0.7) limitations.push('terrain_coverage_limited');
    if (terrainClearanceDegrees <= 0) limitations.push('galactic_center_terrain_blocked');
    else if (terrainClearanceDegrees < 3) limitations.push('terrain_clearance_limited');
  }
  if (directionalLight == null) limitations.push('directional_light_pollution_unavailable');
  else {
    if (directionalLight.coverageRatio == null || directionalLight.coverageRatio < 0.7) {
      limitations.push('light_pollution_coverage_limited');
    }
    if (['bright', 'veryBright'].includes(directionalLight.relativeRadianceBand)) {
      limitations.push('directional_light_pollution_high');
    } else if (directionalLight.relativeRadianceBand === 'moderate') {
      limitations.push('directional_light_pollution_moderate');
    }
  }
  const moon = ephemeris?.moon ?? null;
  if (moon?.interferenceBand === 'high') limitations.push('moon_interference_high');
  else if (moon?.interferenceBand === 'moderate') limitations.push('moon_interference_moderate');
  const agreement = weatherAgreement(weather, auxiliary);
  if (agreement === 'conflicting') limitations.push('forecast_sources_conflicting');
  else if (agreement === 'mixed') limitations.push('forecast_sources_mixed');
  if (auxiliary?.transparencyMagPerAirmass != null && auxiliary.transparencyMagPerAirmass >= 0.85) {
    limitations.push('seven_timer_transparency_limited');
  }
  if (auxiliary?.seeingArcseconds != null && auxiliary.seeingArcseconds >= 2.5) {
    limitations.push('seven_timer_seeing_limited');
  }

  let conditionBand;
  const hardUnavailable = atmosphere.conditionBand === 'unavailable' || ephemeris == null ||
    !ephemeris.astronomicalNight || galacticCenter.altitudeDegrees <= 0 ||
    (terrainClearanceDegrees != null && terrainClearanceDegrees <= 0);
  const insufficient = atmosphere.conditionBand === 'insufficientData' || terrain == null || directionalLight == null ||
    terrain.coverageRatio < 0.7 || directionalLight.coverageRatio < 0.7;
  const conditional = atmosphere.conditionBand === 'conditional' || terrainClearanceDegrees < 3 ||
    ['moderate', 'bright', 'veryBright'].includes(directionalLight?.relativeRadianceBand) ||
    ['moderate', 'high'].includes(moon?.interferenceBand) ||
    ['mixed', 'conflicting'].includes(agreement) ||
    limitations.includes('seven_timer_transparency_limited');
  if (hardUnavailable) conditionBand = 'unavailable';
  else if (insufficient) conditionBand = 'insufficientData';
  else if (conditional) conditionBand = 'conditional';
  else conditionBand = 'favorable';

  return {
    observedAt: observedAt.toISOString(),
    conditionBand,
    geometry: ephemeris == null ? null : {
      astronomicalNight: ephemeris.astronomicalNight,
      sun: ephemeris.sun,
      galacticCenter,
    },
    terrain: terrain == null ? { status: horizon?.status ?? 'unavailable' } : {
      status: 'ready',
      horizonAltitudeDegrees: terrain.horizonAltitudeDegrees,
      clearanceDegrees: terrainClearanceDegrees,
      obstructionDistanceKm: terrain.obstructionDistanceKm,
      obstructionElevationMeters: terrain.obstructionElevationMeters,
      coverageRatio: terrain.coverageRatio,
    },
    moon,
    atmosphere: { ...weather, ...atmosphere },
    auxiliary: {
      sevenTimer: auxiliary,
      weatherAgreement: agreement,
    },
    lightPollution: directionalLight == null
      ? { status: nightSkyBackground?.status ?? 'unavailable' }
      : { status: 'ready', ...directionalLight },
    limitations: [...new Set(limitations)],
  };
}

function pointQuality(point) {
  let value = conditionOrder[point.conditionBand] * 100;
  value -= (point.atmosphere?.totalCloudCoverPercent ?? 100) * 0.35;
  value += Math.min(30, (point.atmosphere?.visibilityMeters ?? 0) / 1_000);
  value += Math.max(-20, Math.min(20, point.terrain?.clearanceDegrees ?? -20));
  if (point.moon?.interferenceBand === 'low') value += 12;
  if (point.moon?.interferenceBand === 'high') value -= 20;
  if (point.lightPollution?.relativeRadianceBand === 'veryDark') value += 12;
  if (point.lightPollution?.relativeRadianceBand === 'bright') value -= 15;
  if (point.lightPollution?.relativeRadianceBand === 'veryBright') value -= 25;
  return value;
}

function summarizeWindow(points, index) {
  const peak = points.reduce((best, point) => pointQuality(point) > pointQuality(best) ? point : best);
  const counts = Object.fromEntries(Object.keys(conditionOrder).map((band) => [
    band,
    points.filter((point) => point.conditionBand === band).length,
  ]));
  const conditionBand = counts.favorable > 0 ? 'favorable' : 'conditional';
  const endAt = new Date(Date.parse(points.at(-1).observedAt) + stepMilliseconds).toISOString();
  const primaryReasons = peak.limitations.slice(0, 4);
  return {
    id: `sky_window_${index + 1}`,
    startAt: points[0].observedAt,
    endAt,
    peakAt: peak.observedAt,
    conditionBand,
    sampleCount: points.length,
    favorableSamples: counts.favorable,
    conditionalSamples: counts.conditional,
    peakAssessment: peak,
    primaryReasons,
    _quality: pointQuality(peak) + points.length,
  };
}

function buildWindows(points) {
  const groups = [];
  let active = [];
  for (const point of points) {
    if (['favorable', 'conditional'].includes(point.conditionBand)) {
      active.push(point);
    } else if (active.length > 0) {
      if (active.length >= 2) groups.push(active);
      active = [];
    }
  }
  if (active.length >= 2) groups.push(active);
  const ranked = groups.map(summarizeWindow).sort((a, b) => b._quality - a._quality);
  const selected = ranked.slice(0, 8).sort((a, b) => Date.parse(a.startAt) - Date.parse(b.startAt));
  for (const window of selected) delete window._quality;
  const best = ranked[0];
  return { windows: selected, bestWindowId: best == null ? null : selected.find((item) => item.peakAt === best.peakAt)?.id ?? null };
}

function confidence({ horizon, nightSkyBackground, weatherResult, sevenTimerResult, calibration, points }) {
  const missingSources = [];
  if (horizon?.status !== 'ready') missingSources.push('terrain_horizon');
  if (nightSkyBackground?.status !== 'ready') missingSources.push('viirs_directional_light');
  if (!weatherResult.ok) missingSources.push('open_meteo_weather');
  if (!sevenTimerResult.ok) missingSources.push('seven_timer_auxiliary');
  const conflicts = [...new Set(points.flatMap((point) => point.limitations)
    .filter((item) => item === 'forecast_sources_conflicting'))];
  const criticalReady = !missingSources.some((item) => item !== 'seven_timer_auxiliary');
  const band = !criticalReady ? 'low' : conflicts.length > 0 || calibration.status !== 'ready' ? 'medium' : 'high';
  return {
    band,
    criticalSourcesReady: criticalReady,
    missingSources,
    conflicts,
  };
}

export class SkyWindowService {
  constructor({
    siteEnvironmentService,
    openMeteoForecast,
    sevenTimerService,
    calibrationStore,
    now = () => new Date(),
  }) {
    this.siteEnvironmentService = siteEnvironmentService;
    this.openMeteoForecast = openMeteoForecast;
    this.sevenTimerService = sevenTimerService;
    this.calibrationStore = calibrationStore;
    this.now = now;
  }

  async forecast(query) {
    const startAt = new Date(query.startAt);
    const endAt = new Date(startAt.getTime() + query.hours * 60 * 60 * 1_000);
    const [environment, weatherResult, sevenTimerResult] = await Promise.all([
      this.siteEnvironmentService.facts({
        latitude: query.latitude,
        longitude: query.longitude,
        includeSkyAssessment: true,
        observedAt: startAt.toISOString(),
      }),
      this.openMeteoForecast.forecast({
        latitude: query.latitude,
        longitude: query.longitude,
        hours: query.hours,
      }),
      this.sevenTimerService.forecast({
        latitude: query.latitude,
        longitude: query.longitude,
        product: 'astro',
      }).catch(() => ({ ok: false, error: 'unavailable' })),
    ]);
    const horizon = environment.terrainHorizon;
    const nightSkyBackground = environment.nightSkyBackground;
    const weatherPoints = sortedPoints(weatherResult.ok ? weatherResult.body.points : []);
    const sevenTimerPoints = sortedPoints(sevenTimerResult.ok ? sevenTimerResult.body.points : [])
      .map((point) => ({ ...point, sourceStatus: sevenTimerResult.body.sourceStatus }));
    const points = [];
    for (let timestamp = startAt.getTime(); timestamp <= endAt.getTime(); timestamp += stepMilliseconds) {
      points.push(evaluatePoint({
        timestamp,
        query,
        horizon,
        nightSkyBackground,
        weather: interpolatedWeather(weatherPoints, timestamp),
        auxiliary: nearestSevenTimer(sevenTimerPoints, timestamp),
      }));
    }
    const { windows, bestWindowId } = buildWindows(points);
    const calibration = this.calibrationStore.lookup(query);
    const instant = this.now();
    return {
      contractVersion,
      algorithmVersion,
      requestedCoordinate: coordinate(query),
      requestedStartAt: startAt.toISOString(),
      endAt: endAt.toISOString(),
      stepMinutes,
      generatedAt: instant.toISOString(),
      expiresAt: new Date(instant.getTime() + 15 * 60 * 1_000).toISOString(),
      current: points[0],
      windows,
      bestWindowId,
      confidence: confidence({
        horizon,
        nightSkyBackground,
        weatherResult,
        sevenTimerResult,
        calibration,
        points,
      }),
      calibration,
      sources: [
        weatherResult.ok ? {
          id: weatherResult.body.source,
          fetchedAt: weatherResult.body.fetchedAt,
          expiresAt: weatherResult.body.expiresAt,
          cacheStatus: weatherResult.body.cacheStatus,
          attribution: weatherResult.body.attribution,
          license: weatherResult.body.license,
        } : { id: 'open-meteo-best-match', status: weatherResult.error },
        sevenTimerResult.ok ? {
          id: '7timer-astro',
          fetchedAt: sevenTimerResult.body.fetchedAt,
          cacheStatus: sevenTimerResult.body.cacheStatus,
          sourceStatus: sevenTimerResult.body.sourceStatus,
        } : { id: '7timer-astro', status: sevenTimerResult.error },
        horizon?.source == null ? { id: 'copernicus-dem-glo30', status: horizon?.status ?? 'unavailable' } : {
          id: horizon.source.id,
          revision: horizon.source.revision,
          attribution: horizon.source.attribution,
        },
        nightSkyBackground?.source == null ? { id: 'eog-viirs', status: nightSkyBackground?.status ?? 'unavailable' } : {
          id: nightSkyBackground.source.id,
          revision: nightSkyBackground.source.revision,
          attribution: nightSkyBackground.source.attribution,
        },
        { id: 'astronomy-engine', version: '2.1.19', license: 'MIT' },
      ],
    };
  }
}
