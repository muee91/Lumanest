import { apiErrorCodes } from '../api/error-codes.mjs';

const ROUTE_ID_PATTERN = /^[a-zA-Z0-9._:-]{1,96}$/;
const facilityLabels = Object.freeze({
  parking: '停车标注', fuel: '加油标注', food: '餐饮标注', water: '饮水标注',
  toilets: '厕所标注', shelter: '庇护设施', restArea: '休息区',
});

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function bounded(value, min, max) {
  return finiteNumber(value) && value >= min && value <= max;
}

function coarseCellCenter(value) {
  const cell = Math.floor(value / 0.05);
  return Number(((cell + 0.5) * 0.05).toFixed(4));
}

function validExpectedAt(value) {
  const parsed = new Date(value);
  return !Number.isNaN(parsed.valueOf());
}

export function coarseRouteCorridor(route) {
  if (route == null || typeof route !== 'object' || Array.isArray(route)) return null;
  if (typeof route.routeId !== 'string' || !ROUTE_ID_PATTERN.test(route.routeId) ||
      !Array.isArray(route.corridorSamples) || route.corridorSamples.length < 2 ||
      route.corridorSamples.length > 5) return null;
  const samples = [];
  let previousProgress = -1;
  for (const sample of route.corridorSamples) {
    if (sample == null || typeof sample !== 'object' || Array.isArray(sample) ||
        !bounded(sample.latitude, -90, 90) || !bounded(sample.longitude, -180, 180) ||
        !bounded(sample.progress, 0, 1) || sample.progress <= previousProgress ||
        !validExpectedAt(sample.expectedAt)) return null;
    previousProgress = sample.progress;
    samples.push({
      latitude: coarseCellCenter(sample.latitude),
      longitude: coarseCellCenter(sample.longitude),
      system: 'wgs84',
      expectedAt: new Date(sample.expectedAt).toISOString(),
      progress: Number(sample.progress.toFixed(4)),
    });
  }
  return { routeId: route.routeId, samples };
}

export function validRouteCorridorBinding(value) {
  return value == null || (typeof value === 'object' && ROUTE_ID_PATTERN.test(value.routeId) &&
    Array.isArray(value.samples) && value.samples.length >= 2 && value.samples.length <= 5 &&
    value.samples.every((sample) => sample?.system === 'wgs84' &&
      bounded(sample.latitude, -90, 90) && bounded(sample.longitude, -180, 180) &&
      bounded(sample.progress, 0, 1) && validExpectedAt(sample.expectedAt)));
}

function routeProgressLabel(progress) {
  if (progress < .18) return '出发后不久';
  if (progress < .45) return '前段';
  if (progress < .72) return '中段';
  if (progress < .92) return '后段';
  return '接近目的地';
}

