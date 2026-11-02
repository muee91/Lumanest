import { apiErrorCodes } from '../api/error-codes.mjs';

import { createHash } from 'node:crypto';

import { createQWeatherJwt } from '../jwt.mjs';

const freshCacheMilliseconds = 5 * 60 * 1_000;
const staleCacheMilliseconds = 2 * 60 * 60 * 1_000;

// QWeather refreshes `/v7/weather/now` roughly every 15 minutes, so a healthy
// observation is routinely 20+ minutes old by the time it reaches us. The
// previous 30-minute window treated a single missed upstream update as stale,
// which propagated into `ContextSnapshot.stale` and made the assistant reject
// every snapshot carrying a slightly lagging observation. This window absorbs
// routine upstream lag while still withholding genuinely old readings.
const observationStaleMilliseconds = 60 * 60 * 1_000;
const observationFutureToleranceMilliseconds = 5 * 60 * 1_000;

function finite(value, minimum, maximum) {
  const parsed = typeof value === 'string' ? Number.parseFloat(value) : value;
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum ? parsed : null;
}

function qweatherHost(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        (url.pathname !== '' && url.pathname !== '/') || url.search || url.hash ||
        !url.hostname.endsWith('.qweatherapi.com')) return null;
    return url;
  } catch {
    return null;
  }
}

function conditionFromIcon(value) {
  const code = Number.parseInt(value ?? '', 10);
  if (code === 100) return 'clear';
  if (code >= 101 && code <= 104) return 'cloudy';
  if (code >= 300 && code <= 399) return 'rain';
  if (code >= 400 && code <= 499) return 'snow';
  if (code === 507 || code === 508) return 'dust';
  return 'unknown';
}

function thunderFromIcon(value) {
  const code = Number.parseInt(value ?? '', 10);
  return code >= 302 && code <= 304;
}

function cacheKey(coordinate) {
  const cell = `${coordinate.latitude.toFixed(2)},${coordinate.longitude.toFixed(2)}`;
  return createHash('sha256').update(cell).digest('hex').slice(0, 24);
}

function warningSeverity(value) {
  const level = String(value ?? '').toLowerCase();
  if (level.includes('red') || level.includes('black') || level.includes('extreme') || level.includes('红') || level.includes('黑')) return 'critical';
  if (level.includes('orange') || level.includes('severe') || level.includes('橙')) return 'warning';
  if (level.includes('yellow') || level.includes('moderate') || level.includes('黄')) return 'caution';
  return 'info';
}

function boundedWarningText(value, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!normalized) return null;
  return [...normalized].slice(0, maximum).join('');
}

function warningGuidance(type, title, severity) {
  const signal = `${type ?? ''} ${title ?? ''}`.toLowerCase();
  const shared = ['关注当地气象部门的最新预警和现场管制信息。'];
  if (/雷|thunder|lightning/.test(signal)) {
    return ['远离制高点、水边、孤立树木和金属设备。', ...shared];
  }
  if (/台风|暴雨|rainstorm|洪|内涝|山洪/.test(signal)) {
    return ['避免进入低洼地、沟谷、涉水路段和临水机位。', ...shared];
  }
  if (/大风|wind|沙尘|dust/.test(signal)) {
    return ['停止无人机和高处架设，固定器材并避开危险树木和广告牌。', ...shared];
  }
  if (/高温|heat/.test(signal)) {
    return ['减少高温时段户外停留，补水并避开无阴影的暴晒区域。', ...shared];
  }
  if (/低温|寒潮|cold|冰冻|道路结冰/.test(signal)) {
    return ['注意保暖、防滑和道路结冰，不要单独进入偏远区域。', ...shared];
  }
  if (severity === 'critical') {
    return ['暂停非必要户外拍摄，优先前往安全地点。', ...shared];
  }
  return ['减少户外暴露，避开风险区域并留意环境变化。', ...shared];
}

