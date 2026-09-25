import { createHash } from 'node:crypto';

export const supportedProviderSourceIds = Object.freeze([
  'sentinel1',
  'sentinel2',
  'cams',
  'aeronet',
  'officialNotices',
  'osm',
  'wikidata',
  'wikimediaCommons',
  'gbif',
  'inaturalist',
  'ebird',
  'firms',
  'copernicusMarine',
  'jplHorizons',
  'noaaSwpc',
]);

const providerIdSet = new Set(supportedProviderSourceIds);
const secretFields = Object.freeze([
  'sentinelRasterToken',
  'camsApiKey',
  'officialNoticeGatewayToken',
  'ebirdToken',
  'firmsMapKey',
  'marineApiKey',
]);
const urlFields = Object.freeze([
  'sentinelStacBaseUrl',
  'sentinelRasterGatewayUrl',
  'camsGatewayUrl',
  'aeronetBaseUrl',
  'officialNoticeGatewayUrl',
  'overpassUrl',
  'wikidataEndpoint',
  'commonsApiUrl',
  'gbifBaseUrl',
  'inaturalistBaseUrl',
  'ebirdBaseUrl',
  'firmsBaseUrl',
  'marineGatewayUrl',
  'horizonsBaseUrl',
  'swpcBaseUrl',
]);
const optionalUrlFields = new Set([
  'sentinelRasterGatewayUrl',
  'camsGatewayUrl',
  'officialNoticeGatewayUrl',
  'marineGatewayUrl',
]);
const allowedFields = new Set([
  'enabled',
  'enabledProviders',
  'timeoutMs',
  ...urlFields,
  ...secretFields,
  'officialNoticeSources',
]);
const officialKinds = new Set([
  'closure',
  'roadClosure',
  'fireRestriction',
  'regulation',
  'reopening',
  'eventChange',
]);

function environmentValue(environment, name, fallback = '') {
  const value = environment?.[name];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : fallback;
}

// docs/core-1.0-scope.md §5 fixes which providers may run by default. The rest
// keep their adapters but stay closed until each has a named user value chain;
// an adapter existing in the tree is not a reason to call it upstream.
const defaultEnabledProviders = Object.freeze([
  'osm',
  'wikidata',
  'wikimediaCommons',
  'officialNotices',
  'gbif',
  'inaturalist',
]);

export function providerSourceDefaults(environment = {}) {
  return {
    enabled: true,
    enabledProviders: defaultEnabledProviders,
    timeoutMs: 8_000,
    sentinelStacBaseUrl: environmentValue(
      environment,
      'LUMANEST_SENTINEL_STAC_URL',
      'https://stac.dataspace.copernicus.eu/v1',
    ),
    sentinelRasterGatewayUrl: environmentValue(environment, 'LUMANEST_SENTINEL_RASTER_GATEWAY_URL'),
    sentinelRasterToken: environmentValue(environment, 'LUMANEST_SENTINEL_RASTER_TOKEN'),
    camsGatewayUrl: environmentValue(environment, 'LUMANEST_CAMS_GATEWAY_URL'),
    camsApiKey: environmentValue(environment, 'LUMANEST_CAMS_API_KEY'),
    aeronetBaseUrl: environmentValue(
      environment,
      'LUMANEST_AERONET_BASE_URL',
      'https://aeronet.gsfc.nasa.gov',
    ),
    officialNoticeGatewayUrl: environmentValue(environment, 'LUMANEST_OFFICIAL_NOTICE_GATEWAY_URL'),
    officialNoticeGatewayToken: environmentValue(environment, 'LUMANEST_OFFICIAL_NOTICE_GATEWAY_TOKEN'),
    officialNoticeSources: [],
    overpassUrl: environmentValue(
      environment,
      'LUMANEST_OVERPASS_URL',
      'https://overpass-api.de/api/interpreter',
    ),
    wikidataEndpoint: environmentValue(
      environment,
      'LUMANEST_WIKIDATA_SPARQL_URL',
      'https://query.wikidata.org/sparql',
    ),
    commonsApiUrl: environmentValue(
      environment,
      'LUMANEST_COMMONS_API_URL',
      'https://commons.wikimedia.org/w/api.php',
    ),
    gbifBaseUrl: environmentValue(environment, 'LUMANEST_GBIF_BASE_URL', 'https://api.gbif.org'),
    inaturalistBaseUrl: environmentValue(
      environment,
      'LUMANEST_INATURALIST_BASE_URL',
      'https://api.inaturalist.org',
    ),
    ebirdBaseUrl: environmentValue(environment, 'LUMANEST_EBIRD_BASE_URL', 'https://api.ebird.org'),
    ebirdToken: environmentValue(environment, 'LUMANEST_EBIRD_API_TOKEN'),
    firmsBaseUrl: environmentValue(
      environment,
      'LUMANEST_FIRMS_BASE_URL',
      'https://firms.modaps.eosdis.nasa.gov',
    ),
    firmsMapKey: environmentValue(environment, 'LUMANEST_FIRMS_MAP_KEY'),
    marineGatewayUrl: environmentValue(environment, 'LUMANEST_COPERNICUS_MARINE_GATEWAY_URL'),
    marineApiKey: environmentValue(environment, 'LUMANEST_COPERNICUS_MARINE_API_KEY'),
    horizonsBaseUrl: environmentValue(
      environment,
      'LUMANEST_JPL_HORIZONS_URL',
      'https://ssd.jpl.nasa.gov',
    ),
    swpcBaseUrl: environmentValue(
      environment,
      'LUMANEST_SWPC_BASE_URL',
      'https://services.swpc.noaa.gov',
    ),
  };
}

