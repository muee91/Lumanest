const canonicalRequestKeys = new Set([
  'contractVersion', 'coordinate', 'observedAt', 'locale', 'intent', 'route',
]);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}
function exactKeys(value, keys) {
  return object(value) && Object.keys(value).every((key) => keys.has(key));
}

function finiteIn(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function validHttpsUrl(value, maximumLength) {
  if (typeof value !== 'string' || value.length < 1 || value.length > maximumLength) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && Boolean(url.hostname);
  } catch {
    return false;
  }
}

// Current context route invariant:
//   mode == 'none'  iff  stage == 'none'
//   when mode != 'none', stage must be one of planned/active/paused
//   (covered structurally by the iff rule given the allowed enum values)
// For responses, active must equal (stage == 'active').
function validRouteModeStage(mode, stage) {
  return (mode === 'none') === (stage === 'none');
}

function validCorridorSample(value) {
  return exactKeys(value, new Set([
    'latitude', 'longitude', 'system', 'expectedAt', 'progress',
  ])) && value.system === 'wgs84' &&
    finiteIn(value.latitude, -90, 90) && finiteIn(value.longitude, -180, 180) &&
    typeof value.expectedAt === 'string' && Number.isFinite(Date.parse(value.expectedAt)) &&
    finiteIn(value.progress, 0, 1);
}

function validRouteRequest(route, contractVersion) {
  const corridorKeys = new Set(['mode', 'stage', 'routeId', 'corridorSamples']);
  if (!exactKeys(route, corridorKeys) ||
      !['none', 'driving', 'hiking'].includes(route.mode) ||
      !['none', 'planned', 'active', 'paused'].includes(route.stage) ||
      !validRouteModeStage(route.mode, route.stage)) return false;
  if (contractVersion !== 4 ||
      (route.routeId !== null &&
        (typeof route.routeId !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(route.routeId))) ||
      !Array.isArray(route.corridorSamples) || route.corridorSamples.length > 3 ||
      !route.corridorSamples.every(validCorridorSample)) return false;
  if (route.mode === 'none') return route.routeId === null && route.corridorSamples.length === 0;
  if (route.corridorSamples.length > 0 && route.routeId === null) return false;
  for (let index = 1; index < route.corridorSamples.length; index += 1) {
    const prior = route.corridorSamples[index - 1];
    const current = route.corridorSamples[index];
    if (prior.progress > current.progress || Date.parse(prior.expectedAt) > Date.parse(current.expectedAt)) {
      return false;
    }
  }
  return true;
}

export function validContextRequest(body) {
  if (!exactKeys(body, canonicalRequestKeys) || body.contractVersion !== 4) return false;
  if (!exactKeys(body.coordinate, new Set(['latitude', 'longitude', 'system'])) ||
      body.coordinate.system !== 'wgs84' ||
      !finiteIn(body.coordinate.latitude, -90, 90) ||
      !finiteIn(body.coordinate.longitude, -180, 180)) return false;
  if (typeof body.observedAt !== 'string' || !Number.isFinite(Date.parse(body.observedAt))) return false;
  if (!['zh-CN', 'en'].includes(body.locale)) return false;
  if (!['photography', 'food', 'supplies', 'fuel', 'wildlife'].includes(body.intent)) return false;
  if (!validRouteRequest(body.route, body.contractVersion)) return false;
  return true;
}

export function validTargetSessionRequest(body) {
  return exactKeys(body, new Set([
    'contractVersion', 'targetId', 'targetCoordinate', 'observedAt', 'locale',
  ])) && body.contractVersion === 1 &&
    typeof body.targetId === 'string' && /^target_[a-f0-9]{24}$/.test(body.targetId) &&
    exactKeys(body.targetCoordinate, new Set(['latitude', 'longitude', 'system'])) &&
    body.targetCoordinate.system === 'wgs84' &&
    finiteIn(body.targetCoordinate.latitude, -90, 90) &&
    finiteIn(body.targetCoordinate.longitude, -180, 180) &&
    typeof body.observedAt === 'string' && Number.isFinite(Date.parse(body.observedAt)) &&
    ['zh-CN', 'en'].includes(body.locale);
}