function normalizedCurrent(body, fetchedAt) {
  if (body?.condition != null && body.temperature != null) {
    const value = body;
    const observedAt = new Date(value.observedAt ?? value.updateTime ?? fetchedAt);
    const temperature = finite(value.temperature?.value, -100, 100);
    const windSpeed = finite(value.wind?.speed?.value, 0, 200);
    const windDirection = finite(value.wind?.direction?.degree, 0, 359.999);
    const visibilityMeters = finite(value.visibility?.value, 0, 500_000);
    const precipitation = finite(value.precipitation?.amount?.value, 0, 2_000);
    if (temperature == null || windSpeed == null || windDirection == null ||
        visibilityMeters == null || precipitation == null) return null;
    const observationAge = fetchedAt.getTime() - observedAt.getTime();
    return {
      observedAt: observedAt.toISOString(),
      condition: conditionFromIcon(value.condition.code),
      temperatureCelsius: temperature,
      windSpeedMps: windSpeed,
      windDirectionDegrees: windDirection,
      precipitationMm: precipitation,
      visibilityKm: visibilityMeters / 1_000,
      cloudCoverPercent: finite(value.cloudCover, 0, 1) == null
        ? null
        : finite(value.cloudCover, 0, 1) * 100,
      thunder: thunderFromIcon(value.condition.code),
      stale: observationAge > observationStaleMilliseconds ||
        observationAge < -observationFutureToleranceMilliseconds,
    };
  }
  if (body?.code !== '200' || body.now == null || typeof body.now !== 'object') return null;
  const value = body.now;
  const observedAt = new Date(value.obsTime);
  const temperature = finite(value.temp, -100, 100);
  const windSpeedKph = finite(value.windSpeed, 0, 540);
  const windDirection = finite(value.wind360, 0, 359.999);
  const visibility = finite(value.vis, 0, 500);
  const precipitation = finite(value.precip, 0, 2_000);
  if (!Number.isFinite(observedAt.getTime()) || temperature == null || windSpeedKph == null ||
      visibility == null || precipitation == null) return null;
  const observationAge = fetchedAt.getTime() - observedAt.getTime();
  return {
    observedAt: observedAt.toISOString(),
    condition: conditionFromIcon(value.icon),
    temperatureCelsius: temperature,
    windSpeedMps: windSpeedKph / 3.6,
    windDirectionDegrees: windDirection,
    precipitationMm: precipitation,
    visibilityKm: visibility,
    cloudCoverPercent: finite(value.cloud, 0, 100),
    thunder: thunderFromIcon(value.icon),
    stale: observationAge > observationStaleMilliseconds ||
      observationAge < -observationFutureToleranceMilliseconds,
  };
}

function normalizedForecast(hourlyBody, minutelyBody, fetchedAt) {
  const hourly = Array.isArray(hourlyBody?.hours)
    ? hourlyBody.hours.slice(0, 24)
    : hourlyBody?.code === '200' && Array.isArray(hourlyBody.hourly)
      ? hourlyBody.hourly.slice(0, 24)
      : [];
  const minutely = minutelyBody?.code === '200' && Array.isArray(minutelyBody.minutely)
    ? minutelyBody.minutely.slice(0, 12)
    : [];
  const nextThreeHours = hourly.slice(0, 3);
  const windSpeeds = nextThreeHours
    .map((item) => {
      const value = finite(item.wind?.speed?.value ?? item.windSpeed, 0, 540);
      return value == null ? null : item.wind?.speed?.value == null ? value / 3.6 : value;
    })
    .filter((value) => value != null);
  const precipitation = minutely.map((item) => finite(item.precip, 0, 500)).filter((value) => value != null);
  return {
    observedAt: fetchedAt.toISOString(),
    nextHourPrecipitationMm: precipitation.reduce((sum, value) => sum + value, 0),
    nextThreeHoursMaxWindSpeedMps: windSpeeds.length === 0 ? null : Math.max(...windSpeeds),
    thunderNextThreeHours: nextThreeHours.some((item) =>
      thunderFromIcon(item.condition?.code ?? item.icon)),
    hourly: hourly.flatMap((item) => {
      const at = new Date(item.forecastTime ?? item.fxTime);
      const windSpeed = finite(item.wind?.speed?.value ?? item.windSpeed, 0, 540);
      const precipitationMm = finite(item.precipitation?.amount?.value ?? item.precip, 0, 2_000);
      if (!Number.isFinite(at.getTime()) || windSpeed == null) return [];
      return [{
        at: at.toISOString(), condition: conditionFromIcon(item.condition?.code ?? item.icon),
        cloudCoverPercent: finite(item.cloudCover, 0, 1) == null
          ? finite(item.cloud, 0, 100)
          : finite(item.cloudCover, 0, 1) * 100,
        windSpeedMps: item.wind?.speed?.value == null ? windSpeed / 3.6 : windSpeed,
        precipitationMm: precipitationMm ?? 0,
        visibilityKm: item.visibility?.value == null
          ? finite(item.vis, 0, 500)
          : finite(item.visibility.value, 0, 500_000) / 1_000,
        thunder: thunderFromIcon(item.condition?.code ?? item.icon),
      }];
    }),
  };
}

