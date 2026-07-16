import { createHash } from 'node:crypto';

import { createQWeatherJwt } from '../jwt.mjs';

const freshCacheMilliseconds = 5 * 60 * 1_000;
const staleCacheMilliseconds = 2 * 60 * 60 * 1_000;

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
    stale: observationAge > 30 * 60 * 1_000 || observationAge < -5 * 60 * 1_000,
  };
}

function normalizedForecast(hourlyBody, minutelyBody, fetchedAt) {
  const hourly = hourlyBody?.code === '200' && Array.isArray(hourlyBody.hourly)
    ? hourlyBody.hourly.slice(0, 3)
    : [];
  const minutely = minutelyBody?.code === '200' && Array.isArray(minutelyBody.minutely)
    ? minutelyBody.minutely.slice(0, 12)
    : [];
  const windSpeeds = hourly.map((item) => finite(item.windSpeed, 0, 540)).filter((value) => value != null);
  const precipitation = minutely.map((item) => finite(item.precip, 0, 500)).filter((value) => value != null);
  return {
    observedAt: fetchedAt.toISOString(),
    nextHourPrecipitationMm: precipitation.reduce((sum, value) => sum + value, 0),
    nextThreeHoursMaxWindSpeedMps: windSpeeds.length === 0 ? null : Math.max(...windSpeeds) / 3.6,
    thunderNextThreeHours: hourly.some((item) => thunderFromIcon(item.icon)),
  };
}

function normalizedAirQuality(body, fetchedAt) {
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

async function qweatherRequest({ host, path, location, token, fetcher, timeoutMs }) {
  const url = new URL(path, host);
  url.searchParams.set('location', location);
  const response = await fetcher(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.json();
  return response.ok ? body : null;
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
    return { ok: false, error: 'not_configured' };
  }
  const key = cacheKey(coordinate);
  const fetchedAt = now();
  const cached = await cache.get(key);
  const cachedAge = cached == null ? Number.POSITIVE_INFINITY : fetchedAt.getTime() - cached.cachedAt;
  if (cachedAge >= 0 && cachedAge <= freshCacheMilliseconds) {
    return { ok: true, body: cached.body, cache: 'fresh' };
  }

  try {
    const token = createQWeatherJwt({ privateKey, keyId, projectId, now: fetchedAt, ttlSeconds: 900 });
    const location = `${coordinate.longitude},${coordinate.latitude}`;
    const requests = await Promise.allSettled([
      qweatherRequest({ host, path: '/v7/weather/now', location, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: '/v7/weather/24h', location, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: '/v7/minutely/5m', location, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: '/v7/warning/now', location, token, fetcher, timeoutMs }),
      qweatherRequest({ host, path: '/v7/air/now', location, token, fetcher, timeoutMs }),
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
    if (cachedAge >= 0 && cachedAge <= staleCacheMilliseconds) {
      return {
        ok: true,
        body: {
          ...cached.body,
          weather: { ...cached.body.weather, stale: true, airQualityStale: true },
        },
        cache: 'stale',
      };
    }
    return { ok: false, error: 'upstream_unavailable' };
  }
}
