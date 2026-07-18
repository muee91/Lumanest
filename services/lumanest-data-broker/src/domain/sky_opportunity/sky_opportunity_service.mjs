import { createHash } from 'node:crypto';

import { SunsetBotCircuitBreaker } from '../../infrastructure/circuit_breaker/sunsetbot_circuit_breaker.mjs';
import { MemorySkyOpportunityCache } from '../../infrastructure/cache/sky_opportunity_cache.mjs';
import { SkyOpportunityMetrics } from '../../infrastructure/metrics/sky_opportunity_metrics.mjs';
import { SunsetBotClient } from '../../providers/sunsetbot/sunsetbot_client.mjs';
import { sunsetBotConfig } from '../../providers/sunsetbot/sunsetbot_config.mjs';
import { SunsetBotProvider, mapEventCode } from '../../providers/sunsetbot/sunsetbot_provider.mjs';
import { aggregateSkyOpportunity } from './sky_opportunity_aggregator.mjs';
import { resolveSkyOpportunityCity } from './sky_opportunity_city_resolver.mjs';

export function validSkyOpportunityQuery(searchParams) {
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  const eventType = searchParams.get('event');
  const dayOffset = Number(searchParams.get('dayOffset'));
  const locale = searchParams.get('locale') ?? 'zh-CN';
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      !['sunrise', 'sunset'].includes(eventType) || ![0, 1].includes(dayOffset) ||
      !['zh-CN', 'en'].includes(locale)) return null;
  return { latitude, longitude, eventType, dayOffset, locale };
}

export function validDailySkyOpportunityQuery(searchParams) {
  const latitude = Number(searchParams.get('lat'));
  const longitude = Number(searchParams.get('lon'));
  const locale = searchParams.get('locale') ?? 'zh-CN';
  const focus = searchParams.get('focus');
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      !['zh-CN', 'en'].includes(locale) || !['next', 'preSunrise'].includes(focus)) return null;
  return { latitude, longitude, locale, focus };
}

function cacheKey(city, eventCode, eventDate, model) {
  return `sunsetbot:${city}:${eventCode}:${eventDate}:${model}`;
}

function cityCacheKey(latitude, longitude) {
  // A 0.02° cell avoids retaining the request's exact coordinate while still
  // being small enough not to routinely cross a municipal boundary.
  const cell = `${Math.floor(latitude * 50)}:${Math.floor(longitude * 50)}`;
  return createHash('sha256').update(cell).digest('base64url');
}

class UpstreamRequestBudget {
  constructor(limit) {
    this.remaining = limit;
  }

  take() {
    if (this.remaining <= 0) return false;
    this.remaining -= 1;
    return true;
  }
}

function shanghaiDateKey(value) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(value);
  const fields = Object.fromEntries(parts
    .filter((part) => part.type !== 'literal')
    .map((part) => [part.type, part.value]));
  return `${fields.year}-${fields.month}-${fields.day}`;
}

function expectedShanghaiDateKey(now, dayOffset) {
  const localNow = new Date(now.getTime() + 8 * 60 * 60 * 1_000);
  const shifted = new Date(Date.UTC(
    localNow.getUTCFullYear(),
    localNow.getUTCMonth(),
    localNow.getUTCDate() + dayOffset,
  ));
  return shifted.toISOString().slice(0, 10);
}

function validateEventDate(result, { dayOffset, now }) {
  if (result.status !== 'ok' || result.eventTime == null) return result;
  const eventAt = new Date(result.eventTime);
  if (!Number.isFinite(eventAt.getTime()) ||
      shanghaiDateKey(eventAt) !== expectedShanghaiDateKey(now, dayOffset)) {
    return {
      ...result,
      status: 'invalid',
      parseStatus: 'event_date_mismatch',
      score: null,
      aod: null,
    };
  }
  return result;
}

