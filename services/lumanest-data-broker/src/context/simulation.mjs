import { createHash } from 'node:crypto';

const presets = Object.freeze({
  'lake-sunset': Object.freeze({
    label: '湖泊 · 晚霞倒影', description: '验证湖面晚霞、倒影阶段和改善趋势。',
    scene: 'lake', primaryScene: 'inlandWater', facets: ['lake', 'reflectiveSurface'],
    activity: 'stationary', phase: 'sunset', weather: 'clear', event: 'session.water.evening',
    session: Object.freeze({
      kind: 'waterEvening', title: '湖岸晚间窗口', primaryPhase: 'reflection',
      secondaryPhase: 'sunset', conditionBand: 'good', confidenceBand: 'high',
      trend: 'improving', directionDegrees: 286, ruleVersion: 'water-evening.1',
      recommendedCapabilities: ['tripod', 'filter'],
    }),
  }),
  'mountain-dawn': Object.freeze({
    label: '山地 · 黎明暖光', description: '验证山地晨光、日出方向和稳定趋势。',
    scene: 'mountain', primaryScene: 'mountain', facets: ['reviewedPeak', 'openHorizon'],
    activity: 'stationary', phase: 'dawn', weather: 'clear', event: 'session.mountain.morning',
    session: Object.freeze({
      kind: 'mountainMorning', title: '山地晨光窗口', primaryPhase: 'sunrise',
      secondaryPhase: 'warmLight', conditionBand: 'good', confidenceBand: 'high',
      trend: 'stable', directionDegrees: 82, ruleVersion: 'mountain-morning.1',
      recommendedCapabilities: ['tripod', 'telephoto'],
    }),
  }),
  'city-blue-hour': Object.freeze({
    label: '城市 · 蓝调时刻', description: '验证城市蓝调、建筑灯光和中等置信度。',
    scene: 'city', primaryScene: 'urban', facets: ['skyline', 'architecture'],
    activity: 'stationary', phase: 'blueHour', weather: 'cloudy', event: 'session.city.blue_hour',
    session: Object.freeze({
      kind: 'cityBlueHour', title: '城市蓝调窗口', primaryPhase: 'blueHour',
      secondaryPhase: 'artificialLights', conditionBand: 'fair', confidenceBand: 'medium',
      trend: 'stable', directionDegrees: 272, ruleVersion: 'city-blue-hour.1',
      recommendedCapabilities: ['tripod', 'wideAngle'],
    }),
  }),
  'rain-thunder': Object.freeze({
    label: '徒步 · 降雨雷暴', description: '验证安全提醒优先、停止拍摄和受限条件。',
    scene: 'mountain', primaryScene: 'mountain', facets: ['canyon'],
    activity: 'hiking', phase: 'day', weather: 'rain', event: 'session.mountain.morning',
    safety: 'thunderstorm',
    session: Object.freeze({
      kind: 'mountainMorning', title: '山地安全停止窗口', primaryPhase: 'safeStop',
      secondaryPhase: 'returnWindow', conditionBand: 'limited', confidenceBand: 'high',
      trend: 'weakening', directionDegrees: 220, ruleVersion: 'mountain-safety.1',
      recommendedCapabilities: ['weatherProtection', 'headlamp'],
    }),
  }),
  'snow-hike': Object.freeze({
    label: '徒步 · 降雪低能见度', description: '验证降雪、行进状态和条件受限降级。',
    scene: 'mountain', primaryScene: 'mountain', facets: ['snowCover'],
    activity: 'hiking', phase: 'day', weather: 'snow', event: 'session.mountain.morning',
    session: Object.freeze({
      kind: 'mountainMorning', title: '雪地晨光观察窗口', primaryPhase: 'approach',
      secondaryPhase: 'safeStop', conditionBand: 'limited', confidenceBand: 'medium',
      trend: 'weakening', directionDegrees: 110, ruleVersion: 'mountain-snow.1',
      recommendedCapabilities: ['weatherProtection', 'headlamp'],
    }),
  }),
  'desert-dust': Object.freeze({
    label: '荒漠 · 风沙侧光', description: '验证风沙、侧光纹理和有限能见度。',
    scene: 'desert', primaryScene: 'desert', facets: ['dune', 'openHorizon'],
    activity: 'stationary', phase: 'sunset', weather: 'dust', event: 'session.desert.side_light',
    session: Object.freeze({
      kind: 'desertSideLight', title: '荒漠侧光窗口', primaryPhase: 'desertSideLight',
      secondaryPhase: 'texture', conditionBand: 'fair', confidenceBand: 'medium',
      trend: 'weakening', directionDegrees: 255, ruleVersion: 'desert-side-light.1',
      recommendedCapabilities: ['weatherProtection', 'telephoto'],
    }),
  }),
});