export function validShootingFeedbackRequest(body) {
  const keys = new Set([
    'contractVersion', 'ruleVersion', 'conditionBand', 'factors', 'outcome',
    'reasons', 'targetId',
  ]);
  if (body?.contractVersion !== 2 || !exactKeys(body, keys) ||
      typeof body.ruleVersion !== 'string' || !/^[a-z0-9._-]{1,32}$/.test(body.ruleVersion) ||
      !['good', 'fair', 'limited'].includes(body.conditionBand) ||
      !['captured', 'conditionsDidNotAppear', 'arrivedLate', 'didNotGo'].includes(body.outcome) ||
      !Array.isArray(body.factors) || body.factors.length < 1 || body.factors.length > 8 ||
      !body.factors.every((factor) => exactKeys(factor, new Set(['id', 'effect'])) &&
        ['cloud', 'wind', 'precipitation', 'visibility', 'dataCoverage'].includes(factor.id) &&
        ['supporting', 'neutral', 'limiting'].includes(factor.effect)) ||
      new Set(body.factors.map((factor) => factor.id)).size !== body.factors.length ||
      !Array.isArray(body.reasons) || body.reasons.length > 4 ||
      !body.reasons.every((reason) => ['wind', 'cloud', 'precipitation', 'target'].includes(reason)) ||
      new Set(body.reasons).size !== body.reasons.length ||
      (body.targetId != null &&
        (typeof body.targetId !== 'string' || !/^target_[a-f0-9]{24}$/.test(body.targetId)))) {
    return false;
  }
  return true;
}

const actions = new Set([
  'openShootingWindow', 'openExplore', 'openRoute', 'openPlaceDetail',
  'openAstronomyDetail', 'openWildlifeDetail', 'openSafetyDetail',
  'openCreativeDetail', 'dismiss',
]);
const moonPhases = new Set([
  'newMoon', 'waxingCrescent', 'firstQuarter', 'waxingGibbous',
  'fullMoon', 'waningGibbous', 'lastQuarter', 'waningCrescent',
]);

function validEvent(value) {
  if (!exactKeys(value, new Set([
    'id', 'channel', 'source', 'observedAt', 'expiresAt', 'confidence',
    'geoScope', 'severity', 'allowedAction', 'title', 'sourceUrl',
  ])) || typeof value.id !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,95}$/.test(value.id) ||
    !['opportunity', 'safety', 'wildlifeOpportunity', 'wildlifeSafety'].includes(value.channel) ||
    !['weather', 'solar', 'rule', 'official', 'wildlifeHistorical', 'astronomyCatalog'].includes(value.source) ||
    typeof value.observedAt !== 'string' || !Number.isFinite(Date.parse(value.observedAt)) ||
    typeof value.expiresAt !== 'string' || !Number.isFinite(Date.parse(value.expiresAt)) ||
    !finiteIn(value.confidence, 0, 1) || !['point', 'region', 'route'].includes(value.geoScope) ||
    !['info', 'caution', 'warning', 'critical'].includes(value.severity) || !actions.has(value.allowedAction)) {
    return false;
  }
  if (value.source === 'astronomyCatalog') {
    if (value.allowedAction !== 'openAstronomyDetail' || typeof value.title !== 'string' ||
        [...value.title.trim()].length < 1 || [...value.title.trim()].length > 80 ||
        typeof value.sourceUrl !== 'string' || value.sourceUrl.length > 500) return false;
    try {
      return new URL(value.sourceUrl).protocol === 'https:';
    } catch {
      return false;
    }
  }
  return value.sourceUrl == null && (value.title == null ||
    (typeof value.title === 'string' && [...value.title.trim()].length >= 1 &&
      [...value.title.trim()].length <= 80));
}