function applyPresentationPolicy(data, config, now) {
  const score = data.summary.score;
  const eventTime = Date.parse(data.event.eventTime ?? '');
  const ageMilliseconds = Number.isFinite(eventTime) ? now.getTime() - eventTime : Infinity;
  const notMissed = ageMilliseconds <= 90 * 60 * 1_000;
  const usable = Number.isFinite(score) && data.provider.providerStatus !== 'unavailable';
  const confidenceFactor = data.summary.confidence === 'low' ? .5 : 1;
  const staleFactor = data.freshness.isStale ? .5 : 1;
  const bandStrength = !usable || score < .20 ? 0 :
    score < .40 ? .08 : score < .60 ? .13 : score < .80 ? .19 : .25;
  return {
    ...data,
    presentation: {
      proactiveEligible: config.cardEnabled && usable && notMissed &&
        score >= config.proactiveDisplayThreshold,
      paperEligible: usable && notMissed && score >= config.paperNoteThreshold,
      notificationEligible: config.notificationEnabled && usable && notMissed &&
        score >= config.notificationThreshold && data.summary.confidence !== 'low',
      ambientStrength: Math.min(.25, bandStrength * confidenceFactor * staleFactor),
    },
  };
}

// Scores and AOD are upstream/model implementation details. Keep them only in
// this service while deriving presentation policy; never let them become part
// of the app contract.
function publicSkyOpportunity(data) {
  return {
    id: data.id,
    source: data.source,
    location: {
      requestedCity: data.location.requestedCity,
      resolvedCity: data.location.resolvedCity,
      locationPrecision: data.location.locationPrecision,
    },
    event: {
      type: data.event.type,
      dayOffset: data.event.dayOffset,
      eventTime: data.event.eventTime,
      providerLocalTimeZone: data.event.providerLocalTimeZone,
    },
    summary: {
      level: data.summary.level,
      label: data.summary.label,
      confidence: data.summary.confidence,
      agreement: data.summary.agreement,
      primaryReason: data.summary.primaryReason,
    },
    atmosphere: {
      clarityLevel: data.atmosphere.clarityLevel,
      clarityLabel: data.atmosphere.clarityLabel,
    },
    models: data.models.map((item) => ({
      model: item.model,
      providerLabel: item.providerLabel,
      eventTime: item.eventTime,
      status: item.status,
      parseStatus: item.parseStatus,
    })),
    freshness: {
      fetchedAt: data.freshness.fetchedAt,
      expiresAt: data.freshness.expiresAt,
      cacheStatus: data.freshness.cacheStatus,
      isStale: data.freshness.isStale,
    },
    provider: {
      name: data.provider.name,
      attribution: data.provider.attribution,
      providerStatus: data.provider.providerStatus,
    },
    presentation: {
      proactiveEligible: data.presentation.proactiveEligible,
      paperEligible: data.presentation.paperEligible,
      notificationEligible: data.presentation.notificationEligible,
      ambientStrength: data.presentation.ambientStrength,
    },
  };
}

export class SkyOpportunityService {
  constructor({
    settings = () => ({}),
    baseUrl,
    amapWebKey = () => '',
    cache = new MemorySkyOpportunityCache(),
    metrics = new SkyOpportunityMetrics(),
    fetcher = fetch,
    now = () => new Date(),
    queryId,
    logger = () => {},
  } = {}) {
    this.settings = settings;
    this.baseUrl = baseUrl;
    this.amapWebKey = amapWebKey;
    this.cache = cache;
    this.metrics = metrics;
    this.fetcher = fetcher;
    this.now = now;
    this.queryId = queryId;
    this.logger = logger;
    this.inFlight = new Map();
    this.runtime = null;
  }

  config() {
    return sunsetBotConfig(this.settings(), { baseUrl: this.baseUrl });
  }

  provider(config) {
    const signature = JSON.stringify({
      baseUrl: config.baseUrl,
      timeoutMs: config.timeoutMs,
      maxAttempts: config.maxAttempts,
      retryDelayMs: config.retryDelayMs,
      maxGlobalConcurrency: config.maxGlobalConcurrency,
      maxCityConcurrency: config.maxCityConcurrency,
      circuitFailureThreshold: config.circuitFailureThreshold,
      circuitRollingWindowSeconds: config.circuitRollingWindowSeconds,
      circuitFailureRateThreshold: config.circuitFailureRateThreshold,
      circuitOpenSeconds: config.circuitOpenSeconds,
    });
    if (this.runtime?.signature === signature) return this.runtime.provider;
    const circuitBreaker = new SunsetBotCircuitBreaker({
      failureThreshold: config.circuitFailureThreshold,
      rollingWindowSeconds: config.circuitRollingWindowSeconds,
      failureRateThreshold: config.circuitFailureRateThreshold,
      openSeconds: config.circuitOpenSeconds,
    });
    const client = new SunsetBotClient({
      config,
      fetcher: this.fetcher,
      queryId: this.queryId,
      now: this.now,
    });
    const provider = new SunsetBotProvider({
      client,
      circuitBreaker,
      metrics: this.metrics,
      logger: this.logger,
    });
    this.runtime = { signature, provider };
    return provider;
  }