const eventTitles = Object.freeze({
  'session.water.evening': '湖岸晚间会话',
  'session.mountain.morning': '山地晨光候选',
  'session.city.blue_hour': '城市蓝调会话',
  'session.desert.side_light': '荒漠侧光会话',
});
const eventActions = Object.freeze({
  'session.water.evening': 'openShootingWindow',
  'session.mountain.morning': 'openShootingWindow',
  'session.city.blue_hour': 'openShootingWindow',
  'session.desert.side_light': 'openShootingWindow',
});

function id(prefix, value) {
  return `${prefix}${createHash('sha256').update(value).digest('hex').slice(0, 24)}`;
}

function isoOffset(now, minutes) {
  return new Date(now.getTime() + minutes * 60_000).toISOString();
}

function weatherFor(spec) {
  return {
    condition: spec.weather,
    temperatureCelsius: spec.weather === 'snow' ? -4 : 18,
    windSpeedMps: spec.weather === 'dust' ? 10 : spec.weather === 'snow' ? 5.8 : 2.4,
    windDirectionDegrees: 245,
    precipitationMm: spec.weather === 'rain' ? 5.4 : spec.weather === 'snow' ? .8 : 0,
    visibilityKm: spec.weather === 'rain' ? 4 : spec.weather === 'snow' ? 3 : spec.weather === 'dust' ? 5 : 18,
    cloudCoverPercent: spec.weather === 'clear' ? 18 : 72,
    thunder: spec.safety != null,
    airQualityIndex: null,
    airQualityCategory: null,
    primaryPollutant: null,
    airQualityObservedAt: null,
    airQualityStale: false,
  };
}

function shootingSession(preset, spec, now, weather) {
  const generatedAt = now.toISOString();
  const startAt = isoOffset(now, 10);
  const primaryStart = isoOffset(now, 20);
  const primaryPeak = isoOffset(now, 35);
  const primaryEnd = isoOffset(now, 50);
  const secondaryEnd = isoOffset(now, 75);
  const conditionIndex = spec.session.conditionBand === 'good' ? 82 : spec.session.conditionBand === 'fair' ? 62 : 28;
  const finalIndex = spec.session.trend === 'improving' ? Math.min(95, conditionIndex + 12)
    : spec.session.trend === 'weakening' ? Math.max(5, conditionIndex - 14) : conditionIndex;
  const precipitationEffect = weather.precipitationMm > 0 ? 'limiting' : 'supporting';
  return {
    id: id('session_', `${preset}:${generatedAt}`),
    kind: spec.session.kind,
    title: spec.session.title,
    startAt,
    endAt: secondaryEnd,
    primaryPhase: spec.session.primaryPhase,
    conditionBand: spec.session.conditionBand,
    confidenceBand: spec.session.confidenceBand,
    trend: spec.session.trend,
    phases: [
      {
        kind: spec.session.primaryPhase,
        startAt: primaryStart,
        peakAt: primaryPeak,
        endAt: primaryEnd,
        conditionBand: spec.session.conditionBand,
        directionDegrees: spec.session.directionDegrees,
      },
      {
        kind: spec.session.secondaryPhase,
        startAt: primaryEnd,
        peakAt: isoOffset(now, 62),
        endAt: secondaryEnd,
        conditionBand: spec.session.conditionBand,
        directionDegrees: spec.session.directionDegrees,
      },
    ],
    factors: [
      { id: 'cloud', effect: weather.cloudCoverPercent <= 65 ? 'supporting' : 'limiting', label: '云量', value: `${weather.cloudCoverPercent}%`, sourceAt: generatedAt },
      { id: 'wind', effect: weather.windSpeedMps <= 4 ? 'supporting' : 'limiting', label: '风速', value: `${weather.windSpeedMps}m/s`, sourceAt: generatedAt },
      { id: 'precipitation', effect: precipitationEffect, label: '降水', value: `${weather.precipitationMm}mm`, sourceAt: generatedAt },
      { id: 'visibility', effect: weather.visibilityKm >= 8 ? 'supporting' : 'limiting', label: '能见度', value: `${weather.visibilityKm}km`, sourceAt: generatedAt },
    ],
    trendSamples: [
      { at: startAt, conditionIndex, cloudCoverPercent: weather.cloudCoverPercent, windSpeedMps: weather.windSpeedMps, precipitationMm: weather.precipitationMm },
      { at: primaryPeak, conditionIndex: Math.round((conditionIndex + finalIndex) / 2), cloudCoverPercent: weather.cloudCoverPercent, windSpeedMps: weather.windSpeedMps, precipitationMm: weather.precipitationMm },
      { at: secondaryEnd, conditionIndex: finalIndex, cloudCoverPercent: weather.cloudCoverPercent, windSpeedMps: weather.windSpeedMps, precipitationMm: weather.precipitationMm },
    ],
    targetCandidates: [],
    recommendedCapabilities: spec.session.recommendedCapabilities,
    ruleVersion: spec.session.ruleVersion,
    expiresAt: isoOffset(now, 15),
  };
}