function boundedText(value, name, maximum) {
  if (typeof value !== 'string') throw new TypeError(`${name} must be a string`);
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximum || /[\u0000-\u001f\u007f]/.test(normalized)) {
    throw new TypeError(`${name} is invalid`);
  }
  return normalized;
}

function httpsUrl(value, name, { optional = false } = {}) {
  if (optional && (value == null || value === '')) return '';
  const text = boundedText(value, name, 2_048);
  let url;
  try {
    url = new URL(text);
  } catch {
    throw new TypeError(`${name} must be an HTTPS URL`);
  }
  if (url.protocol !== 'https:' || url.username || url.password || !url.hostname) {
    throw new TypeError(`${name} must be an HTTPS URL without credentials`);
  }
  return url.toString().replace(/\/$/, '');
}

function secret(value, name) {
  if (value == null || value === '') return '';
  if (typeof value !== 'string' || value.trim().length > 512 || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new TypeError(`${name} is invalid`);
  }
  return value.trim();
}

function finite(value, minimum, maximum, name, { integer = false } = {}) {
  if (typeof value !== 'number' || !Number.isFinite(value) ||
      (integer && !Number.isInteger(value)) || value < minimum || value > maximum) {
    throw new RangeError(`${name} must be between ${minimum} and ${maximum}`);
  }
  return value;
}