function validShootingTarget(value) {
  return exactKeys(value, new Set([
    'id', 'name', 'kind', 'coordinate', 'supportedSessions', 'viewBearingDegrees',
    'bearingToleranceDegrees', 'accessModes', 'leadTimeMinutes', 'arrivalRadiusMeters',
    'shorelineSide', 'reviewedAt', 'reviewReference', 'sourceAttribution',
    'sourceLicense', 'sourceUrl',
  ])) && typeof value.id === 'string' && /^target_[a-f0-9]{24}$/.test(value.id) &&
    typeof value.name === 'string' && [...value.name.trim()].length >= 1 && [...value.name.trim()].length <= 200 &&
    value.kind === 'lakeshore' &&
    exactKeys(value.coordinate, new Set(['latitude', 'longitude', 'system'])) &&
    value.coordinate.system === 'wgs84' && finiteIn(value.coordinate.latitude, -90, 90) &&
    finiteIn(value.coordinate.longitude, -180, 180) &&
    Array.isArray(value.supportedSessions) && value.supportedSessions.length >= 1 &&
    value.supportedSessions.length <= 2 &&
    value.supportedSessions.every((item) => [
      'waterMorning', 'waterEvening', 'mountainMorning', 'mountainEvening',
      'cityBlueHour', 'cityAfterRain', 'desertSideLight', 'routeLightWindow',
    ].includes(item)) &&
    finiteIn(value.viewBearingDegrees, 0, 360) && value.viewBearingDegrees !== 360 &&
    finiteIn(value.bearingToleranceDegrees, 5, 90) &&
    Array.isArray(value.accessModes) && value.accessModes.length >= 1 && value.accessModes.length <= 2 &&
    value.accessModes.every((item) => ['driving', 'walking'].includes(item)) &&
    Number.isInteger(value.leadTimeMinutes) && finiteIn(value.leadTimeMinutes, 0, 180) &&
    Number.isInteger(value.arrivalRadiusMeters) && finiteIn(value.arrivalRadiusMeters, 25, 1000) &&
    ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']
      .includes(value.shorelineSide) &&
    typeof value.reviewedAt === 'string' && Number.isFinite(Date.parse(value.reviewedAt)) &&
    validHttpsUrl(value.reviewReference, 500) &&
    typeof value.sourceAttribution === 'string' && value.sourceAttribution.trim().length >= 1 &&
    value.sourceAttribution.length <= 500 &&
    typeof value.sourceLicense === 'string' && value.sourceLicense.trim().length >= 1 &&
    value.sourceLicense.length <= 100 && validHttpsUrl(value.sourceUrl, 500);
}

function validShootingFactor(value) {
  return exactKeys(value, new Set(['id', 'effect', 'label', 'value', 'sourceAt'])) &&
    ['cloud', 'wind', 'precipitation', 'visibility', 'dataCoverage'].includes(value.id) &&
    ['supporting', 'neutral', 'limiting'].includes(value.effect) &&
    typeof value.label === 'string' && value.label.trim().length >= 1 && value.label.length <= 40 &&
    typeof value.value === 'string' && value.value.trim().length >= 1 && value.value.length <= 80 &&
    typeof value.sourceAt === 'string' && Number.isFinite(Date.parse(value.sourceAt));
}

function validShootingPhase(value) {
  return exactKeys(value, new Set([
    'kind', 'startAt', 'peakAt', 'endAt', 'conditionBand', 'directionDegrees',
  ])) && [
    'morningBlueHour', 'sunrise', 'morningMist', 'reflection', 'warmLight',
    'sunset', 'blueHour', 'artificialLights', 'rainEnding', 'wetReflection',
    'desertSideLight', 'texture', 'approach', 'safeStop', 'shoot', 'rejoinRoute',
    'returnWindow', 'sessionEnd',
  ].includes(value.kind) &&
    ['good', 'fair', 'limited'].includes(value.conditionBand) &&
    [value.startAt, value.peakAt, value.endAt].every((item) =>
      typeof item === 'string' && Number.isFinite(Date.parse(item))) &&
    Date.parse(value.startAt) <= Date.parse(value.peakAt) &&
    Date.parse(value.peakAt) <= Date.parse(value.endAt) &&
    finiteIn(value.directionDegrees, 0, 360) && value.directionDegrees !== 360;
}

function validShootingTrendSample(value) {
  return exactKeys(value, new Set([
    'at', 'conditionIndex', 'cloudCoverPercent', 'windSpeedMps', 'precipitationMm',
  ])) && typeof value.at === 'string' && Number.isFinite(Date.parse(value.at)) &&
    Number.isInteger(value.conditionIndex) && finiteIn(value.conditionIndex, 0, 100) &&
    (value.cloudCoverPercent == null || finiteIn(value.cloudCoverPercent, 0, 100)) &&
    finiteIn(value.windSpeedMps, 0, 150) && finiteIn(value.precipitationMm, 0, 2000);
}