export function simulationPresetCatalog() {
  return Object.entries(presets).map(([value, preset]) => Object.freeze({
    value,
    label: preset.label,
    description: preset.description,
    kind: preset.session.kind,
    conditionBand: preset.session.conditionBand,
    confidenceBand: preset.session.confidenceBand,
    hasSafetyAlert: preset.safety != null,
  }));
}

export function isSimulationSessionId(value) {
  return typeof value === 'string' && /^[a-z0-9]{12,48}$/.test(value);
}

export class SimulationRegistry {
  constructor({ now = () => Date.now(), ttlMs = 30 * 60_000 } = {}) {
    this.now = now;
    this.ttlMs = ttlMs;
    this.sessions = new Map();
  }

  register(sessionId, { contractVersion = null } = {}) {
    if (!isSimulationSessionId(sessionId)) return;
    const current = this.now();
    const previous = this.sessions.get(sessionId);
    this.sessions.set(sessionId, {
      sessionId,
      controlId: id('sim_', sessionId),
      preset: previous?.preset ?? null,
      registeredAt: previous?.registeredAt ?? current,
      lastSeenAt: current,
      activatedAt: previous?.activatedAt ?? null,
      lastDeliveredAt: previous?.lastDeliveredAt ?? null,
      deliveryCount: previous?.deliveryCount ?? 0,
      suppressedFeedbackCount: previous?.suppressedFeedbackCount ?? 0,
      contractVersion: Number.isInteger(contractVersion) ? contractVersion : previous?.contractVersion ?? null,
      expiresAt: current + this.ttlMs,
    });
  }

  list() {
    this.#prune();
    return [...this.sessions.values()]
      .sort((left, right) => right.lastSeenAt - left.lastSeenAt)
      .map((entry) => ({
        controlId: entry.controlId,
        sessionCode: entry.sessionId.slice(-8),
        activePreset: entry.preset,
        registeredAt: new Date(entry.registeredAt).toISOString(),
        lastSeenAt: new Date(entry.lastSeenAt).toISOString(),
        activatedAt: entry.activatedAt == null ? null : new Date(entry.activatedAt).toISOString(),
        lastDeliveredAt: entry.lastDeliveredAt == null ? null : new Date(entry.lastDeliveredAt).toISOString(),
        deliveryCount: entry.deliveryCount,
        suppressedFeedbackCount: entry.suppressedFeedbackCount,
        contractVersion: entry.contractVersion,
        expiresAt: new Date(entry.expiresAt).toISOString(),
      }));
  }