function validateCoverage(value, sourceId) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${sourceId}.coverage must be an object`);
  }
  const allowed = new Set(['latitude', 'longitude', 'radiusKm', 'regionCodes']);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new TypeError(`${sourceId}.coverage contains an unknown field`);
  }
  const regionCodes = value.regionCodes ?? [];
  if (!Array.isArray(regionCodes) || regionCodes.length > 32 ||
      regionCodes.some((code) => typeof code !== 'string' || !/^[0-9A-Za-z_-]{2,24}$/.test(code))) {
    throw new TypeError(`${sourceId}.coverage.regionCodes is invalid`);
  }
  return Object.freeze({
    latitude: finite(value.latitude, -90, 90, `${sourceId}.coverage.latitude`),
    longitude: finite(value.longitude, -180, 180, `${sourceId}.coverage.longitude`),
    radiusKm: finite(value.radiusKm, 1, 2_000, `${sourceId}.coverage.radiusKm`),
    regionCodes: Object.freeze([...new Set(regionCodes)]),
  });
}

function validateOfficialSource(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('official notice source must be an object');
  }
  const allowed = new Set([
    'id', 'name', 'feedUrl', 'homepageUrl', 'format', 'enabled', 'authoritative',
    'promoteToSafety', 'allowDefaultSafetyExpiry', 'defaultExpiryMinutes',
    'refreshMinutes', 'coverage', 'allowedKinds',
  ]);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new TypeError('official notice source contains an unknown field');
  }
  const id = boundedText(value.id, 'official source id', 64);
  if (!/^[a-z0-9][a-z0-9._-]*$/.test(id)) throw new TypeError('official source id is invalid');
  const format = value.format ?? 'jsonFeed';
  if (!['jsonFeed', 'rss', 'atom'].includes(format)) throw new TypeError(`${id}.format is invalid`);
  const allowedKinds = value.allowedKinds ?? [...officialKinds];
  if (!Array.isArray(allowedKinds) || allowedKinds.length === 0 || allowedKinds.length > officialKinds.size ||
      allowedKinds.some((kind) => !officialKinds.has(kind))) {
    throw new TypeError(`${id}.allowedKinds is invalid`);
  }
  const authoritative = value.authoritative === true;
  const promoteToSafety = value.promoteToSafety === true;
  if (promoteToSafety && !authoritative) {
    throw new TypeError(`${id} cannot promote a non-authoritative source`);
  }
  return Object.freeze({
    id,
    name: boundedText(value.name, `${id}.name`, 120),
    feedUrl: httpsUrl(value.feedUrl, `${id}.feedUrl`),
    homepageUrl: httpsUrl(value.homepageUrl, `${id}.homepageUrl`),
    format,
    enabled: value.enabled !== false,
    authoritative,
    promoteToSafety,
    allowDefaultSafetyExpiry: value.allowDefaultSafetyExpiry === true,
    defaultExpiryMinutes: finite(
      value.defaultExpiryMinutes ?? 360,
      15,
      1_440,
      `${id}.defaultExpiryMinutes`,
      { integer: true },
    ),
    refreshMinutes: finite(
      value.refreshMinutes ?? 30,
      15,
      1_440,
      `${id}.refreshMinutes`,
      { integer: true },
    ),
    coverage: validateCoverage(value.coverage, id),
    allowedKinds: Object.freeze([...new Set(allowedKinds)]),
  });
}

function deepFreeze(value) {
  if (value == null || typeof value !== 'object' || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const item of Object.values(value)) deepFreeze(item);
  return value;
}

export function validateProviderSources(input = {}, { partial = false, base = null } = {}) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new TypeError('providerSources must be an object');
  }
  for (const name of Object.keys(input)) {
    if (!allowedFields.has(name)) throw new TypeError(`Unknown provider source field: ${name}`);
  }
  const result = partial
    ? {}
    : { ...providerSourceDefaults(), ...(base ?? {}) };
  for (const [name, value] of Object.entries(input)) {
    if (name === 'enabled') {
      if (typeof value !== 'boolean') throw new TypeError('providerSources.enabled must be a boolean');
      result.enabled = value;
    } else if (name === 'enabledProviders') {
      if (!Array.isArray(value) || value.length > supportedProviderSourceIds.length ||
          value.some((id) => !providerIdSet.has(id)) || new Set(value).size !== value.length) {
        throw new TypeError('enabledProviders is invalid');
      }
      result.enabledProviders = [...value];
    } else if (name === 'timeoutMs') {
      result.timeoutMs = finite(value, 2_000, 30_000, 'providerSources.timeoutMs', { integer: true });
    } else if (urlFields.includes(name)) {
      result[name] = httpsUrl(value, name, { optional: optionalUrlFields.has(name) });
    } else if (secretFields.includes(name)) {
      result[name] = secret(value, name);
    } else if (name === 'officialNoticeSources') {
      if (!Array.isArray(value) || value.length > 32) {
        throw new TypeError('officialNoticeSources must be an array with at most 32 entries');
      }
      const sources = value.map(validateOfficialSource);
      if (new Set(sources.map((item) => item.id)).size !== sources.length ||
          new Set(sources.map((item) => item.feedUrl)).size !== sources.length) {
        throw new TypeError('officialNoticeSources contains duplicate IDs or feeds');
      }
      result.officialNoticeSources = sources;
    }
  }
  if (partial) return deepFreeze(result);
  result.enabledProviders = Object.freeze([...(result.enabledProviders ?? defaultEnabledProviders)]);
  result.officialNoticeSources = Object.freeze([...(result.officialNoticeSources ?? [])]);
  return deepFreeze(result);
}

export function providerConfigurationFingerprint(configuration) {
  const safe = { ...configuration };
  for (const name of secretFields) {
    safe[name] = typeof safe[name] === 'string' && safe[name].length > 0
      ? createHash('sha256').update(safe[name]).digest('hex').slice(0, 12)
      : '';
  }
  return createHash('sha256').update(JSON.stringify(safe)).digest('hex').slice(0, 16);
}

function maskedSecret(value) {
  const configured = typeof value === 'string' && value.length > 0;
  return { configured, lastFour: configured ? [...value].slice(-4).join('') : null };
}

export function safeProviderSources(configuration) {
  const result = {
    enabled: configuration.enabled,
    enabledProviders: [...configuration.enabledProviders],
    timeoutMs: configuration.timeoutMs,
    officialNoticeSources: configuration.officialNoticeSources.map((source) => ({
      ...source,
      coverage: { ...source.coverage, regionCodes: [...source.coverage.regionCodes] },
      allowedKinds: [...source.allowedKinds],
    })),
  };
  for (const name of urlFields) result[name] = configuration[name];
  for (const name of secretFields) result[name] = maskedSecret(configuration[name]);
  return result;
}

export function providerConfigured(id, configuration) {
  if (!configuration.enabled || !configuration.enabledProviders.includes(id)) return false;
  return switchProvider(id, configuration);
}

function switchProvider(id, configuration) {
  switch (id) {
    case 'sentinel1':
    case 'sentinel2':
      return Boolean(configuration.sentinelStacBaseUrl);
    case 'cams':
      return Boolean(configuration.camsGatewayUrl);
    case 'aeronet':
      return Boolean(configuration.aeronetBaseUrl);
    case 'officialNotices':
      return Boolean(configuration.officialNoticeGatewayUrl) ||
        configuration.officialNoticeSources.some((source) => source.enabled);
    case 'osm':
      return Boolean(configuration.overpassUrl);
    case 'wikidata':
      return Boolean(configuration.wikidataEndpoint);
    case 'wikimediaCommons':
      return Boolean(configuration.commonsApiUrl);
    case 'gbif':
      return Boolean(configuration.gbifBaseUrl);
    case 'inaturalist':
      return Boolean(configuration.inaturalistBaseUrl);
    case 'ebird':
      return Boolean(configuration.ebirdBaseUrl && configuration.ebirdToken);
    case 'firms':
      return Boolean(configuration.firmsBaseUrl && configuration.firmsMapKey);
    case 'copernicusMarine':
      return Boolean(configuration.marineGatewayUrl);
    case 'jplHorizons':
      return Boolean(configuration.horizonsBaseUrl);
    case 'noaaSwpc':
      return Boolean(configuration.swpcBaseUrl);
    default:
      return false;
  }
}

export function publicProviderSourceCatalog() {
  const labels = {
    sentinel1: 'Sentinel-1 雷达目录',
    sentinel2: 'Sentinel-2 光学与派生指数',
    cams: 'CAMS 大气成分',
    aeronet: 'NASA AERONET',
    officialNotices: '官方公告',
    osm: 'OpenStreetMap',
    wikidata: 'Wikidata',
    wikimediaCommons: 'Wikimedia Commons',
    gbif: 'GBIF',
    inaturalist: 'iNaturalist',
    ebird: 'eBird（可选）',
    firms: 'NASA FIRMS',
    copernicusMarine: 'Copernicus Marine',
    jplHorizons: 'JPL Horizons',
    noaaSwpc: 'NOAA SWPC',
  };
  return supportedProviderSourceIds.map((id) => ({ id, label: labels[id] }));
}