function validShootingSession(value) {
  if (!exactKeys(value, new Set([
    'id', 'kind', 'title', 'startAt', 'endAt', 'primaryPhase', 'conditionBand',
    'confidenceBand', 'trend', 'phases', 'factors', 'trendSamples', 'targetCandidates',
    'recommendedCapabilities', 'ruleVersion', 'expiresAt',
  ])) || typeof value.id !== 'string' || !/^session_[a-f0-9]{24}$/.test(value.id) ||
      ![
        'waterMorning', 'waterEvening', 'mountainMorning', 'mountainEvening',
        'cityBlueHour', 'cityAfterRain', 'desertSideLight', 'routeLightWindow',
      ].includes(value.kind) ||
      typeof value.title !== 'string' || value.title.trim().length < 1 ||
      value.title.length > 80 ||
      ![
        'morningBlueHour', 'sunrise', 'morningMist', 'reflection', 'warmLight',
        'sunset', 'blueHour', 'artificialLights', 'rainEnding', 'wetReflection',
        'desertSideLight', 'texture', 'approach', 'safeStop', 'shoot', 'rejoinRoute',
        'returnWindow', 'sessionEnd',
      ].includes(value.primaryPhase) ||
      !['good', 'fair', 'limited'].includes(value.conditionBand) ||
      !['high', 'medium', 'limited'].includes(value.confidenceBand) ||
      !['improving', 'stable', 'weakening'].includes(value.trend) ||
      typeof value.startAt !== 'string' || !Number.isFinite(Date.parse(value.startAt)) ||
      typeof value.endAt !== 'string' || !Number.isFinite(Date.parse(value.endAt)) ||
      Date.parse(value.endAt) <= Date.parse(value.startAt) ||
      typeof value.expiresAt !== 'string' || !Number.isFinite(Date.parse(value.expiresAt)) ||
      typeof value.ruleVersion !== 'string' || !/^[a-z0-9._-]{1,32}$/.test(value.ruleVersion) ||
      !Array.isArray(value.phases) || value.phases.length < 1 || value.phases.length > 5 ||
      !value.phases.every(validShootingPhase) ||
      !value.phases.some((phase) => phase.kind === value.primaryPhase) ||
      !Array.isArray(value.factors) || value.factors.length < 1 || value.factors.length > 8 ||
      !value.factors.every(validShootingFactor) ||
      !Array.isArray(value.trendSamples) || value.trendSamples.length < 2 ||
      value.trendSamples.length > 12 || !value.trendSamples.every(validShootingTrendSample) ||
      !Array.isArray(value.targetCandidates) || value.targetCandidates.length > 3 ||
      !value.targetCandidates.every(validShootingTarget) ||
      !Array.isArray(value.recommendedCapabilities) || value.recommendedCapabilities.length > 4 ||
      new Set(value.recommendedCapabilities).size !== value.recommendedCapabilities.length ||
      !value.recommendedCapabilities.every((item) => [
        'tripod', 'wide_angle', 'telephoto', 'filter', 'weather_protection', 'headlamp',
      ].includes(item))) return false;
  return true;
}

const primaryScenes = new Set([
  'unknown', 'urban', 'village', 'mountain', 'plateau', 'desert', 'forest',
  'inlandWater', 'coast', 'wetland',
]);
const sceneFacets = new Set([
  'lake', 'river', 'reservoir', 'wetland', 'coast', 'tidalFlat', 'waterfall',
  'snowCover', 'glacier', 'canyon', 'dune', 'grassland', 'forest',
  'bambooForest', 'skyline', 'architecture', 'oldTown', 'villageStreet',
  'openRoad', 'openHorizon', 'darkSky', 'reviewedPeak', 'reviewedViewpoint',
  'reflectiveSurface',
]);

function validSceneContext(value) {
  if (!exactKeys(value, new Set([
    'primaryScene', 'facets', 'activity', 'scores', 'reviewedOverride',
  ])) || !primaryScenes.has(value.primaryScene) ||
      !Array.isArray(value.facets) || value.facets.length > 24 ||
      value.facets.some((facet) => !sceneFacets.has(facet)) ||
      new Set(value.facets).size !== value.facets.length ||
      !['stationary', 'walking', 'hiking', 'driving'].includes(value.activity) ||
      !object(value.scores) || typeof value.reviewedOverride !== 'boolean') return false;
  if (Object.entries(value.scores).some(([scene, score]) =>
    !primaryScenes.has(scene) || !Number.isInteger(score) || score < 0 || score > 100)) return false;
  return !value.reviewedOverride || value.scores[value.primaryScene] === 100;
}