  activate(controlId, preset) {
    this.#prune();
    if (!Object.hasOwn(presets, preset)) return { ok: false, error: 'invalid_preset' };
    const entry = [...this.sessions.values()].find((candidate) => candidate.controlId === controlId);
    if (entry == null) return { ok: false, error: 'session_not_found' };
    entry.preset = preset;
    entry.activatedAt = this.now();
    entry.expiresAt = this.now() + this.ttlMs;
    return { ok: true, controlId, preset, expiresAt: new Date(entry.expiresAt).toISOString() };
  }

  clear(controlId) {
    const entry = [...this.sessions.values()].find((candidate) => candidate.controlId === controlId);
    if (entry == null) return { ok: false, error: 'session_not_found' };
    entry.preset = null;
    entry.activatedAt = null;
    return { ok: true };
  }

  clearAll() {
    this.#prune();
    let cleared = 0;
    for (const entry of this.sessions.values()) {
      if (entry.preset == null) continue;
      entry.preset = null;
      entry.activatedAt = null;
      cleared += 1;
    }
    return { ok: true, cleared };
  }

  suppressFeedback(sessionId) {
    this.#prune();
    const entry = this.sessions.get(sessionId);
    if (entry?.preset == null) return false;
    entry.suppressedFeedbackCount += 1;
    return true;
  }

  snapshot(sessionId, now = new Date()) {
    this.#prune();
    const entry = this.sessions.get(sessionId);
    if (entry?.preset == null) return null;
    entry.lastDeliveredAt = this.now();
    entry.deliveryCount += 1;
    return simulatedSnapshot(entry.preset, now);
  }

  #prune() {
    for (const [key, value] of this.sessions) {
      if (value.expiresAt <= this.now()) this.sessions.delete(key);
    }
  }
}

export function simulatedSnapshot(preset, now = new Date()) {
  const spec = presets[preset];
  if (spec == null) return null;
  const generatedAt = now.toISOString();
  const expiresAt = isoOffset(now, 10);
  const creative = {
    id: spec.event,
    channel: 'opportunity',
    source: 'rule',
    observedAt: generatedAt,
    expiresAt,
    confidence: .82,
    geoScope: 'point',
    severity: 'info',
    allowedAction: eventActions[spec.event],
    title: eventTitles[spec.event],
    sourceUrl: null,
  };
  const safety = spec.safety == null ? [] : [{
    id: 'thunderstorm',
    channel: 'safety',
    source: 'official',
    observedAt: generatedAt,
    expiresAt,
    confidence: .95,
    geoScope: 'region',
    severity: 'warning',
    allowedAction: 'openSafetyDetail',
    title: '雷暴风险，请暂停暴露地带停留',
    sourceUrl: null,
  }];
  const weather = weatherFor(spec);
  return {
    contractVersion: 4,
    contextId: id('ctx_', `${preset}:${generatedAt}`),
    generatedAt,
    expiresAt,
    scene: spec.scene,
    fingerprint: id('', `${preset}:${generatedAt}`),
    stale: false,
    dataFreshness: { context: 'fresh', weather: 'fresh', weatherObservedAt: generatedAt },
    weather,
    sunMoon: {
      dayPhase: spec.phase,
      sunElevationDegrees: 8,
      sunAzimuthDegrees: spec.session.directionDegrees,
      moonPhase: 'waxingCrescent',
      moonIllumination: .24,
    },
    route: {
      mode: spec.activity === 'hiking' ? 'hiking' : 'none',
      stage: spec.activity === 'hiking' ? 'active' : 'none',
      active: spec.activity === 'hiking',
    },
    sceneContext: {
      primaryScene: spec.primaryScene,
      facets: spec.facets,
      activity: spec.activity,
      scores: { [spec.primaryScene]: 60 },
      reviewedOverride: false,
    },
    opportunityCatalogVersion: 1,
    events: [creative, ...safety],
    allowedActions: [...new Set([creative.allowedAction, ...safety.map((item) => item.allowedAction)])],
    manifest: {
      layoutMode: safety.length ? 'safety' : 'opportunity',
      primaryEventId: creative.id,
      secondaryEventIds: [],
      safetyEventIds: safety.map((item) => item.id),
    },
    shootingSessions: [shootingSession(preset, spec, now, weather)],
  };
}