  featureFlags(config = this.config()) {
    return {
      sunsetbotProviderEnabled: config.enabled,
      skyOpportunityCardEnabled: config.cardEnabled,
      skyOpportunityNotificationEnabled: config.notificationEnabled,
      skyOpportunityMapEnabled: config.mapEnabled,
    };
  }

  async resolveLocation(latitude, longitude, config) {
    const now = this.now();
    const key = cityCacheKey(latitude, longitude);
    const cached = await this.cache.getCityCandidates?.(key, now);
    if (cached?.status === 'hit') {
      this.metrics.increment('sunsetbot_city_cache_hit_total');
      return { ok: true, ...cached.entry };
    }
    const location = await resolveSkyOpportunityCity({
      latitude,
      longitude,
      amapWebKey: this.amapWebKey(),
      fetcher: this.fetcher,
      timeoutMs: Math.min(config.timeoutMs, 5_000),
    });
    if (location.ok) {
      await this.cache.setCityCandidates?.(key, location, {
        now,
        ttlSeconds: 24 * 60 * 60,
      });
    }
    return location;
  }

  async model({
    city,
    eventType,
    dayOffset,
    model,
    config,
    allowUpstream = true,
    requestBudget,
  }) {
    const instant = this.now();
    const eventCode = mapEventCode(eventType, dayOffset);
    const key = cacheKey(
      city,
      eventCode,
      expectedShanghaiDateKey(instant, dayOffset),
      model,
    );
    const cached = await this.cache.get(key, instant);
    if (cached.status === 'hit') {
      this.metrics.increment('sunsetbot_cache_hit_total');
      if (cached.entry.modelResult.status === 'not_found') {
        this.metrics.increment('sunsetbot_negative_cache_hit_total');
      }
      return {
        ...cached.entry.modelResult,
        fetchedAt: cached.entry.fetchedAt,
        cacheStatus: 'hit',
        isStale: false,
      };
    }
    const stale = cached.status === 'stale' ? cached.entry : null;
    const budgetExhausted = allowUpstream && requestBudget != null && !requestBudget.take();
    if (!allowUpstream || budgetExhausted) {
      if (budgetExhausted) this.metrics.increment('sunsetbot_request_budget_exhausted_total');
      if (stale != null) {
        this.metrics.increment('sunsetbot_stale_cache_total');
        return {
          ...stale.modelResult,
          fetchedAt: stale.fetchedAt,
          cacheStatus: 'stale',
          isStale: true,
        };
      }
      return { model, status: 'upstream_error', parseStatus: 'request_budget', cacheStatus: 'miss' };
    }
    if (this.inFlight.has(key)) return this.inFlight.get(key);
    const operation = (async () => {
      const fetched = await this.provider(config).fetchModel({
        city,
        eventType,
        dayOffset,
        model,
        now: instant,
      });
      const result = validateEventDate(fetched, { dayOffset, now: instant });
      if (result.parseStatus === 'event_date_mismatch') {
        this.metrics.increment('sunsetbot_event_date_mismatch_total');
        this.metrics.increment('sunsetbot_parse_error_total');
      }
      if (result.status === 'ok' || result.status === 'not_found') {
        await this.cache.set(key, result, {
          fetchedAt: instant,
          freshTtlSeconds: config.freshTtlSeconds,
          staleTtlSeconds: config.staleTtlSeconds,
        });
        return {
          ...result,
          fetchedAt: instant.toISOString(),
          cacheStatus: 'miss',
          isStale: false,
        };
      }
      if (stale != null) {
        this.metrics.increment('sunsetbot_stale_cache_total');
        return {
          ...stale.modelResult,
          fetchedAt: stale.fetchedAt,
          cacheStatus: 'stale',
          isStale: true,
        };
      }
      return { ...result, fetchedAt: null, cacheStatus: 'miss', isStale: false };
    })().finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, operation);
    return operation;
  }

  async forecastForLocation({
    latitude,
    longitude,
    requestedCity,
    candidates,
    eventType,
    dayOffset,
    config,
    allowUpstream = true,
    requestBudget,
  }) {
    for (const city of candidates) {
      const models = await Promise.all(config.models.map((model) => this.model({
        city,
        eventType,
        dayOffset,
        model,
        config,
        allowUpstream,
        requestBudget,
      })));
      if (models.every((item) => item.status === 'not_found')) continue;
      const available = models.some((item) => item.status === 'ok' && Number.isFinite(item.score));
      if (!available) {
        return { status: 'unavailable', data: null, locationUnsupported: false };
      }
      const stale = models.some((item) => item.status === 'ok' && item.isStale);
      const statuses = new Set(models.map((item) => item.cacheStatus));
      const cacheStatus = statuses.size === 1 ? models[0].cacheStatus : 'mixed';
      const data = aggregateSkyOpportunity({
        city,
        requestedCity,
        latitude,
        longitude,
        eventType,
        dayOffset,
        models,
        now: this.now(),
        freshTtlSeconds: config.freshTtlSeconds,
        stale,
        cacheStatus,
        metrics: this.metrics,
      });
      return {
        status: 'ok',
        data: publicSkyOpportunity(applyPresentationPolicy(data, config, this.now())),
        locationUnsupported: false,
      };
    }
    return { status: 'unavailable', data: null, locationUnsupported: true };
  }

  async forecast(query) {
    const config = this.config();
    const flags = this.featureFlags(config);
    if (!config.enabled) return { status: 'unavailable', data: null, featureFlags: flags };
    const location = await this.resolveLocation(query.latitude, query.longitude, config);
    if (!location.ok) {
      return { status: 'unavailable', data: null, locationUnsupported: false, featureFlags: flags };
    }
    return {
      ...(await this.forecastForLocation({ ...query, ...location, config })),
      featureFlags: flags,
    };
  }

  async daily(query) {
    const config = this.config();
    const featureFlags = this.featureFlags(config);
    const unavailable = { status: 'unavailable', data: null };
    if (!config.enabled) {
      return {
        status: 'unavailable', todaySunrise: unavailable, todaySunset: unavailable,
        tomorrowSunrise: unavailable,
        tomorrowSunset: unavailable, featureFlags,
      };
    }
    const location = await this.resolveLocation(query.latitude, query.longitude, config);
    if (!location.ok) {
      return {
        status: 'unavailable', todaySunrise: unavailable, todaySunset: unavailable,
        tomorrowSunrise: unavailable,
        tomorrowSunset: unavailable, featureFlags,
      };
    }
    const common = { ...query, ...location, config };
    const primaryBudget = new UpstreamRequestBudget(4);
    const wantsTodaySunrise = query.focus === 'preSunrise';
    const [first, second] = await Promise.all([
      this.forecastForLocation({
        ...common,
        eventType: wantsTodaySunrise ? 'sunrise' : 'sunset',
        dayOffset: 0,
        requestBudget: primaryBudget,
      }),
      this.forecastForLocation({
        ...common,
        eventType: wantsTodaySunrise ? 'sunset' : 'sunrise',
        dayOffset: wantsTodaySunrise ? 0 : 1,
        requestBudget: primaryBudget,
      }),
    ]);
    const todaySunrise = wantsTodaySunrise ? first : unavailable;
    const todaySunset = wantsTodaySunrise ? second : first;
    const tomorrowSunrise = wantsTodaySunrise ? unavailable : second;
    const tomorrowSunset = config.tomorrowSunsetEnabled
      ? await this.forecastForLocation({
        ...common,
        eventType: 'sunset',
        dayOffset: 1,
        requestBudget: new UpstreamRequestBudget(2),
      })
      : unavailable;
    return {
      status: [todaySunrise, todaySunset, tomorrowSunrise, tomorrowSunset]
        .some((item) => item.status === 'ok') ? 'ok' : 'unavailable',
      todaySunrise,
      todaySunset,
      tomorrowSunrise,
      tomorrowSunset,
      featureFlags,
    };
  }
}