function normalizedAirQuality(body, fetchedAt) {
  if (Array.isArray(body?.indexes)) {
    const value = body.indexes.find((item) => finite(item?.aqi, 0, 500) != null) ?? null;
    const index = finite(value?.aqi, 0, 500);
    const category = typeof value?.category === 'string' && value.category.trim().length <= 40
      ? value.category.trim()
      : null;
    const primary = typeof value?.primaryPollutant?.name === 'string' &&
        value.primaryPollutant.name.trim().length <= 40
      ? value.primaryPollutant.name.trim()
      : null;
    return {
      airQualityIndex: index == null ? null : Math.round(index),
      airQualityCategory: category,
      primaryPollutant: primary,
      airQualityObservedAt: fetchedAt.toISOString(),
      airQualityStale: index == null,
    };
  }
  const value = body?.code === '200' && body.now != null && typeof body.now === 'object'
    ? body.now
    : null;
  if (value == null) {
    return {
      airQualityIndex: null,
      airQualityCategory: null,
      primaryPollutant: null,
      airQualityObservedAt: null,
      airQualityStale: true,
    };
  }
  const index = finite(value.aqi, 0, 500);
  const observedAt = new Date(value.pubTime ?? body.updateTime ?? fetchedAt);
  const category = typeof value.category === 'string' && value.category.trim().length <= 40
    ? value.category.trim()
    : null;
  const primary = typeof value.primary === 'string' && value.primary.trim().length <= 40 &&
      !['NA', 'N/A', '-'].includes(value.primary.trim().toUpperCase())
    ? value.primary.trim()
    : null;
  if (index == null || !Number.isFinite(observedAt.getTime())) {
    return {
      airQualityIndex: null,
      airQualityCategory: null,
      primaryPollutant: null,
      airQualityObservedAt: null,
      airQualityStale: true,
    };
  }
  const age = fetchedAt.getTime() - observedAt.getTime();
  return {
    airQualityIndex: Math.round(index),
    airQualityCategory: category,
    primaryPollutant: primary,
    airQualityObservedAt: observedAt.toISOString(),
    airQualityStale: age > 2 * 60 * 60 * 1_000 || age < -5 * 60 * 1_000,
  };
}

function normalizedWarnings(body, fetchedAt) {
  if (Array.isArray(body?.alerts)) {
    return body.alerts.flatMap((warning) => {
      const messageType = String(warning?.messageType?.code ?? '').toLowerCase();
      if (messageType === 'cancel') return [];
      const observedAt = new Date(warning?.issuedTime ?? warning?.effectiveTime ?? fetchedAt);
      const expiresAt = new Date(warning?.expireTime ?? fetchedAt.getTime() + 60 * 60 * 1_000);
      if (!Number.isFinite(observedAt.getTime()) || !Number.isFinite(expiresAt.getTime()) ||
          expiresAt <= fetchedAt) return [];
      const type = boundedWarningText(warning?.eventType?.name, 60);
      const title = boundedWarningText(warning?.headline ?? [type, '预警'].filter(Boolean).join(' '), 80)
        ?? '官方气象预警';
      const description = boundedWarningText(warning?.description, 500);
      const severity = warningSeverity(warning?.severity ?? warning?.color?.code);
      return [{
        id: createHash('sha256').update(String(warning?.id ?? title)).digest('hex').slice(0, 12),
        observedAt: observedAt.toISOString(),
        expiresAt: expiresAt.toISOString(),
        severity,
        title,
        description,
        guidance: (() => {
          const instruction = boundedWarningText(warning?.instruction, 500);
          return instruction == null
            ? warningGuidance(type, title, severity)
            : [...instruction.split(/\n+/u).slice(0, 3),
              '关注当地气象部门的最新预警和现场管制信息。'];
        })(),
      }];
    }).slice(0, 8);
  }
  if (body?.code !== '200' || !Array.isArray(body.warning)) return [];
  return body.warning.flatMap((warning) => {
    if (String(warning.status ?? '').toLowerCase() === 'cancel') return [];
    const observedAt = new Date(warning.pubTime ?? warning.startTime ?? fetchedAt);
    const expiresAt = new Date(warning.endTime ?? fetchedAt.getTime() + 60 * 60 * 1_000);
    if (!Number.isFinite(observedAt.getTime()) || !Number.isFinite(expiresAt.getTime()) ||
        expiresAt <= fetchedAt) return [];
    const rawId = String(warning.id ?? warning.title ?? `${observedAt.toISOString()}-${warning.type ?? ''}`);
    const type = boundedWarningText(warning.typeName ?? warning.type, 60);
    const level = boundedWarningText(warning.level, 20);
    const title = boundedWarningText(
      warning.title ?? [type, level, '预警'].filter(Boolean).join(' '),
      80,
    ) ?? '官方气象预警';
    const description = boundedWarningText(warning.text ?? warning.description, 500);
    const severity = warningSeverity(warning.level);
    return [{
      id: createHash('sha256').update(rawId).digest('hex').slice(0, 12),
      observedAt: observedAt.toISOString(),
      expiresAt: expiresAt.toISOString(),
      severity,
      title,
      description,
      guidance: warningGuidance(type, title, severity),
    }];
  }).slice(0, 8);
}