function normalisedCondition(value) {
  return typeof value === 'string' && ['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(value)
    ? value : null;
}

function sourceRows(corridor) {
  if (!Array.isArray(corridor?.sources)) return [];
  return corridor.sources.filter((item) => item != null && typeof item.id === 'string' &&
    typeof item.title === 'string' && typeof item.publisher === 'string' && typeof item.url === 'string').slice(0, 4);
}

export function routeCorridorFacts(result, now = new Date()) {
  const empty = {
    lines: [], factIds: [], sources: [], expiresAt: null,
    coverage: {
      status: 'unavailable', requestedSegments: 0, availableSegments: 0,
      environmentTransitions: 0, parkingStatus: 'unavailable', supplyStatus: 'unavailable',
      restrictionStatus: 'unavailable', photographyStatus: 'unavailable',
      evidenceStatus: 'unavailable', authoritativeRestrictionCount: 0,
    },
  };
  if (result == null || typeof result !== 'object' || result.ok !== true ||
      result.body == null || typeof result.body !== 'object') return empty;
  const body = result.body;
  if (typeof body.generatedAt !== 'string' || !Array.isArray(body.samples) ||
      !['full', 'partial'].includes(body.coverage)) return empty;
  const generatedAt = new Date(body.generatedAt);
  if (Number.isNaN(generatedAt.valueOf()) || now.valueOf() - generatedAt.valueOf() > 2 * 60 * 60 * 1_000) return empty;

  const lines = [];
  const factIds = [];
  let previousCondition = null;
  let environmentTransitions = 0;
  for (let index = 0; index < body.samples.length; index += 1) {
    const sample = body.samples[index];
    if (sample == null || typeof sample !== 'object' || !bounded(sample.progress, 0, 1) ||
        !validExpectedAt(sample.expectedAt)) continue;
    const parts = [];
    const condition = normalisedCondition(sample.condition);
    if (condition != null) parts.push(`天气 ${condition}`);
    if (previousCondition != null && condition != null && previousCondition !== condition) environmentTransitions += 1;
    if (condition != null) previousCondition = condition;
    if (bounded(sample.windSpeedMps, 0, 150)) parts.push(`风速 ${sample.windSpeedMps.toFixed(1)}m/s`);
    if (bounded(sample.visibilityKm, 0, 500)) parts.push(`能见度 ${sample.visibilityKm.toFixed(0)}km`);
    if (bounded(sample.precipitationMm, 0, 2_000) && sample.precipitationMm > 0) parts.push(`降水 ${sample.precipitationMm.toFixed(1)}mm`);
    if (sample.thunder === true) parts.push('雷暴信号');
    if (parts.length > 0) {
      lines.push(`路线${routeProgressLabel(sample.progress)}（预计 ${new Date(sample.expectedAt).toISOString()}）：${parts.join('，')}${sample.stale === true ? '；该点使用过期缓存，仅作低置信参考' : ''}${sample.thunder === true ? '；雷暴等安全风险只以安全卡和官方预警为准' : ''}。`);
      factIds.push(`route.weather.${index}`);
    }
  }
  if (body.coverage === 'partial') lines.push('路线沿途天气只覆盖部分采样点；缺失路段不得按晴好或安全处理。');

  const corridor = body.corridor;
  const segments = Array.isArray(corridor?.segments) ? corridor.segments : [];
  const totals = Object.fromEntries(Object.keys(facilityLabels).map((key) => [key, 0]));
  let photographyReferences = 0;
  let authoritativeRestrictionCount = 0;
  let officialResponsive = false;
  let referenceEvidence = false;
  for (const segment of segments) {
    if (segment?.facilities?.status === 'reference') {
      referenceEvidence = true;
      for (const key of Object.keys(totals)) {
        if (Number.isInteger(segment.facilities[key]) && segment.facilities[key] >= 0) totals[key] += segment.facilities[key];
      }
    }
    if (segment?.photography?.status === 'reference') {
      photographyReferences += (segment.photography.viewpointCount ?? 0) + (segment.photography.heritageCount ?? 0);
    }
    if (segment?.restrictions?.status === 'present') {
      officialResponsive = true;
      authoritativeRestrictionCount += 1;
      for (const id of segment.restrictions.factIds ?? []) if (typeof id === 'string') factIds.push(id);
    } else if (segment?.restrictions?.status === 'noneObserved') {
      officialResponsive = true;
    }
  }
  const facilityParts = Object.entries(totals).filter(([, value]) => value > 0)
    .map(([key, value]) => `${facilityLabels[key]} ${value}`);
  if (facilityParts.length > 0) {
    lines.push(`沿途公开地图参考：${facilityParts.join('、')}。这些标注不代表营业、开放或一定可进入，客户端高德结果仍作为具体补给与停车候选。`);
    factIds.push('route.corridor.facilities');
  }
  if (photographyReferences > 0) {
    lines.push(`沿途公开地图存在 ${photographyReferences} 条观景点或历史对象参考；这不是已验证机位，也不代表当前适合拍摄。`);
    factIds.push('route.corridor.photography');
  }
  if (authoritativeRestrictionCount > 0) {
    lines.push(`沿途 ${authoritativeRestrictionCount} 个采样段存在仍有效的官方关闭、道路管制或限制证据；具体内容只以安全卡与官方来源为准。`);
  } else if (officialResponsive) {
    lines.push('沿途采样范围未检出仍有效的官方管制公告；这不是道路安全或开放确认，出发前仍需查看官方来源。');
  }

  const requestedSegments = Number.isInteger(corridor?.requestedSegments) ? corridor.requestedSegments : 0;
  const availableSegments = Number.isInteger(corridor?.availableSegments) ? corridor.availableSegments : 0;
  const parkingStatus = totals.parking > 0 ? 'reference' : availableSegments > 0 ? 'noReference' : 'unavailable';
  const supplyTotal = totals.fuel + totals.food + totals.water + totals.toilets + totals.shelter + totals.restArea;
  const supplyStatus = supplyTotal > 0 ? 'reference' : availableSegments > 0 ? 'noReference' : 'unavailable';
  const photographyStatus = photographyReferences > 0 ? 'reference' : availableSegments > 0 ? 'noReference' : 'unavailable';
  const restrictionStatus = authoritativeRestrictionCount > 0 ? 'present' : officialResponsive ? 'noneObserved' : 'unavailable';
  const status = lines.length === 0 ? 'unavailable'
    : body.coverage === 'full' && corridor?.coverage === 'full' ? 'ready' : 'partial';
  return {
    lines,
    factIds: [...new Set(factIds)].slice(0, 12),
    sources: sourceRows(corridor),
    expiresAt: new Date(generatedAt.valueOf() + 2 * 60 * 60 * 1_000),
    coverage: {
      status,
      requestedSegments,
      availableSegments,
      environmentTransitions,
      parkingStatus,
      supplyStatus,
      restrictionStatus,
      photographyStatus,
      evidenceStatus: authoritativeRestrictionCount > 0 ? 'verified' : referenceEvidence ? 'reference' : 'unavailable',
      authoritativeRestrictionCount,
    },
  };
}

export const routeWeatherFacts = routeCorridorFacts;