function validContextResponse(body) {
  if (!exactKeys(body, new Set([
    'contractVersion', 'contextId', 'generatedAt', 'expiresAt', 'scene', 'fingerprint',
    'stale', 'dataFreshness', 'weather', 'sunMoon', 'route', 'events', 'allowedActions', 'manifest',
    'shootingSessions', 'sceneContext', 'opportunityCatalogVersion',
  ])) || body.contractVersion !== 4) return false;
  if (!/^ctx_[a-f0-9]{24}$/.test(body.contextId) ||
      !Number.isFinite(Date.parse(body.generatedAt)) || !Number.isFinite(Date.parse(body.expiresAt)) ||
      !['unknown', 'city', 'lake', 'mountain', 'desert', 'village', 'driving', 'hiking'].includes(body.scene) ||
      !/^[a-f0-9]{24}$/.test(body.fingerprint) || typeof body.stale !== 'boolean' ||
      !body.events.every(validEvent) ||
      !Array.isArray(body.shootingSessions) || body.shootingSessions.length > 2 ||
      !body.shootingSessions.every(validShootingSession) ||
      body.opportunityCatalogVersion !== 1 || !validSceneContext(body.sceneContext)) return false;
  const freshness = body.dataFreshness;
  if (!exactKeys(freshness, new Set(['context', 'weather', 'weatherObservedAt'])) ||
      !['fresh', 'stale'].includes(freshness.context) || !['fresh', 'stale'].includes(freshness.weather) ||
      typeof freshness.weatherObservedAt !== 'string' || !Number.isFinite(Date.parse(freshness.weatherObservedAt))) return false;
  const weather = body.weather;
  if (!exactKeys(weather, new Set([
    'condition', 'temperatureCelsius', 'windSpeedMps', 'windDirectionDegrees', 'precipitationMm',
    'visibilityKm', 'cloudCoverPercent', 'thunder', 'airQualityIndex', 'airQualityCategory',
    'primaryPollutant', 'airQualityObservedAt', 'airQualityStale',
  ])) || !['clear', 'cloudy', 'rain', 'snow', 'dust', 'unknown'].includes(weather.condition) ||
      (weather.temperatureCelsius != null && !finiteIn(weather.temperatureCelsius, -100, 100)) ||
      !finiteIn(weather.windSpeedMps, 0, 150) ||
      (weather.windDirectionDegrees != null &&
        (!finiteIn(weather.windDirectionDegrees, 0, 360) || weather.windDirectionDegrees === 360)) ||
      !finiteIn(weather.precipitationMm, 0, 2000) || !finiteIn(weather.visibilityKm, 0, 500) ||
      (weather.cloudCoverPercent != null && !finiteIn(weather.cloudCoverPercent, 0, 100)) ||
      typeof weather.thunder !== 'boolean' ||
      (weather.airQualityIndex != null && !Number.isInteger(weather.airQualityIndex)) ||
      (weather.airQualityIndex != null && !finiteIn(weather.airQualityIndex, 0, 500)) ||
      (weather.airQualityCategory != null &&
        (typeof weather.airQualityCategory !== 'string' || weather.airQualityCategory.length > 40)) ||
      (weather.primaryPollutant != null &&
        (typeof weather.primaryPollutant !== 'string' || weather.primaryPollutant.length > 40)) ||
      (weather.airQualityObservedAt != null &&
        (typeof weather.airQualityObservedAt !== 'string' ||
          !Number.isFinite(Date.parse(weather.airQualityObservedAt)))) ||
      typeof weather.airQualityStale !== 'boolean') return false;
  if ((weather.airQualityIndex == null) !== (weather.airQualityObservedAt == null)) return false;
  const sunMoon = body.sunMoon;
  if (!exactKeys(sunMoon, new Set([
    'dayPhase', 'sunElevationDegrees', 'sunAzimuthDegrees', 'moonPhase', 'moonIllumination',
  ])) || !['dawn', 'day', 'sunset', 'blueHour', 'night'].includes(sunMoon.dayPhase) ||
      (sunMoon.sunElevationDegrees != null && !finiteIn(sunMoon.sunElevationDegrees, -90, 90)) ||
      (sunMoon.sunAzimuthDegrees != null &&
        (!finiteIn(sunMoon.sunAzimuthDegrees, 0, 360) || sunMoon.sunAzimuthDegrees === 360)) ||
      !moonPhases.has(sunMoon.moonPhase) || !finiteIn(sunMoon.moonIllumination, 0, 1)) return false;
  if (!exactKeys(body.route, new Set(['mode', 'stage', 'active'])) ||
      !['none', 'driving', 'hiking'].includes(body.route.mode) ||
      !['none', 'planned', 'active', 'paused'].includes(body.route.stage) ||
      !validRouteModeStage(body.route.mode, body.route.stage) ||
      typeof body.route.active !== 'boolean' ||
      body.route.active !== (body.route.stage === 'active') ||
      !Array.isArray(body.allowedActions) ||
      body.allowedActions.some((action) => !actions.has(action)) ||
      new Set(body.allowedActions).size !== body.allowedActions.length) return false;
  return exactKeys(body.manifest, new Set([
    'layoutMode', 'primaryEventId', 'secondaryEventIds', 'safetyEventIds',
  ])) && ['quiet', 'opportunity', 'safety'].includes(body.manifest.layoutMode) &&
    (body.manifest.primaryEventId == null || typeof body.manifest.primaryEventId === 'string') &&
    Array.isArray(body.manifest.secondaryEventIds) && Array.isArray(body.manifest.safetyEventIds);
}

