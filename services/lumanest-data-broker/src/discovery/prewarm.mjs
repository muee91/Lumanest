import { resolveSkyOpportunityCity } from '../domain/sky_opportunity/sky_opportunity_city_resolver.mjs';
import { forwardDiscovery } from './proxy.mjs';

const defaultRadiusMeters = 15_000;
const maximumRadiusMeters = 30_000;
const regionBriefMissionFocus = Object.freeze({
  popularPlaces: '摄影地点与观景地',
  hiddenPlaces: '小众地点与地方空间',
  humanityEvents: '近期活动、表演与市集',
  localStories: '区域身份、历史与地方故事',
  openingAndClosure: '场馆开放、闭馆与通行变化',
  seasonalSignals: '当前季节特征与摄影题材',
  localFoodAndSpecialties: '地方食物、特产与市场线索',
  culturalEtiquette: '当地文化礼仪与拍摄边界',
});

function validCoordinate(value) {
  return value != null && typeof value === 'object' && value.system === 'wgs84' &&
    typeof value.latitude === 'number' && Number.isFinite(value.latitude) &&
    typeof value.longitude === 'number' && Number.isFinite(value.longitude) &&
    value.latitude >= -90 && value.latitude <= 90 &&
    value.longitude >= -180 && value.longitude <= 180;
}

function enabledPolicies(value) {
  return Array.isArray(value) && value.some((policy) => policy?.enabled);
}

export function nearbyPrewarmRequest({ coordinate, locale, city, now = new Date(), radiusMeters = defaultRadiusMeters }) {
  if (!validCoordinate(coordinate) || !['zh-CN', 'en'].includes(locale) ||
      typeof city !== 'string' || city.trim().length === 0 || !Number.isFinite(now.getTime())) return null;
  const radius = Math.min(maximumRadiusMeters, Math.max(100, Math.round(radiusMeters)));
  const startsAt = now.toISOString();
  const endsAt = new Date(now.getTime() + 24 * 60 * 60 * 1_000).toISOString();
  const placeName = city.trim().slice(0, 80);
  return Object.freeze({
    activationType: 'foreground_opportunistic',
    missionType: 'popularPlaces',
    // City is resolved transiently by the Broker. The Discovery service stores
    // only its coarse grid centre in the queued job, never this input point.
    focus: locale === 'zh-CN'
      ? `${placeName}周边近期值得了解的摄影地点与观景地`
      : `Recent photography places and viewpoints around ${placeName}`,
    locale,
    region: {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      radiusMeters: radius,
    },
    timeRange: { startsAt, endsAt },
    routeCorridor: null,
    interests: ['photography'],
  });
}

export function regionBriefPrewarmRequests({
  coordinate,
  locale,
  city,
  now = new Date(),
  radiusMeters = defaultRadiusMeters,
}) {
  const popular = nearbyPrewarmRequest({ coordinate, locale, city, now, radiusMeters });
  if (popular == null) return [];
  const endsAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1_000).toISOString();
  const placeName = city.trim().slice(0, 80);
  return Object.entries(regionBriefMissionFocus).map(([missionType, focus]) => Object.freeze({
    ...popular,
    missionType,
    focus: locale === 'zh-CN'
      ? `${placeName}周边${focus}`
      : `Verified regional photography context around ${placeName}: ${missionType}`,
    timeRange: { startsAt: popular.timeRange.startsAt, endsAt },
  }));
}

/**
 * Starts a cache-first nearby discovery after a context refresh. This function
 * is intentionally fire-and-forget at its call site: a failed or unavailable
 * discovery provider must never delay the environment snapshot response.
 */
export async function prewarmNearbyDiscovery({
  coordinate,
  locale,
  amapWebKey,
  serviceUrl,
  internalToken,
  sourcePolicies,
  fetcher = fetch,
  timeoutMs = 8_000,
  now = () => new Date(),
  radiusMeters = defaultRadiusMeters,
  enabled = true,
  searchEnabled = true,
}) {
  if (!enabled || !searchEnabled || !validCoordinate(coordinate) || !enabledPolicies(sourcePolicies) || !serviceUrl || !internalToken) {
    return { queued: false, reason: 'not_configured' };
  }
  const city = await resolveSkyOpportunityCity({
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    amapWebKey,
    fetcher,
    timeoutMs: Math.min(timeoutMs, 5_000),
  });
  if (!city.ok || !city.requestedCity) return { queued: false, reason: 'city_unavailable' };
  const body = nearbyPrewarmRequest({
    coordinate,
    locale,
    city: city.requestedCity,
    now: now(),
    radiusMeters,
  });
  if (body == null) return { queued: false, reason: 'invalid_request' };
  const result = await forwardDiscovery({
    body,
    serviceUrl,
    internalToken,
    sourcePolicies,
    fetcher,
    timeoutMs,
  });
  return result.ok
    ? { queued: result.body.status !== 'ready', status: result.body.status }
    : { queued: false, reason: result.error };
}

/**
 * Schedules the complete Region Brief mission bundle after a context refresh.
 * Discovery's coarse-grid single-flight and per-mission cooldown absorb
 * repeated app refreshes; the Broker never persists the input coordinate.
 */
export async function prewarmRegionBriefDiscovery({
  coordinate,
  locale,
  amapWebKey,
  serviceUrl,
  internalToken,
  sourcePolicies,
  fetcher = fetch,
  timeoutMs = 8_000,
  now = () => new Date(),
  radiusMeters = defaultRadiusMeters,
  enabled = true,
  searchEnabled = true,
}) {
  if (!enabled || !searchEnabled || !validCoordinate(coordinate) ||
      !enabledPolicies(sourcePolicies) || !serviceUrl || !internalToken) {
    return { queued: false, reason: 'not_configured' };
  }
  const city = await resolveSkyOpportunityCity({
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    amapWebKey,
    fetcher,
    timeoutMs: Math.min(timeoutMs, 5_000),
  });
  if (!city.ok || !city.requestedCity) return { queued: false, reason: 'city_unavailable' };
  const requests = regionBriefPrewarmRequests({
    coordinate,
    locale,
    city: city.requestedCity,
    now: now(),
    radiusMeters,
  });
  if (requests.length === 0) return { queued: false, reason: 'invalid_request' };
  const results = await Promise.all(requests.map((body) => forwardDiscovery({
    body,
    serviceUrl,
    internalToken,
    sourcePolicies,
    fetcher,
    timeoutMs,
  })));
  const accepted = results.filter((result) => result.ok);
  if (accepted.length === 0) {
    return { queued: false, reason: results[0]?.error ?? 'upstream_unavailable' };
  }
  return {
    queued: accepted.some((result) => result.body.status !== 'ready'),
    acceptedMissions: accepted.length,
  };
}
