function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function rounded(value) {
  return Number(value.toFixed(6));
}

function coarseCoordinate(value) {
  const latitudeCell = Math.floor(value.latitude / 0.05);
  const longitudeCell = Math.floor(value.longitude / 0.05);
  return {
    latitude: rounded((latitudeCell + 0.5) * 0.05),
    longitude: rounded((longitudeCell + 0.5) * 0.05),
  };
}

export function coarseRouteCorridor(route) {
  if (!object(route) ||
      typeof route.routeId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(route.routeId) ||
      !Array.isArray(route.corridorSamples) ||
      route.corridorSamples.length < 2 ||
      route.corridorSamples.length > 5) {
    return null;
  }
  const samples = [];
  let previousProgress = -1;
  for (const sample of route.corridorSamples) {
    if (!object(sample) ||
        !finite(sample.latitude, -90, 90) ||
        !finite(sample.longitude, -180, 180) ||
        !finite(sample.progress, 0, 1) ||
        sample.progress <= previousProgress ||
        !validDate(sample.expectedAt)) {
      return null;
    }
    const point = coarseCoordinate(sample);
    samples.push(Object.freeze({
      ...point,
      system: 'wgs84',
      expectedAt: new Date(sample.expectedAt).toISOString(),
      progress: Number(sample.progress.toFixed(6)),
    }));
    previousProgress = sample.progress;
  }
  return Object.freeze({
    routeId: route.routeId.slice(0, 64),
    samples: Object.freeze(samples),
  });
}

export function validRouteCorridorBinding(value) {
  if (value == null) return true;
  return object(value) &&
    typeof value.routeId === 'string' &&
    /^[A-Za-z0-9_-]{1,64}$/.test(value.routeId) &&
    Array.isArray(value.samples) &&
    value.samples.length >= 2 && value.samples.length <= 5 &&
    value.samples.every((sample, index) => object(sample) &&
      sample.system === 'wgs84' &&
      finite(sample.latitude, -90, 90) &&
      finite(sample.longitude, -180, 180) &&
      finite(sample.progress, 0, 1) &&
      validDate(sample.expectedAt) &&
      (index === 0 || sample.progress > value.samples[index - 1].progress));
}

function boundedCondition(value) {
  return ['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(value)
    ? value
    : 'unknown';
}

function segmentLabel(progress) {
  if (progress < .18) return '出发后不久';
  if (progress < .45) return '路线前段';
  if (progress < .72) return '路线中段';
  if (progress < .92) return '路线后段';
  return '接近目的地';
}

export function routeWeatherFacts(result, now) {
  const body = result?.ok === true ? result.body : null;
  if (!object(body) || !validDate(body.generatedAt) ||
      Date.parse(body.generatedAt) > now.getTime() + 5 * 60_000 ||
      !Array.isArray(body.samples)) {
    return { lines: [], factIds: [], expiresAt: null };
  }
  const lines = [];
  const factIds = [];
  let latestExpectedAt = null;
  for (const [index, sample] of body.samples.slice(0, 5).entries()) {
    if (!object(sample) ||
        !finite(sample.progress, 0, 1) ||
        !validDate(sample.expectedAt) ||
        !finite(sample.windSpeedMps, 0, 150) ||
        !finite(sample.precipitationMm, 0, 2000)) {
      continue;
    }
    const parts = [
      boundedCondition(sample.condition),
      `风速${sample.windSpeedMps.toFixed(1)}m/s`,
    ];
    if (finite(sample.visibilityKm, 0, 500)) {
      parts.push(`能见度${sample.visibilityKm.toFixed(0)}km`);
    }
    if (sample.precipitationMm > 0) {
      parts.push(`降水${sample.precipitationMm.toFixed(1)}mm`);
    }
    if (sample.thunder === true) {
      parts.push('存在雷暴信号，具体安全判断只看安全卡和官方预警');
    }
    if (sample.stale === true) parts.push('数据来自缓存');
    lines.push(
      `沿途天气（${segmentLabel(sample.progress)}，预计${sample.expectedAt}）：${parts.join('、')}`,
    );
    factIds.push(`route.weather.${index}`);
    const expectedAt = Date.parse(sample.expectedAt);
    latestExpectedAt = latestExpectedAt == null
      ? expectedAt
      : Math.max(latestExpectedAt, expectedAt);
  }
  const hardExpiry = now.getTime() + 30 * 60_000;
  return {
    lines,
    factIds,
    expiresAt: new Date(Math.min(latestExpectedAt ?? hardExpiry, hardExpiry)).toISOString(),
  };
}