export async function forwardContextSnapshot({
  body,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const url = new URL('/internal/v1/evaluate', serviceUrl);
    const upstream = await fetcher(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (!upstream.ok || !validContextResponse(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, body: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

export async function resolveShootingTarget({
  targetId,
  coordinate,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/shooting-targets/resolve', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify({ targetId, coordinate }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (upstream.status === 404) return { ok: false, error: 'not_found' };
    if (!upstream.ok || !validShootingTarget(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, target: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

export async function forwardShootingFeedback({
  body,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/shooting-feedback', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (!upstream.ok || !exactKeys(responseBody, new Set(['accepted'])) ||
        responseBody.accepted !== true) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

export async function listContextSources({ serviceUrl, internalToken, fetcher = fetch, timeoutMs = 8_000 }) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/sources', serviceUrl), {
      headers: { 'X-Internal-Service-Token': internalToken },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await upstream.json();
    if (!upstream.ok || !Array.isArray(body)) return { ok: false, error: 'upstream_unavailable' };
    return { ok: true, sources: body };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function validShootingCalibration(body) {
  if (!exactKeys(body, new Set([
    'generatedAt', 'since', 'minimumSamples', 'rows',
  ])) || !Number.isFinite(Date.parse(body.generatedAt)) ||
      !Number.isFinite(Date.parse(body.since)) ||
      !Number.isInteger(body.minimumSamples) || !finiteIn(body.minimumSamples, 5, 100) ||
      !Array.isArray(body.rows) || body.rows.length > 500) return false;
  return body.rows.every((row) => exactKeys(row, new Set([
    'ruleVersion', 'conditionBand', 'factorId', 'factorEffect', 'evaluatedCount',
    'capturedCount', 'conditionsDidNotAppearCount', 'capturedRate',
  ])) && typeof row.ruleVersion === 'string' && /^[a-z0-9._-]{1,32}$/.test(row.ruleVersion) &&
    ['good', 'fair', 'limited'].includes(row.conditionBand) &&
    ['cloud', 'wind', 'precipitation', 'visibility', 'dataCoverage'].includes(row.factorId) &&
    ['supporting', 'neutral', 'limiting'].includes(row.factorEffect) &&
    Number.isInteger(row.evaluatedCount) && row.evaluatedCount >= body.minimumSamples &&
    Number.isInteger(row.capturedCount) && row.capturedCount >= 0 &&
    Number.isInteger(row.conditionsDidNotAppearCount) && row.conditionsDidNotAppearCount >= 0 &&
    row.capturedCount + row.conditionsDidNotAppearCount === row.evaluatedCount &&
    finiteIn(row.capturedRate, 0, 1));
}

export async function fetchShootingCalibration({
  days = 90,
  minimumSamples = 5,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  if (!Number.isInteger(days) || days < 30 || days > 365 ||
      !Number.isInteger(minimumSamples) || minimumSamples < 5 || minimumSamples > 100) {
    return { ok: false, error: 'invalid_request' };
  }
  try {
    const url = new URL('/internal/v1/shooting-feedback/calibration', serviceUrl);
    url.searchParams.set('days', String(days));
    url.searchParams.set('minimumSamples', String(minimumSamples));
    const upstream = await fetcher(url, {
      headers: { 'X-Internal-Service-Token': internalToken },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await upstream.json();
    if (!upstream.ok || !validShootingCalibration(body)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, report: body };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function validPosition(value) {
  return Array.isArray(value) && value.length >= 2 &&
    finiteIn(value[0], -180, 180) && finiteIn(value[1], -90, 90);
}

function validRing(value) {
  return Array.isArray(value) && value.length >= 4 && value.every(validPosition) &&
    value[0][0] === value.at(-1)[0] && value[0][1] === value.at(-1)[1];
}

function validWildlifeGeometry(value) {
  if (!exactKeys(value, new Set(['type', 'coordinates'])) || !Array.isArray(value.coordinates)) return false;
  if (value.type === 'Polygon') return value.coordinates.length > 0 && value.coordinates.every(validRing);
  if (value.type === 'MultiPolygon') {
    return value.coordinates.length > 0 && value.coordinates.every((polygon) =>
      Array.isArray(polygon) && polygon.length > 0 && polygon.every(validRing));
  }
  return false;
}

function validWildlifeLayerResponse(body) {
  if (!exactKeys(body, new Set(['contractVersion', 'generatedAt', 'radiusKm', 'areas'])) ||
      body.contractVersion !== 1 || !Number.isFinite(Date.parse(body.generatedAt)) ||
      !Number.isInteger(body.radiusKm) || body.radiusKm < 5 || body.radiusKm > 50 ||
      !Array.isArray(body.areas) || body.areas.length > 50) return false;
  return body.areas.every((area) =>
    exactKeys(area, new Set(['id', 'name', 'geometry', 'source'])) &&
    typeof area.id === 'string' && /^[a-f0-9]{64}$/.test(area.id) &&
    typeof area.name === 'string' && [...area.name.trim()].length >= 1 && [...area.name.trim()].length <= 200 &&
    validWildlifeGeometry(area.geometry) &&
    exactKeys(area.source, new Set(['attribution', 'version', 'updatedAt'])) &&
    typeof area.source.attribution === 'string' && area.source.attribution.trim().length > 0 &&
    typeof area.source.version === 'string' && area.source.version.trim().length > 0 &&
    (area.source.updatedAt == null ||
      (typeof area.source.updatedAt === 'string' && Number.isFinite(Date.parse(area.source.updatedAt)))));
}

export async function fetchWildlifeLayers({
  latitude,
  longitude,
  radiusKm,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const url = new URL('/internal/v1/wildlife/layers', serviceUrl);
    url.searchParams.set('latitude', String(latitude));
    url.searchParams.set('longitude', String(longitude));
    url.searchParams.set('radiusKm', String(radiusKm));
    const upstream = await fetcher(url, {
      headers: { 'X-Internal-Service-Token': internalToken },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await upstream.json();
    if (!upstream.ok || !validWildlifeLayerResponse(body)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, body };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function validImportResult(body) {
  return object(body) && typeof body.sourceId === 'string' &&
    ['spatialFeatures', 'astronomyEvents'].includes(body.datasetType) &&
    Number.isInteger(body.importedCount) && body.importedCount >= 0 &&
    typeof body.enabled === 'boolean' && typeof body.cacheInvalidated === 'boolean';
}

export async function importContextDataset({
  body,
  serviceUrl,
  internalToken,
  fetcher = fetch,
  timeoutMs = 20_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: 'not_configured' };
  try {
    const upstream = await fetcher(new URL('/internal/v1/imports', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (upstream.status === 422) return { ok: false, error: 'invalid_import' };
    if (!upstream.ok || !validImportResult(responseBody)) {
      return { ok: false, error: 'upstream_unavailable' };
    }
    return { ok: true, result: responseBody };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}
