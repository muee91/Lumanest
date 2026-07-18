import { clarityLevel, opportunityLevel } from './sky_opportunity_levels.mjs';

function confidenceFor(difference, count) {
  if (count === 0) return { confidence: 'unavailable', confidenceScore: 0, agreement: 'none' };
  if (count === 1) return { confidence: 'medium', confidenceScore: .65, agreement: 'single_model' };
  if (difference <= .20) return { confidence: 'high', confidenceScore: .85, agreement: 'strong' };
  if (difference <= .50) return { confidence: 'medium', confidenceScore: .65, agreement: 'partial' };
  return { confidence: 'low', confidenceScore: .35, agreement: 'conflict' };
}

function lowerConfidence(value) {
  return value === 'high' ? 'medium' : value === 'medium' ? 'low' : value;
}

function primaryReason(agreement) {
  return {
    strong: '双模型判断较一致',
    partial: '双模型存在一定分歧',
    conflict: '双模型分歧较大',
    single_model: '当前仅一个模型可用',
    none: '当前缺少可用模型结果',
  }[agreement];
}

export function aggregateSkyOpportunity({
  city,
  requestedCity,
  latitude,
  longitude,
  eventType,
  dayOffset,
  models,
  now,
  freshTtlSeconds,
  stale,
  cacheStatus,
  metrics,
}) {
  const available = models.filter((item) => item.status === 'ok' && Number.isFinite(item.score));
  const score = available.length === 0
    ? null
    : available.reduce((sum, item) => sum + item.score, 0) / available.length;
  const difference = available.length === 2 ? Math.abs(available[0].score - available[1].score) : null;
  if (difference != null) metrics?.observeDisagreement(difference);
  const base = confidenceFor(difference ?? 0, available.length);
  const confidence = stale ? lowerConfidence(base.confidence) : base.confidence;
  const confidenceScore = stale ? base.confidenceScore * .75 : base.confidenceScore;
  const level = opportunityLevel(score);
  const aodValues = available.map((item) => item.aod).filter(Number.isFinite);
  const aod = aodValues.length === 0
    ? null
    : aodValues.reduce((sum, value) => sum + value, 0) / aodValues.length;
  const clarity = clarityLevel(aod);
  const eventTime = available.map((item) => item.eventTime).find(Boolean) ?? null;
  const date = eventTime?.slice(0, 10).replaceAll('-', '') ??
    new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai' }).format(now).replaceAll('-', '');
  const fetchedTimes = models.map((item) => Date.parse(item.fetchedAt ?? '')).filter(Number.isFinite);
  const fetchedAt = fetchedTimes.length === 0 ? now : new Date(Math.min(...fetchedTimes));
  return {
    id: `skyopp_${city}_${date}_${eventType}`,
    source: 'sunsetbot',
    location: {
      requestedCity,
      resolvedCity: city,
      latitude,
      longitude,
      locationPrecision: 'city',
    },
    event: {
      type: eventType,
      dayOffset,
      eventTime,
      providerLocalTimeZone: 'Asia/Shanghai',
    },
    summary: {
      score,
      normalizedScore: score == null ? null : Math.max(0, Math.min(1, score / 2.5)),
      level: level.level,
      label: level.label,
      confidence,
      confidenceScore,
      agreement: base.agreement,
      primaryReason: primaryReason(base.agreement),
    },
    atmosphere: { aod, ...clarity },
    models: models.map((item) => ({
      model: item.model,
      score: item.score ?? null,
      providerLabel: item.providerLabel ?? null,
      aod: item.aod ?? null,
      aodLabel: item.aodLabel ?? null,
      eventTime: item.eventTime ?? null,
      status: item.status,
      parseStatus: item.parseStatus,
    })),
    freshness: {
      fetchedAt: fetchedAt.toISOString(),
      expiresAt: new Date(fetchedAt.getTime() + freshTtlSeconds * 1_000).toISOString(),
      cacheStatus,
      isStale: stale,
    },
    provider: {
      name: 'SunsetBot',
      attribution: '晚霞数据来源：SunsetBot',
      providerStatus: available.length === 0
        ? 'unavailable'
        : stale || available.length < 2
          ? 'degraded'
          : 'healthy',
    },
  };
}
