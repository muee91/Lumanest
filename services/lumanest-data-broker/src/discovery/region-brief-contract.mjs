const contractVersion = 2;

const activationTypes = new Set([
  'user_manual',
  'foreground_opportunistic',
]);
const physicalScenes = new Set([
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
const settlementTypes = new Set([
  'unknown', 'none', 'metropolitan', 'urbanDistrict', 'historicDistrict', 'historicTown',
  'village', 'pastoralSettlement', 'scenicArea',
]);
const remotenessLevels = new Set(['unknown', 'connected', 'edge', 'remote', 'extreme']);
const altitudeBands = new Set(['low', 'moderate', 'high', 'veryHigh', 'unknown']);
const poiDensityBands = new Set(['unknown', 'dense', 'normal', 'sparse', 'verySparse']);
const mobilityStates = new Set(['stationary', 'walking', 'hiking', 'driving']);
const routeStages = new Set(['none', 'planned', 'active', 'paused']);
const sectionNames = new Set([
  'identity', 'orientation', 'photoThemes', 'happeningNow', 'places',
  'localTaste', 'etiquette', 'practical',
]);
const briefStatuses = new Set(['ready', 'refreshing', 'partial', 'pending', 'unavailable']);
const completenessStates = new Set(['identityOnly', 'partial', 'actionable', 'comprehensive']);
const insightTypes = new Set([
  'areaIdentity', 'orientation', 'history', 'localStory', 'architecture',
  'culturalPractice', 'etiquette', 'performance', 'event', 'market',
  'localFood', 'specialty', 'naturalFeature', 'photographyTheme', 'routeStop',
  'supply', 'openingStatus', 'regulation', 'seasonalSignal',
]);
const verificationStates = new Set([
  'authoritative', 'corroborated', 'singleSource', 'candidate', 'conflicting',
]);
const actionabilityStates = new Set(['informational', 'detail', 'navigate', 'remind']);
const qualityTiers = new Set(['S', 'A', 'B', 'C']);

const requestKeys = new Set([
  'contractVersion', 'snapshotId', 'activationType', 'locale', 'region',
  'sceneProfile', 'requestedSections',
]);
const profileKeys = new Set([
  'physicalScene', 'facets', 'settlement', 'remoteness', 'altitude',
  'poiDensity', 'mobility', 'routeStage',
]);
const regionKeys = new Set(['latitude', 'longitude', 'radiusMeters']);
const responseKeys = new Set([
  'contractVersion', 'briefId', 'regionId', 'regionName', 'profile',
  'generatedAt', 'expiresAt', 'status', 'completeness', 'identity',
  'orientation', 'photoThemes', 'insights', 'sources', 'refresh',
]);
const textBlockKeys = new Set(['summary', 'factIds']);
const sourceKeys = new Set([
  'id', 'sourcePolicyId', 'publisher', 'title', 'url', 'observedAt',
  'qualityTier', 'publishedAt', 'validFrom', 'validUntil', 'license', 'version',
]);
const insightKeys = new Set([
  'id', 'regionId', 'type', 'title', 'summary', 'verification', 'factIds',
  'evidenceIds', 'observedAt', 'expiresAt', 'placeId', 'coordinate', 'startsAt',
  'endsAt', 'timeSensitive', 'actionability', 'sceneTags', 'photoThemeTags',
]);
const coordinateKeys = new Set(['latitude', 'longitude', 'system']);
const refreshKeys = new Set(['refreshingMissions', 'retryAfterSeconds']);

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return isObject(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function allowedKeys(value, keys) {
  return isObject(value) && Object.keys(value).every((key) => keys.has(key));
}

function boundedString(value, minimum, maximum) {
  return typeof value === 'string' && value.trim().length >= minimum && [...value].length <= maximum;
}

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function finiteIn(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function validId(value, maximum = 160) {
  return boundedString(value, 1, maximum) && /^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(value);
}

function validSnapshotId(value) {
  // Context Service identifiers are opaque, Broker-generated ctx_ IDs. The
  // request is later bound to the remembered snapshot; syntax alone is never
  // authorization.
  return typeof value === 'string' && /^ctx_[a-f0-9]{24}$/.test(value);
}

function validProfile(value) {
  return exactKeys(value, profileKeys) && physicalScenes.has(value.physicalScene) &&
    Array.isArray(value.facets) && value.facets.length <= 24 &&
    value.facets.every((facet) => sceneFacets.has(facet)) &&
    new Set(value.facets).size === value.facets.length &&
    settlementTypes.has(value.settlement) && remotenessLevels.has(value.remoteness) &&
    altitudeBands.has(value.altitude) && poiDensityBands.has(value.poiDensity) &&
    mobilityStates.has(value.mobility) && routeStages.has(value.routeStage);
}

function validRegion(value) {
  return exactKeys(value, regionKeys) && finiteIn(value.latitude, -90, 90) &&
    finiteIn(value.longitude, -180, 180) && Number.isInteger(value.radiusMeters) &&
    finiteIn(value.radiusMeters, 100, 50_000);
}

function validCoordinate(value) {
  return exactKeys(value, coordinateKeys) && value.system === 'wgs84' &&
    finiteIn(value.latitude, -90, 90) && finiteIn(value.longitude, -180, 180);
}

function validTextBlock(value) {
  return exactKeys(value, textBlockKeys) && boundedString(value.summary, 1, 120) &&
    Array.isArray(value.factIds) && value.factIds.length > 0 && value.factIds.length <= 8 &&
    value.factIds.every((id) => validId(id, 160)) && new Set(value.factIds).size === value.factIds.length;
}

function validSource(value) {
  if (!allowedKeys(value, sourceKeys) || !validId(value.id) || !validId(value.sourcePolicyId, 80) ||
      !boundedString(value.publisher, 1, 80) || !boundedString(value.title, 1, 300) ||
      !boundedString(value.url, 1, 1_000) || !validDate(value.observedAt) ||
      !qualityTiers.has(value.qualityTier) || !boundedString(value.license, 1, 160) ||
      !boundedString(value.version, 1, 80)) return false;
  try {
    if (new URL(value.url).protocol !== 'https:') return false;
  } catch {
    return false;
  }
  return ['publishedAt', 'validFrom', 'validUntil'].every((key) => value[key] === undefined || value[key] === null || validDate(value[key]));
}

function validInsight(value, sourceIds) {
  if (!allowedKeys(value, insightKeys) || !validId(value.id) || !validId(value.regionId) ||
      !insightTypes.has(value.type) || !boundedString(value.title, 1, 120) ||
      !boundedString(value.summary, 1, 280) || !verificationStates.has(value.verification) ||
      !validDate(value.observedAt) || !validDate(value.expiresAt) ||
      Date.parse(value.expiresAt) <= Date.parse(value.observedAt) ||
      typeof value.timeSensitive !== 'boolean' || !actionabilityStates.has(value.actionability) ||
      !Array.isArray(value.factIds) || value.factIds.length === 0 || value.factIds.length > 8 ||
      !value.factIds.every((id) => validId(id, 160)) || new Set(value.factIds).size !== value.factIds.length ||
      !Array.isArray(value.evidenceIds) || value.evidenceIds.length === 0 || value.evidenceIds.length > 8 ||
      !value.evidenceIds.every((id) => sourceIds.has(id)) ||
      !Array.isArray(value.sceneTags) || value.sceneTags.length > 12 ||
      !value.sceneTags.every((tag) => sceneFacets.has(tag)) ||
      !Array.isArray(value.photoThemeTags) || value.photoThemeTags.length > 8 ||
      !value.photoThemeTags.every((tag) => boundedString(tag, 1, 32))) return false;
  if (value.placeId !== undefined && value.placeId !== null && !validId(value.placeId)) return false;
  if (value.coordinate !== undefined && value.coordinate !== null && !validCoordinate(value.coordinate)) return false;
  if (value.startsAt !== undefined && value.startsAt !== null && !validDate(value.startsAt)) return false;
  if (value.endsAt !== undefined && value.endsAt !== null && !validDate(value.endsAt)) return false;
  return !(value.startsAt != null && value.endsAt != null && Date.parse(value.endsAt) < Date.parse(value.startsAt));
}

export function validRegionBriefRequest(body) {
  return exactKeys(body, requestKeys) && body.contractVersion === contractVersion &&
    validSnapshotId(body.snapshotId) && activationTypes.has(body.activationType) &&
    typeof body.locale === 'string' && /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(body.locale) &&
    validRegion(body.region) && validProfile(body.sceneProfile) &&
    Array.isArray(body.requestedSections) && body.requestedSections.length > 0 &&
    body.requestedSections.length <= sectionNames.size &&
    body.requestedSections.every((section) => sectionNames.has(section)) &&
    new Set(body.requestedSections).size === body.requestedSections.length;
}

export function regionBriefGrid({ latitude, longitude }) {
  if (!finiteIn(latitude, -90, 90) || !finiteIn(longitude, -180, 180)) return null;
  // This is deliberately the same roughly-5 km grid used by Discovery jobs;
  // it binds a request to a remembered snapshot without retaining raw GPS.
  return `g${Math.floor(latitude / 0.05)}:${Math.floor(longitude / 0.05)}`;
}

export function validRegionBriefResponse(body) {
  if (!exactKeys(body, responseKeys) || body.contractVersion !== contractVersion ||
      !validId(body.briefId) || !validId(body.regionId) || !boundedString(body.regionName, 1, 160) ||
      !validProfile(body.profile) || !validDate(body.generatedAt) || !validDate(body.expiresAt) ||
      Date.parse(body.expiresAt) <= Date.parse(body.generatedAt) || !briefStatuses.has(body.status) ||
      !completenessStates.has(body.completeness) ||
      (body.identity !== null && !validTextBlock(body.identity)) ||
      (body.orientation !== null && !validTextBlock(body.orientation)) ||
      !Array.isArray(body.photoThemes) || body.photoThemes.length > 5 ||
      !body.photoThemes.every((theme) => allowedKeys(theme, new Set(['id', 'label'])) && validId(theme.id) && boundedString(theme.label, 1, 32)) ||
      !Array.isArray(body.sources) || body.sources.length > 40 || !body.sources.every(validSource) ||
      !Array.isArray(body.insights) || body.insights.length > 40 || !exactKeys(body.refresh, refreshKeys) ||
      !Array.isArray(body.refresh.refreshingMissions) || body.refresh.refreshingMissions.length > 9 ||
      !body.refresh.refreshingMissions.every((mission) => boundedString(mission, 1, 64)) ||
      (body.refresh.retryAfterSeconds !== null && (!Number.isInteger(body.refresh.retryAfterSeconds) || body.refresh.retryAfterSeconds < 1 || body.refresh.retryAfterSeconds > 3600))) return false;
  const sourceIds = new Set(body.sources.map((source) => source.id));
  if (sourceIds.size !== body.sources.length || !body.insights.every((insight) => validInsight(insight, sourceIds))) return false;
  if (body.status === 'pending' || body.status === 'unavailable') {
    return body.identity === null && body.orientation === null && body.photoThemes.length === 0 && body.insights.length === 0 && body.sources.length === 0;
  }
  if (!validTextBlock(body.identity) || !validTextBlock(body.orientation)) return false;
  const factIds = new Set(body.insights.flatMap((insight) => insight.factIds));
  return [...body.identity.factIds, ...body.orientation.factIds].every((id) => factIds.has(id));
}

export const regionBriefContractVersion = contractVersion;
