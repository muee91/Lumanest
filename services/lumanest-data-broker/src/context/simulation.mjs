import { createHash, randomBytes } from 'node:crypto';

const presets = Object.freeze({
  'lake-sunset': { scene: 'lake', primaryScene: 'inlandWater', facets: ['lake', 'reflectiveSurface'], activity: 'stationary', phase: 'sunset', weather: 'clear', event: 'session.water.evening' },
  'mountain-dawn': { scene: 'mountain', primaryScene: 'mountain', facets: ['reviewedPeak', 'openHorizon'], activity: 'stationary', phase: 'dawn', weather: 'clear', event: 'session.mountain.morning' },
  'city-blue-hour': { scene: 'city', primaryScene: 'urban', facets: ['skyline', 'architecture'], activity: 'stationary', phase: 'blueHour', weather: 'cloudy', event: 'session.city.blue_hour' },
  'rain-thunder': { scene: 'mountain', primaryScene: 'mountain', facets: ['canyon'], activity: 'hiking', phase: 'day', weather: 'rain', event: 'session.mountain.morning', safety: 'thunderstorm' },
  'snow-hike': { scene: 'mountain', primaryScene: 'mountain', facets: ['snowCover'], activity: 'hiking', phase: 'day', weather: 'snow', event: 'session.mountain.morning' },
  'desert-dust': { scene: 'desert', primaryScene: 'desert', facets: ['dune', 'openHorizon'], activity: 'stationary', phase: 'sunset', weather: 'dust', event: 'session.desert.side_light' },
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

export function isSimulationSessionId(value) {
  return typeof value === 'string' && /^[a-z0-9]{12,48}$/.test(value);
}

export class SimulationRegistry {
  constructor({ now = () => Date.now(), ttlMs = 30 * 60_000 } = {}) {
    this.now = now;
    this.ttlMs = ttlMs;
    this.sessions = new Map();
  }

  register(sessionId) {
    if (!isSimulationSessionId(sessionId)) return;
    const previous = this.sessions.get(sessionId);
    this.sessions.set(sessionId, { sessionId, preset: previous?.preset ?? null, expiresAt: this.now() + this.ttlMs });
  }

  list() {
    this.#prune();
    return [...this.sessions.values()].map(({ sessionId, preset, expiresAt }) => ({
      sessionCode: sessionId.slice(-8), activePreset: preset, expiresAt: new Date(expiresAt).toISOString(),
    }));
  }

  activate(sessionCode, preset) {
    this.#prune();
    if (!Object.hasOwn(presets, preset)) return { ok: false, error: 'invalid_preset' };
    const entry = [...this.sessions.values()].find((candidate) => candidate.sessionId.endsWith(sessionCode));
    if (entry == null) return { ok: false, error: 'session_not_found' };
    entry.preset = preset;
    return { ok: true, sessionCode, preset, expiresAt: new Date(entry.expiresAt).toISOString() };
  }

  clear(sessionCode) {
    const entry = [...this.sessions.values()].find((candidate) => candidate.sessionId.endsWith(sessionCode));
    if (entry == null) return { ok: false, error: 'session_not_found' };
    entry.preset = null;
    return { ok: true };
  }

  snapshot(sessionId, now = new Date()) {
    this.#prune();
    const preset = this.sessions.get(sessionId)?.preset;
    if (preset == null) return null;
    return simulatedSnapshot(preset, now);
  }

  #prune() { for (const [key, value] of this.sessions) if (value.expiresAt <= this.now()) this.sessions.delete(key); }
}

export function simulatedSnapshot(preset, now = new Date()) {
  const spec = presets[preset];
  if (spec == null) return null;
  const generatedAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + 10 * 60_000).toISOString();
  const creative = {
    id: spec.event, channel: 'opportunity', source: 'rule', observedAt: generatedAt, expiresAt,
    confidence: .82, geoScope: 'point', severity: 'info', allowedAction: eventActions[spec.event], title: eventTitles[spec.event], sourceUrl: null,
  };
  const safety = spec.safety == null ? [] : [{
    id: 'thunderstorm', channel: 'safety', source: 'official', observedAt: generatedAt, expiresAt,
    confidence: .95, geoScope: 'region', severity: 'warning', allowedAction: 'openSafetyDetail', title: '雷暴风险，请暂停暴露地带停留', sourceUrl: null,
  }];
  const weather = { condition: spec.weather, temperatureCelsius: spec.weather === 'snow' ? -4 : 18, windSpeedMps: spec.weather === 'dust' ? 10 : 2.4, windDirectionDegrees: 245, precipitationMm: spec.weather === 'rain' ? 5.4 : spec.weather === 'snow' ? .8 : 0, visibilityKm: spec.weather === 'mist' ? 1.2 : spec.weather === 'rain' ? 4 : 18, cloudCoverPercent: spec.weather === 'clear' ? 18 : 72, thunder: spec.safety != null, airQualityIndex: null, airQualityCategory: null, primaryPollutant: null, airQualityObservedAt: null, airQualityStale: false };
  return {
    contractVersion: 4, contextId: id('ctx_', `${preset}:${generatedAt}`), generatedAt, expiresAt, scene: spec.scene,
    fingerprint: id('', `${preset}:${generatedAt}`), stale: false,
    dataFreshness: { context: 'fresh', weather: 'fresh', weatherObservedAt: generatedAt }, weather,
    sunMoon: { dayPhase: spec.phase, sunElevationDegrees: 8, sunAzimuthDegrees: 105, moonPhase: 'waxingCrescent', moonIllumination: .24 },
    route: { mode: spec.activity === 'hiking' ? 'hiking' : 'none', stage: spec.activity === 'hiking' ? 'active' : 'none', active: spec.activity === 'hiking' },
    sceneContext: { primaryScene: spec.primaryScene, facets: spec.facets, activity: spec.activity, scores: { [spec.primaryScene]: 60 }, reviewedOverride: false },
    opportunityCatalogVersion: 1,
    events: [creative, ...safety], allowedActions: [...new Set([creative.allowedAction, ...safety.map((item) => item.allowedAction)])],
    manifest: { layoutMode: safety.length ? 'safety' : 'opportunity', primaryEventId: creative.id, secondaryEventIds: [], safetyEventIds: safety.map((item) => item.id) },
    shootingSessions: [],
  };
}