function hasCurrentWarningContract(body) {
  return body != null && typeof body === 'object' &&
    Array.isArray(body.officialWarnings) && body.officialWarnings.every((warning) =>
      warning != null && typeof warning === 'object' &&
      boundedWarningText(warning.title, 80) != null,
    );
}

function staleCachedBody(body) {
  if (body == null || typeof body !== 'object' || body.weather == null ||
      typeof body.weather !== 'object') return null;
  const warnings = Array.isArray(body.officialWarnings) ? body.officialWarnings : [];
  return {
    ...body,
    weather: { ...body.weather, stale: true, airQualityStale: true },
    officialWarnings: warnings.flatMap((warning) => {
      if (warning == null || typeof warning !== 'object') return [];
      return [{
        ...warning,
        title: boundedWarningText(warning.title, 80) ?? '官方气象预警',
      }];
    }),
  };
}

async function qweatherRequest({ host, path, location, query = {}, token, fetcher, timeoutMs }) {
  const url = new URL(path, host);
  if (location != null) url.searchParams.set('location', location);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, String(value));
  const response = await fetcher(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(timeoutMs),
  });
  let body;
  try {
    body = await response.json();
  } catch {
    return null;
  }
  return response.ok ? body : null;
}

function coordinatePath(coordinate) {
  return `${coordinate.latitude.toFixed(2)}/${coordinate.longitude.toFixed(2)}`;
}

export async function authoritativeWeather({
  coordinate,
  apiHost,
  privateKey,
  keyId,
  projectId,
  cache,
  fetcher = fetch,
  now = () => new Date(),
  timeoutMs = 10_000,
}) {
  const host = qweatherHost(apiHost);
  if (host == null || privateKey == null || !keyId || !projectId) {
    return { ok: false, error: apiErrorCodes.notConfigured };
  }
  const key = cacheKey(coordinate);
  const fetchedAt = now();
  const cached = await cache.get(key);
  const cachedAge = cached == null ? Number.POSITIVE_INFINITY : fetchedAt.getTime() - cached.cachedAt;
  if (cachedAge >= 0 && cachedAge <= freshCacheMilliseconds &&
      hasCurrentWarningContract(cached.body)) {
    return { ok: true, body: cached.body, cache: 'fresh' };
  }

  try {
    const token = createQWeatherJwt({ privateKey, keyId, projectId, now: fetchedAt, ttlSeconds: 900 });
    const location = `${coordinate.longitude},${coordinate.latitude}`;
    const path = coordinatePath(coordinate);
    const requests = await Promise.allSettled([
      qweatherRequest({ host, path: `/weather/v1/current/${path}`, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: `/weather/v1/hourly/${path}`, query: { hours: 24 }, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: '/v7/minutely/5m', location, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: `/weatheralert/v1/current/${path}`, query: { localTime: false }, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: `/airquality/v1/current/${path}`, token, fetcher, timeoutMs }),
    ]);
    const current = requests[0].status === 'fulfilled'
      ? normalizedCurrent(requests[0].value, fetchedAt)
      : null;
    if (current == null) throw new Error('current_weather_unavailable');
    const body = {
      weather: {
        ...current,
        ...normalizedAirQuality(
          requests[4].status === 'fulfilled' ? requests[4].value : null,
          fetchedAt,
        ),
      },
      forecast: normalizedForecast(
        requests[1].status === 'fulfilled' ? requests[1].value : null,
        requests[2].status === 'fulfilled' ? requests[2].value : null,
        fetchedAt,
      ),
      officialWarnings: normalizedWarnings(
        requests[3].status === 'fulfilled' ? requests[3].value : null,
        fetchedAt,
      ),
    };
    await cache.set(key, { cachedAt: fetchedAt.getTime(), body });
    return { ok: true, body, cache: 'miss' };
  } catch {
    const staleBody = staleCachedBody(cached?.body);
    if (cachedAge >= 0 && cachedAge <= staleCacheMilliseconds && staleBody != null) {
      return {
        ok: true,
        body: staleBody,
        cache: 'stale',
      };
    }
    return { ok: false, error: apiErrorCodes.upstreamUnavailable };
  }
}
