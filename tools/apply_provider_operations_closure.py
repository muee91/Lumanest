from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    content = read(path)
    if content.count(old) != 1:
        raise RuntimeError(f"Expected one match in {path}: {old[:120]!r}, found {content.count(old)}")
    write(path, content.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    content = read(path)
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"Expected one regex match in {path}: {pattern[:120]!r}, found {count}")
    write(path, updated)


# ---------------------------------------------------------------------------
# Runtime configuration: encrypted Provider Hub endpoints and credentials.
# ---------------------------------------------------------------------------
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "import { defaultDiscoverySearchProfile, validateDiscoverySearchProfile } from '../discovery/search-profile.mjs';\n",
    "import { defaultDiscoverySearchProfile, validateDiscoverySearchProfile } from '../discovery/search-profile.mjs';\n"
    "import { providerSourceDefaults, validateProviderSources } from '../environment/provider-runtime-config.mjs';\n",
)
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "  'discoverySearchProfile',\n  'settings',\n]);",
    "  'discoverySearchProfile',\n  'providerSources',\n  'settings',\n]);",
)
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "    if (name === 'discoverySearchProfile') {\n      if (value == null || typeof value !== 'object' || Array.isArray(value)) {\n        throw new TypeError('discoverySearchProfile must be an object');\n      }\n      continue;\n    }\n    if (typeof value !== 'string') {",
    "    if (name === 'discoverySearchProfile') {\n      if (value == null || typeof value !== 'object' || Array.isArray(value)) {\n        throw new TypeError('discoverySearchProfile must be an object');\n      }\n      continue;\n    }\n    if (name === 'providerSources') {\n      validateProviderSources(value, { partial: true });\n      continue;\n    }\n    if (typeof value !== 'string') {",
)
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "    } else if (name === 'discoverySearchProfile') {\n      result.discoverySearchProfile = {\n        ...(result.discoverySearchProfile ?? {}),\n        ...value,\n      };\n      if (value.apiKey === undefined && result.discoverySearchProfile.apiKey === undefined &&\n          current.discoverySearchProfile?.apiKey !== undefined) {\n        result.discoverySearchProfile.apiKey = current.discoverySearchProfile.apiKey;\n      }\n    } else {",
    "    } else if (name === 'discoverySearchProfile') {\n      result.discoverySearchProfile = {\n        ...(result.discoverySearchProfile ?? {}),\n        ...value,\n      };\n      if (value.apiKey === undefined && result.discoverySearchProfile.apiKey === undefined &&\n          current.discoverySearchProfile?.apiKey !== undefined) {\n        result.discoverySearchProfile.apiKey = current.discoverySearchProfile.apiKey;\n      }\n    } else if (name === 'providerSources') {\n      result.providerSources = {\n        ...(result.providerSources ?? {}),\n        ...value,\n      };\n    } else {",
)
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "  const discoverySearchProfile = validateDiscoverySearchProfile({\n    ...defaultDiscoverySearchProfile(),\n    ...(overrides.discoverySearchProfile ?? {}),\n  });\n  const effective = {",
    "  const discoverySearchProfile = validateDiscoverySearchProfile({\n    ...defaultDiscoverySearchProfile(),\n    ...(overrides.discoverySearchProfile ?? {}),\n  });\n  const providerSources = validateProviderSources({\n    ...providerSourceDefaults(),\n    ...(defaults.providerSources ?? {}),\n    ...(overrides.providerSources ?? {}),\n  });\n  const effective = {",
)
replace_once(
    "services/lumanest-data-broker/src/admin/runtime-config.mjs",
    "    discoverySearchProfile,\n    contextServiceUrl:",
    "    discoverySearchProfile,\n    providerSources,\n    contextServiceUrl:",
)

# ---------------------------------------------------------------------------
# Provider Facts: dynamic config, strict gateways, official feeds, metrics.
# ---------------------------------------------------------------------------
replace_once(
    "services/lumanest-data-broker/src/environment/provider-facts-service.mjs",
    "import { createHash } from 'node:crypto';\n",
    "import { createHash } from 'node:crypto';\n\n"
    "import { loadOfficialNoticeItems, officialNoticeSafetyKinds } from './official-notice-feed.mjs';\n"
    "import {\n"
    "  providerConfigured,\n"
    "  providerConfigurationFingerprint,\n"
    "  providerSourceDefaults,\n"
    "  publicProviderSourceCatalog,\n"
    "  validateProviderSources,\n"
    "} from './provider-runtime-config.mjs';\n",
)
replace_once(
    "services/lumanest-data-broker/src/environment/provider-facts-service.mjs",
    "function cacheKey(query) {\n  return [\n    query.latitude.toFixed(2), query.longitude.toFixed(2), query.radiusKm,\n    query.locale, query.providerIds.join(','),\n  ].join(':');\n}",
    "function cacheKey(query, configurationFingerprint = '') {\n  return [\n    query.latitude.toFixed(2), query.longitude.toFixed(2), query.radiusKm,\n    query.locale, query.providerIds.join(','), configurationFingerprint,\n  ].join(':');\n}",
)

new_gateway_functions = r'''async function normalizedGatewayProvider({
  id,
  category,
  url,
  token = '',
  query,
  fetcher,
  timeoutMs,
  now,
  sourceInfo,
  allowedKinds = null,
  allowedVerifications = null,
}) {
  if (!url) return unconfigured(id, category, now);
  try {
    const endpoint = new URL(url);
    endpoint.searchParams.set('lat', String(query.latitude));
    endpoint.searchParams.set('lon', String(query.longitude));
    endpoint.searchParams.set('radiusKm', String(query.radiusKm));
    endpoint.searchParams.set('at', query.observedAt);
    endpoint.searchParams.set('locale', query.locale);
    const headers = { 'User-Agent': 'LumaNest/1.0' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const body = await fetchJson(fetcher, endpoint, { timeoutMs, headers });
    const items = Array.isArray(body?.signals) ? body.signals : [];
    const normalized = items.slice(0, 8).map((item) => {
      const kind = boundedText(item?.kind, 64) ?? 'providerSignal';
      const verification = ['authoritative', 'observed', 'model', 'reference', 'candidate'].includes(item?.verification)
        ? item.verification : 'model';
      if (allowedKinds != null && !allowedKinds.has(kind)) return null;
      if (allowedVerifications != null && !allowedVerifications.has(verification)) return null;
      return signal({
        providerId: id,
        kind,
        category,
        title: item?.title,
        summary: item?.summary,
        verification,
        observedAt: item?.observedAt ?? body?.observedAt ?? now,
        expiresAt: item?.expiresAt ?? body?.expiresAt ?? new Date(now.getTime() + readyTtlMs),
        sourceUrl: item?.sourceUrl ?? body?.sourceUrl ?? sourceInfo.url,
      });
    }).filter(Boolean);
    return normalized.length === 0
      ? noData(id, category, now, sourceInfo)
      : providerResult({ id, category, status: 'ready', now, ttlMs: readyTtlMs, sourceInfo, signals: normalized });
  } catch {
    return unavailable(id, category, now);
  }
}

async function officialNoticesProvider({ query, fetcher, timeoutMs, now, configuration }) {
  const id = 'officialNotices';
  const category = 'operations';
  if (configuration.officialNoticeGatewayUrl) {
    return normalizedGatewayProvider({
      id,
      category,
      url: configuration.officialNoticeGatewayUrl,
      token: configuration.officialNoticeGatewayToken,
      query,
      fetcher,
      timeoutMs,
      now,
      sourceInfo: source({
        id: 'official-notice-gateway',
        title: 'Reviewed official notices',
        publisher: 'Configured government and venue sources',
        url: configuration.officialNoticeGatewayUrl,
        license: 'Source-specific',
        version: 'normalized gateway v1',
      }),
      allowedKinds: new Set(['closure', 'roadClosure', 'fireRestriction', 'regulation', 'reopening', 'eventChange']),
      allowedVerifications: new Set(['authoritative', 'reference']),
    });
  }
  const enabledSources = configuration.officialNoticeSources.filter((item) => item.enabled);
  if (enabledSources.length === 0) return unconfigured(id, category, now, '需要在控制台配置审核公告源');
  const sourceInfo = source({
    id: 'official-notice-registry',
    title: 'Reviewed official notice feeds',
    publisher: 'Configured government and venue sources',
    url: enabledSources[0].homepageUrl,
    license: 'Source-specific',
    version: 'feed registry v1',
  });
  try {
    const loaded = await loadOfficialNoticeItems({
      sources: enabledSources,
      query,
      fetcher,
      timeoutMs,
      now,
    });
    if (loaded.items.length === 0) {
      return loaded.checkedSources > 0 && loaded.unavailableSources === loaded.checkedSources
        ? unavailable(id, category, now)
        : noData(id, category, now, sourceInfo, '当前范围没有仍有效的官方公告');
    }
    return providerResult({
      id,
      category,
      status: 'ready',
      now,
      ttlMs: readyTtlMs,
      sourceInfo,
      signals: loaded.items.map((item) => signal({
        providerId: id,
        kind: item.kind,
        category,
        title: item.title,
        summary: item.summary,
        verification: item.safetyEligible || (item.authoritative && !officialNoticeSafetyKinds.has(item.kind))
          ? 'authoritative' : 'reference',
        observedAt: item.observedAt,
        expiresAt: item.expiresAt,
        sourceUrl: item.sourceUrl,
      })),
    });
  } catch {
    return unavailable(id, category, now);
  }
}

function finiteMetadata(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

async function sentinelRasterSignals({ query, fetcher, timeoutMs, now, url, token }) {
  if (!url) return [];
  try {
    const endpoint = new URL(url);
    endpoint.searchParams.set('lat', String(query.latitude));
    endpoint.searchParams.set('lon', String(query.longitude));
    endpoint.searchParams.set('radiusKm', String(query.radiusKm));
    endpoint.searchParams.set('at', query.observedAt);
    const headers = { 'User-Agent': 'LumaNest/1.0 SentinelRasterClient' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const body = await fetchJson(fetcher, endpoint, { timeoutMs, headers });
    const observations = Array.isArray(body?.observations) ? body.observations : [];
    const metrics = {
      ndvi: ['vegetationIndexChange', '植被指数变化', 'NDVI'],
      ndsi: ['snowIndexChange', '积雪指数变化', 'NDSI'],
      ndwi: ['waterIndexChange', '水体指数变化', 'NDWI'],
      surfaceChange: ['surfaceChange', '地表变化线索', '变化指数'],
    };
    return observations.slice(0, 4).flatMap((item) => {
      const definition = metrics[item?.metric];
      const observedAt = iso(item?.observedAt);
      const comparisonStart = iso(item?.comparisonStart);
      const comparisonEnd = iso(item?.comparisonEnd);
      const sourceUrl = boundedUrl(item?.sourceUrl);
      const delta = Number(item?.delta);
      const cloudCoverage = Number(item?.cloudCoverage);
      const resolution = Number(item?.spatialResolutionMeters);
      const confidence = ['limited', 'medium', 'high'].includes(item?.confidence)
        ? item.confidence : null;
      if (definition == null || !observedAt || !comparisonStart || !comparisonEnd || !sourceUrl ||
          Date.parse(comparisonEnd) <= Date.parse(comparisonStart) ||
          !finiteMetadata(delta, -2, 2) || !finiteMetadata(cloudCoverage, 0, 100) ||
          !finiteMetadata(resolution, 1, 1_000) || confidence == null) return [];
      const sign = delta > 0 ? '+' : '';
      const summary = `${comparisonStart.slice(0, 10)} 至 ${comparisonEnd.slice(0, 10)} 的 ${definition[2]} 差值为 ${sign}${delta.toFixed(3)}，云量约 ${Math.round(cloudCoverage)}%，空间分辨率 ${Math.round(resolution)} 米，置信等级 ${confidence}。这是遥感变化线索，不代表现场已进入最佳状态。`;
      return [signal({
        providerId: 'sentinel2',
        kind: definition[0],
        category: 'surface',
        title: definition[1],
        summary,
        verification: confidence === 'high' ? 'observed' : 'model',
        observedAt,
        expiresAt: item?.expiresAt ?? new Date(now.getTime() + 24 * 60 * 60 * 1_000),
        sourceUrl,
      })].filter(Boolean);
    });
  } catch {
    return [];
  }
}

function parseAeronet'''
regex_once(
    "services/lumanest-data-broker/src/environment/provider-facts-service.mjs",
    r"async function normalizedGatewayProvider\([\s\S]*?\n}\n\nfunction parseAeronet",
    new_gateway_functions,
)

new_provider_class = r'''export class ProviderFactsService {
  constructor({
    fetcher = fetch,
    now = () => new Date(),
    timeoutMs = 12_000,
    cache = new Map(),
    configuration = null,
    sentinelStacBaseUrl = configuredUrl(process.env.LUMANEST_SENTINEL_STAC_URL) || 'https://stac.dataspace.copernicus.eu/v1',
    sentinelRasterGatewayUrl = configuredUrl(process.env.LUMANEST_SENTINEL_RASTER_GATEWAY_URL),
    sentinelRasterToken = configuredToken(process.env.LUMANEST_SENTINEL_RASTER_TOKEN),
    camsGatewayUrl = configuredUrl(process.env.LUMANEST_CAMS_GATEWAY_URL),
    camsApiKey = configuredToken(process.env.LUMANEST_CAMS_API_KEY),
    aeronetBaseUrl = configuredUrl(process.env.LUMANEST_AERONET_BASE_URL) || 'https://aeronet.gsfc.nasa.gov',
    officialNoticeGatewayUrl = configuredUrl(process.env.LUMANEST_OFFICIAL_NOTICE_GATEWAY_URL),
    officialNoticeGatewayToken = configuredToken(process.env.LUMANEST_OFFICIAL_NOTICE_GATEWAY_TOKEN),
    officialNoticeSources = [],
    overpassUrl = configuredUrl(process.env.LUMANEST_OVERPASS_URL) || 'https://overpass-api.de/api/interpreter',
    wikidataEndpoint = configuredUrl(process.env.LUMANEST_WIKIDATA_SPARQL_URL) || 'https://query.wikidata.org/sparql',
    commonsApiUrl = configuredUrl(process.env.LUMANEST_COMMONS_API_URL) || 'https://commons.wikimedia.org/w/api.php',
    gbifBaseUrl = configuredUrl(process.env.LUMANEST_GBIF_BASE_URL) || 'https://api.gbif.org',
    ebirdBaseUrl = configuredUrl(process.env.LUMANEST_EBIRD_BASE_URL) || 'https://api.ebird.org',
    ebirdToken = configuredToken(process.env.LUMANEST_EBIRD_API_TOKEN),
    firmsBaseUrl = configuredUrl(process.env.LUMANEST_FIRMS_BASE_URL) || 'https://firms.modaps.eosdis.nasa.gov',
    firmsMapKey = configuredToken(process.env.LUMANEST_FIRMS_MAP_KEY, 128),
    marineGatewayUrl = configuredUrl(process.env.LUMANEST_COPERNICUS_MARINE_GATEWAY_URL),
    marineApiKey = configuredToken(process.env.LUMANEST_COPERNICUS_MARINE_API_KEY),
    horizonsBaseUrl = configuredUrl(process.env.LUMANEST_JPL_HORIZONS_URL) || 'https://ssd.jpl.nasa.gov',
    swpcBaseUrl = configuredUrl(process.env.LUMANEST_SWPC_BASE_URL) || 'https://services.swpc.noaa.gov',
  } = {}) {
    this.fetcher = fetcher;
    this.now = now;
    this.defaultTimeoutMs = timeoutMs;
    this.cache = cache;
    const fallback = validateProviderSources({
      ...providerSourceDefaults(),
      sentinelStacBaseUrl,
      sentinelRasterGatewayUrl,
      sentinelRasterToken,
      camsGatewayUrl,
      camsApiKey,
      aeronetBaseUrl,
      officialNoticeGatewayUrl,
      officialNoticeGatewayToken,
      officialNoticeSources,
      overpassUrl,
      wikidataEndpoint,
      commonsApiUrl,
      gbifBaseUrl,
      ebirdBaseUrl,
      ebirdToken,
      firmsBaseUrl,
      firmsMapKey,
      marineGatewayUrl,
      marineApiKey,
      horizonsBaseUrl,
      swpcBaseUrl,
    });
    this.configuration = typeof configuration === 'function'
      ? () => validateProviderSources(configuration(), { base: fallback })
      : () => fallback;
    this.inFlight = new Map();
    this.metrics = new Map(providerIds.map((id) => [id, {
      requestTotal: 0,
      readyTotal: 0,
      noDataTotal: 0,
      unavailableTotal: 0,
      unconfiguredTotal: 0,
      lastStatus: 'unknown',
      lastSuccessAt: null,
      lastFailureAt: null,
      lastLatencyMs: null,
      lastSignalCount: 0,
      lastErrorCode: null,
    }]));
    this.cacheMetrics = { hits: 0, misses: 0, coalesced: 0 };
  }

  async facts(query) {
    const now = this.now();
    const configuration = this.configuration();
    const key = cacheKey(query, providerConfigurationFingerprint(configuration));
    const cached = readCache(this.cache, key, now);
    if (cached != null) {
      this.cacheMetrics.hits += 1;
      return { ...cached, cacheStatus: 'hit' };
    }
    if (this.inFlight.has(key)) {
      this.cacheMetrics.coalesced += 1;
      const coalesced = await this.inFlight.get(key);
      return { ...structuredClone(coalesced), cacheStatus: 'coalesced' };
    }
    this.cacheMetrics.misses += 1;
    const request = this.#load(query, now, configuration).then((value) => {
      writeCache(this.cache, key, value);
      return value;
    }).finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, request);
    return request;
  }

  async #load(query, now, configuration) {
    const timeoutMs = Math.min(this.defaultTimeoutMs, configuration.timeoutMs);
    const calls = {
      sentinel1: () => sentinelProvider({ id: 'sentinel1', collection: 'sentinel-1-grd', query, fetcher: this.fetcher, timeoutMs, now, stacBaseUrl: configuration.sentinelStacBaseUrl }),
      sentinel2: () => sentinelProvider({ id: 'sentinel2', collection: 'sentinel-2-l2a', query, fetcher: this.fetcher, timeoutMs, now, stacBaseUrl: configuration.sentinelStacBaseUrl }),
      cams: () => normalizedGatewayProvider({
        id: 'cams', category: 'atmosphere', url: configuration.camsGatewayUrl,
        token: configuration.camsApiKey, query, fetcher: this.fetcher, timeoutMs, now,
        sourceInfo: source({ id: 'copernicus-cams', title: 'CAMS atmospheric composition', publisher: 'Copernicus Atmosphere Monitoring Service', url: 'https://ads.atmosphere.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway v1' }),
        allowedKinds: new Set(['aerosolOpticalDepth', 'dustLoad', 'blackCarbon', 'smokeTransport', 'visibilityModel']),
        allowedVerifications: new Set(['model', 'observed']),
      }),
      aeronet: () => aeronetProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.aeronetBaseUrl }),
      officialNotices: () => officialNoticesProvider({ query, fetcher: this.fetcher, timeoutMs, now, configuration }),
      osm: () => osmProvider({ query, fetcher: this.fetcher, timeoutMs, now, overpassUrl: configuration.overpassUrl }),
      wikidata: () => wikidataProvider({ query, fetcher: this.fetcher, timeoutMs, now, endpoint: configuration.wikidataEndpoint }),
      wikimediaCommons: () => commonsProvider({ query, fetcher: this.fetcher, timeoutMs, now, apiUrl: configuration.commonsApiUrl }),
      gbif: () => gbifProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.gbifBaseUrl }),
      ebird: () => ebirdProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.ebirdBaseUrl, token: configuration.ebirdToken }),
      firms: () => firmsProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.firmsBaseUrl, mapKey: configuration.firmsMapKey }),
      copernicusMarine: () => normalizedGatewayProvider({
        id: 'copernicusMarine', category: 'marine', url: configuration.marineGatewayUrl,
        token: configuration.marineApiKey, query, fetcher: this.fetcher, timeoutMs, now,
        sourceInfo: source({ id: 'copernicus-marine', title: 'Copernicus Marine Toolbox gateway', publisher: 'Copernicus Marine Service', url: 'https://marine.copernicus.eu/', license: 'Copernicus licence', version: 'configured gateway v1' }),
        allowedKinds: new Set(['significantWaveHeight', 'waveDirection', 'wavePeriod', 'current', 'seaLevelAnomaly']),
        allowedVerifications: new Set(['model', 'observed']),
      }),
      jplHorizons: () => horizonsProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.horizonsBaseUrl }),
      noaaSwpc: () => swpcProvider({ fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.swpcBaseUrl }),
    };
    const providers = await Promise.all(query.providerIds.map(async (id) => {
      const started = Date.now();
      let result;
      if (!configuration.enabled || !configuration.enabledProviders.includes(id)) {
        result = unconfigured(id, 'other', now, '已在控制台关闭');
      } else {
        try {
          result = await calls[id]();
          if (id === 'sentinel2' && result.status === 'ready') {
            const derivatives = await sentinelRasterSignals({
              query,
              fetcher: this.fetcher,
              timeoutMs,
              now,
              url: configuration.sentinelRasterGatewayUrl,
              token: configuration.sentinelRasterToken,
            });
            if (derivatives.length > 0) {
              result = { ...result, signals: [...derivatives, ...result.signals].slice(0, 8) };
            }
          }
        } catch {
          result = unavailable(id, 'other', now);
        }
      }
      this.#record(id, result, Date.now() - started, now);
      return result;
    }));
    const readyCount = providers.filter((item) => item.status === 'ready').length;
    const status = readyCount === 0 ? 'unavailable' : readyCount === providers.length ? 'ready' : 'partial';
    const expiresAt = providers.map((item) => Date.parse(item.expiresAt)).filter(Number.isFinite)
      .reduce((minimum, value) => Math.min(minimum, value), now.getTime() + unavailableTtlMs);
    return {
      contractVersion: 1,
      requestedCoordinate: {
        latitude: Number(query.latitude.toFixed(5)),
        longitude: Number(query.longitude.toFixed(5)),
        system: 'wgs84',
      },
      radiusKm: query.radiusKm,
      generatedAt: now.toISOString(),
      expiresAt: new Date(expiresAt).toISOString(),
      status,
      cacheStatus: 'miss',
      providers,
    };
  }

  #record(id, result, latencyMs, now) {
    const metric = this.metrics.get(id);
    metric.requestTotal += 1;
    metric.lastStatus = result.status;
    metric.lastLatencyMs = latencyMs;
    metric.lastSignalCount = result.signals.length;
    metric[`${result.status}Total`] = (metric[`${result.status}Total`] ?? 0) + 1;
    if (result.status === 'ready' || result.status === 'noData') {
      metric.lastSuccessAt = now.toISOString();
      metric.lastErrorCode = null;
    } else {
      metric.lastFailureAt = now.toISOString();
      metric.lastErrorCode = result.status === 'unconfigured' ? 'not_configured' : 'upstream_unavailable';
    }
  }

  async authoritativeSafetyNotices(query) {
    const result = await this.facts({ ...query, providerIds: ['officialNotices'] });
    const provider = result.providers.find((item) => item.id === 'officialNotices');
    if (provider?.status !== 'ready') return [];
    const now = this.now();
    return provider.signals.flatMap((item) => {
      if (item.verification !== 'authoritative' || !officialNoticeSafetyKinds.has(item.kind) ||
          Date.parse(item.expiresAt) <= now.getTime()) return [];
      const id = createHash('sha256').update(`${item.id}|${item.sourceUrl}`).digest('hex').slice(0, 12);
      const severity = item.kind === 'roadClosure' || item.kind === 'fireRestriction' ? 'warning' : 'caution';
      const guidance = item.kind === 'roadClosure'
        ? ['不要按原路线继续前进', '以交通或景区官方公告为准']
        : item.kind === 'fireRestriction'
          ? ['遵守禁火与封闭要求', '不要进入受限林区或草原']
          : ['确认恢复开放前不要进入', '以发布机构最新公告为准'];
      return [{
        id,
        observedAt: item.observedAt,
        expiresAt: item.expiresAt,
        severity,
        title: item.title,
        description: item.summary,
        guidance,
        source: `官方公告 · ${provider.source?.publisher ?? '审核来源'}`,
      }];
    }).slice(0, 4);
  }

  async testProvider({ providerId, latitude, longitude, radiusKm = 25, locale = 'zh-CN' }) {
    if (!providerIdSet.has(providerId) || !finite(latitude, -90, 90) ||
        !finite(longitude, -180, 180) || !finite(radiusKm, 1, maximumRadiusKm)) {
      return { ok: false, error: 'invalid_request' };
    }
    const started = Date.now();
    const now = this.now();
    const configuration = this.configuration();
    const result = await this.#load({
      latitude,
      longitude,
      radiusKm: Math.round(radiusKm),
      locale,
      observedAt: now.toISOString(),
      providerIds: [providerId],
    }, now, configuration);
    const provider = result.providers[0];
    return {
      ok: provider.status !== 'unavailable',
      providerId,
      status: provider.status,
      signalCount: provider.signals.length,
      latencyMs: Date.now() - started,
      traceId: createHash('sha256').update(`${providerId}|${now.toISOString()}|${provider.status}`).digest('hex').slice(0, 16),
      error: provider.status === 'unavailable' ? 'upstream_unavailable' : null,
    };
  }

  healthSnapshot() {
    const configuration = this.configuration();
    const labels = new Map(publicProviderSourceCatalog().map((item) => [item.id, item.label]));
    return {
      provider: 'providerHub',
      enabled: configuration.enabled,
      checkedAt: this.now().toISOString(),
      configurationRevision: providerConfigurationFingerprint(configuration),
      cache: { ...this.cacheMetrics, entries: this.cache.size, inFlight: this.inFlight.size },
      providers: providerIds.map((id) => ({
        id,
        label: labels.get(id) ?? id,
        enabled: configuration.enabledProviders.includes(id),
        configured: providerConfigured(id, configuration),
        ...structuredClone(this.metrics.get(id)),
      })),
    };
  }

  clearCache() {
    this.cache.clear();
    this.inFlight.clear();
  }

  toPrometheus() {
    const lines = [];
    for (const [id, metric] of this.metrics) {
      lines.push(`lumanest_provider_requests_total{provider="${id}"} ${metric.requestTotal}`);
      lines.push(`lumanest_provider_ready_total{provider="${id}"} ${metric.readyTotal}`);
      lines.push(`lumanest_provider_unavailable_total{provider="${id}"} ${metric.unavailableTotal}`);
      lines.push(`lumanest_provider_last_latency_ms{provider="${id}"} ${metric.lastLatencyMs ?? 0}`);
    }
    lines.push(`lumanest_provider_cache_hits_total ${this.cacheMetrics.hits}`);
    lines.push(`lumanest_provider_cache_misses_total ${this.cacheMetrics.misses}`);
    return `${lines.join('\n')}\n`;
  }
}

export const supportedProviderIds = providerIds;'''
regex_once(
    "services/lumanest-data-broker/src/environment/provider-facts-service.mjs",
    r"export class ProviderFactsService \{[\s\S]*?export const supportedProviderIds = providerIds;",
    new_provider_class,
)

# ---------------------------------------------------------------------------
# Admin API: masked config, provider health and one-provider diagnostics.
# ---------------------------------------------------------------------------
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "import { simulationPresetCatalog } from '../context/simulation.mjs';\n",
    "import { simulationPresetCatalog } from '../context/simulation.mjs';\n"
    "import { providerSourceDefaults, publicProviderSourceCatalog, safeProviderSources } from '../environment/provider-runtime-config.mjs';\n",
)
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "  ['/admin-assets/app.js', ['app.js', 'text/javascript; charset=utf-8']],\n]);",
    "  ['/admin-assets/app.js', ['app.js', 'text/javascript; charset=utf-8']],\n"
    "  ['/admin-assets/providers.js', ['providers.js', 'text/javascript; charset=utf-8']],\n]);",
)
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "    discoverySearch: safeDiscoverySearchProfile(snapshot.discoverySearchProfile),\n    settings:",
    "    discoverySearch: safeDiscoverySearchProfile(snapshot.discoverySearchProfile),\n"
    "    providers: {\n"
    "      catalog: publicProviderSourceCatalog(),\n"
    "      configuration: safeProviderSources(snapshot.providerSources ?? providerSourceDefaults()),\n"
    "    },\n"
    "    settings:",
)
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "  getBrokerHealth = async () => ({ status: 'unknown' }),\n  getAuditLogHealth",
    "  getBrokerHealth = async () => ({ status: 'unknown' }),\n"
    "  getProviderHealth = async () => ({ provider: 'providerHub', enabled: false, providers: [], cache: {} }),\n"
    "  testProvider = async () => ({ ok: false, error: 'not_configured' }),\n"
    "  getAuditLogHealth",
)
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "    if (request.method === 'GET' && url.pathname === '/admin-api/services/7timer') {\n      return json(response, 200, await getSevenTimerHealth());\n    }\n    if (request.method === 'GET' && url.pathname === '/admin-api/health') {\n      const [runtime, sevenTimer] = await Promise.all([getBrokerHealth(), getSevenTimerHealth()]);",
    "    if (request.method === 'GET' && url.pathname === '/admin-api/services/7timer') {\n      return json(response, 200, await getSevenTimerHealth());\n    }\n"
    "    if (request.method === 'GET' && url.pathname === '/admin-api/providers/health') {\n"
    "      return json(response, 200, await getProviderHealth());\n"
    "    }\n"
    "    if (request.method === 'POST' && url.pathname === '/admin-api/providers/test') {\n"
    "      const parsed = await body(request);\n"
    "      if (parsed.tooLarge) return json(response, 413, { error: 'body_too_large' });\n"
    "      const { providerId, latitude, longitude, radiusKm = 25 } = parsed.value ?? {};\n"
    "      if (typeof providerId !== 'string' || typeof latitude !== 'number' || latitude < -90 || latitude > 90 ||\n"
    "          typeof longitude !== 'number' || longitude < -180 || longitude > 180 ||\n"
    "          typeof radiusKm !== 'number' || radiusKm < 1 || radiusKm > 50) {\n"
    "        return json(response, 400, { error: 'invalid_request' });\n"
    "      }\n"
    "      const result = await testProvider({ providerId, latitude, longitude, radiusKm });\n"
    "      auditLog.record({ operation: 'test_provider', fields: ['providerId'], result: result.ok ? 'ok' : result.error, details: { providerId, traceId: result.traceId ?? null } });\n"
    "      return json(response, result.ok ? 200 : result.error === 'invalid_request' ? 400 : 503, result);\n"
    "    }\n"
    "    if (request.method === 'GET' && url.pathname === '/admin-api/health') {\n"
    "      const [runtime, sevenTimer, providerHub] = await Promise.all([getBrokerHealth(), getSevenTimerHealth(), getProviderHealth()]);",
)
replace_once(
    "services/lumanest-data-broker/src/admin/admin-server.mjs",
    "        services: { sevenTimer },\n        audit,",
    "        services: { sevenTimer, providerHub },\n        audit,",
)

# ---------------------------------------------------------------------------
# Admin HTML: Provider Hub configuration/health panels.
# ---------------------------------------------------------------------------
replace_once(
    "services/lumanest-data-broker/src/admin/public/index.html",
    "  <script src=\"/admin-assets/app.js\" defer></script>\n",
    "  <script src=\"/admin-assets/app.js\" defer></script>\n"
    "  <script src=\"/admin-assets/providers.js\" defer></script>\n",
)
provider_form = r'''

            <form id="provider-sources-form" class="settings-card">
              <header class="settings-card-head">
                <div><p class="card-kicker">PROVIDER HUB</p><h3>环境与地区数据源</h3><p>端点与密钥由你在这里录入；密钥加密保存且读取时只返回末四位。</p></div>
                <span class="section-index">03</span>
              </header>
              <div class="credential-layout">
                <section class="settings-group">
                  <div class="group-head"><div><h4>运行控制</h4><p>每个数据源独立失败，不阻塞今日、探索、路线或 AI。</p></div></div>
                  <label class="switch-row"><span><strong>启用 Provider Hub</strong><small>关闭后前端不会请求补充数据</small></span><input name="enabled" type="checkbox"></label>
                  <label>单源超时（毫秒）<input name="timeoutMs" type="number" min="2000" max="30000" value="8000" required></label>
                  <div id="provider-enabled-list" class="fallback-list"></div>
                </section>
                <section class="settings-group">
                  <div class="group-head"><div><h4>卫星与大气</h4><p>Sentinel 目录可直接使用；派生指数和 CAMS 使用受控网关。</p></div></div>
                  <label>Sentinel STAC<input name="sentinelStacBaseUrl" type="url" maxlength="2048" required></label>
                  <label>Sentinel Raster Gateway<input name="sentinelRasterGatewayUrl" type="url" maxlength="2048" placeholder="可留空"></label>
                  <label>Raster Token<input name="sentinelRasterToken" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="sentinelRasterToken"></small></label>
                  <label>CAMS Gateway<input name="camsGatewayUrl" type="url" maxlength="2048" placeholder="可留空"></label>
                  <label>CAMS Token<input name="camsApiKey" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="camsApiKey"></small></label>
                  <label>AERONET Base URL<input name="aeronetBaseUrl" type="url" maxlength="2048" required></label>
                </section>
                <section class="settings-group">
                  <div class="group-head"><div><h4>公告、地图与知识</h4><p>公告可接标准网关，也可录入审核过的 JSON Feed/RSS/Atom 源。</p></div></div>
                  <label>官方公告 Gateway<input name="officialNoticeGatewayUrl" type="url" maxlength="2048" placeholder="可留空"></label>
                  <label>公告 Gateway Token<input name="officialNoticeGatewayToken" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="officialNoticeGatewayToken"></small></label>
                  <label>Overpass<input name="overpassUrl" type="url" maxlength="2048" required></label>
                  <label>Wikidata SPARQL<input name="wikidataEndpoint" type="url" maxlength="2048" required></label>
                  <label>Commons API<input name="commonsApiUrl" type="url" maxlength="2048" required></label>
                  <label>审核公告源（JSON 数组）<textarea name="officialNoticeSources" rows="12" spellcheck="false">[]</textarea><small>每项需包含 id、name、feedUrl、homepageUrl、format、coverage、allowedKinds；只有 authoritative=true 且 promoteToSafety=true 的当前公告可进入安全链。</small></label>
                </section>
                <section class="settings-group">
                  <div class="group-head"><div><h4>生态、火情、海洋与天文</h4><p>所有凭据仅在 Broker 使用，不进入 Flutter。</p></div></div>
                  <label>GBIF<input name="gbifBaseUrl" type="url" maxlength="2048" required></label>
                  <label>eBird<input name="ebirdBaseUrl" type="url" maxlength="2048" required></label>
                  <label>eBird Token<input name="ebirdToken" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="ebirdToken"></small></label>
                  <label>FIRMS<input name="firmsBaseUrl" type="url" maxlength="2048" required></label>
                  <label>FIRMS Map Key<input name="firmsMapKey" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="firmsMapKey"></small></label>
                  <label>Marine Gateway<input name="marineGatewayUrl" type="url" maxlength="2048" placeholder="可留空"></label>
                  <label>Marine Token<input name="marineApiKey" type="password" autocomplete="new-password" placeholder="留空表示不修改"><small data-provider-mask="marineApiKey"></small></label>
                  <label>JPL Horizons<input name="horizonsBaseUrl" type="url" maxlength="2048" required></label>
                  <label>NOAA SWPC<input name="swpcBaseUrl" type="url" maxlength="2048" required></label>
                </section>
              </div>
              <footer class="settings-actions"><p id="provider-console-status" class="status" role="status"></p><button type="submit">保存 Provider 配置</button></footer>
            </form>

            <section class="settings-card">
              <header class="settings-card-head">
                <div><p class="card-kicker">PROVIDER OPERATIONS</p><h3>运行诊断</h3><p id="provider-health-summary">等待读取健康状态</p></div>
                <button id="refresh-provider-health" type="button" class="secondary compact-button">刷新</button>
              </header>
              <div id="provider-health-list" class="service-status-list"></div>
              <form id="provider-test-form" class="field-grid">
                <label>Provider<select name="providerId"><option value="sentinel2">Sentinel-2</option><option value="cams">CAMS</option><option value="officialNotices">官方公告</option><option value="osm">OSM</option><option value="gbif">GBIF</option><option value="ebird">eBird</option><option value="firms">FIRMS</option><option value="copernicusMarine">Marine</option><option value="jplHorizons">JPL</option><option value="noaaSwpc">SWPC</option></select></label>
                <label>纬度<input name="latitude" type="number" min="-90" max="90" step="0.000001" value="30.25" required></label>
                <label>经度<input name="longitude" type="number" min="-180" max="180" step="0.000001" value="120.15" required></label>
                <label>半径 km<input name="radiusKm" type="number" min="1" max="50" value="25" required></label>
                <button type="submit">检测单个 Provider</button>
              </form>
            </section>'''
replace_once(
    "services/lumanest-data-broker/src/admin/public/index.html",
    "            </form>\n          </div>\n        </section>\n\n        <section class=\"page\" data-panel=\"llm\" hidden>",
    "            </form>" + provider_form + "\n          </div>\n        </section>\n\n        <section class=\"page\" data-panel=\"llm\" hidden>",
)

# ---------------------------------------------------------------------------
# Broker wiring and official-notice promotion into existing Context V5 safety.
# ---------------------------------------------------------------------------
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "function safetyDetailsFor(contextId, warnings, eventIds) {",
    "function safetyDetailsFor(contextId, warnings, eventIds) {",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "      source: '和风天气 · 官方预警',",
    "      source: typeof warning.source === 'string' ? warning.source : '和风天气 · 官方预警',",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "  });\n}\n\nfunction validNarrativeRequest(body) {",
    "  });\n}\n\n"
    "async function boundedProviderSafetyWarnings(service, body) {\n"
    "  let timer;\n"
    "  try {\n"
    "    return await Promise.race([\n"
    "      service.authoritativeSafetyNotices({\n"
    "        latitude: body.coordinate.latitude,\n"
    "        longitude: body.coordinate.longitude,\n"
    "        radiusKm: 25,\n"
    "        locale: body.locale,\n"
    "        observedAt: body.observedAt,\n"
    "      }).catch(() => []),\n"
    "      new Promise((resolve) => { timer = setTimeout(() => resolve([]), 1_500); }),\n"
    "    ]);\n"
    "  } finally {\n"
    "    if (timer != null) clearTimeout(timer);\n"
    "  }\n"
    "}\n\nfunction validNarrativeRequest(body) {",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "  const activeProviderFactsService = providerFactsService ?? new ProviderFactsService({\n    fetcher,\n    now,\n    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 12_000),\n  });",
    "  const activeProviderFactsService = providerFactsService ?? new ProviderFactsService({\n    fetcher,\n    now,\n    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 12_000),\n    configuration: runtimeConfig == null\n      ? null\n      : () => configurationSource.snapshot().providerSources,\n  });",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "      writeText(response, 200, `${skyOpportunityMetrics.toPrometheus()}${activeSevenTimerMetrics.toPrometheus()}`);",
    "      writeText(response, 200, `${skyOpportunityMetrics.toPrometheus()}${activeSevenTimerMetrics.toPrometheus()}${activeProviderFactsService.toPrometheus()}`);",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "      const [weather, sceneEvidence] = await Promise.all([",
    "      const [weather, sceneEvidence, providerWarnings] = await Promise.all([",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "        fetchAmapSceneEvidence({\n          coordinate: body.coordinate,\n          apiKey: configuration.amapWebKey,\n          fetcher,\n          timeoutMs: configuration.settings.upstreamTimeoutMs,\n        }),\n      ]);",
    "        fetchAmapSceneEvidence({\n          coordinate: body.coordinate,\n          apiKey: configuration.amapWebKey,\n          fetcher,\n          timeoutMs: configuration.settings.upstreamTimeoutMs,\n        }),\n"
    "        boundedProviderSafetyWarnings(activeProviderFactsService, body),\n"
    "      ]);",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "      const internalBody = {\n        contractVersion: body.contractVersion,",
    "      const allOfficialWarnings = [...weather.body.officialWarnings, ...providerWarnings]\n"
    "        .filter((warning) => Date.parse(warning.expiresAt) > now().getTime())\n"
    "        .sort((a, b) => Date.parse(a.expiresAt) - Date.parse(b.expiresAt))\n"
    "        .slice(0, 8);\n"
    "      const internalBody = {\n        contractVersion: body.contractVersion,",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "        officialWarnings: weather.body.officialWarnings.map((warning) => ({",
    "        officialWarnings: allOfficialWarnings.map((warning) => ({",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "        weather.body.officialWarnings,\n        result.body.facts.events.map((event) => event.id),",
    "        allOfficialWarnings,\n        result.body.facts.events.map((event) => event.id),",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "  const runtimeConfig = new RuntimeConfigService({ defaults, store: configStore });\n  await runtimeConfig.initialize();\n",
    "  const runtimeConfig = new RuntimeConfigService({ defaults, store: configStore });\n"
    "  await runtimeConfig.initialize();\n"
    "  const providerFactsService = new ProviderFactsService({\n"
    "    configuration: () => runtimeConfig.snapshot().providerSources,\n"
    "    timeoutMs: Math.min(runtimeConfig.snapshot().settings.upstreamTimeoutMs, 12_000),\n"
    "  });\n",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "    simulationRegistry,\n  });\n  const adminServer = createAdminServer({",
    "    simulationRegistry,\n    providerFactsService,\n  });\n  const adminServer = createAdminServer({",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "    getBrokerHealth: () => brokerHealthMonitor.snapshot(),\n    getAuditLogHealth:",
    "    getBrokerHealth: () => brokerHealthMonitor.snapshot(),\n"
    "    getProviderHealth: () => providerFactsService.healthSnapshot(),\n"
    "    testProvider: (query) => providerFactsService.testProvider(query),\n"
    "    getAuditLogHealth:",
)
replace_once(
    "services/lumanest-data-broker/src/server.mjs",
    "        sevenTimerCache.clear(),\n      ]);",
    "        sevenTimerCache.clear(),\n"
    "        Promise.resolve(providerFactsService.clearCache()),\n"
    "      ]);",
)

# ---------------------------------------------------------------------------
# Flutter presentation: contextual 2–4 signal selection.
# ---------------------------------------------------------------------------
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "Future<void> showV2ProviderFactsSheet(\n  BuildContext context,\n  ProviderFactsBundle bundle,\n) => showModalBottomSheet<void>(",
    "Future<void> showV2ProviderFactsSheet(\n  BuildContext context,\n  ProviderFactsBundle bundle, {\n  List<ProviderSignal>? prioritizedSignals,\n}) => showModalBottomSheet<void>(",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "  builder: (context) => _V2ProviderFactsSheet(bundle: bundle),",
    "  builder: (context) => _V2ProviderFactsSheet(\n    bundle: bundle,\n    prioritizedSignals: prioritizedSignals,\n  ),",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "    required this.onTap,\n  });\n\n  final ProviderFactsBundle bundle;\n  final VoidCallback onTap;",
    "    required this.onTap,\n    this.signals,\n  });\n\n  final ProviderFactsBundle bundle;\n  final List<ProviderSignal>? signals;\n  final VoidCallback onTap;",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "    final signals = bundle.displayableSignals.take(2).toList(growable: false);",
    "    final signals = (this.signals ?? bundle.displayableSignals)\n        .take(2)\n        .toList(growable: false);",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "class _V2ProviderFactsSheet extends StatelessWidget {\n  const _V2ProviderFactsSheet({required this.bundle});\n\n  final ProviderFactsBundle bundle;",
    "class _V2ProviderFactsSheet extends StatelessWidget {\n  const _V2ProviderFactsSheet({\n    required this.bundle,\n    required this.prioritizedSignals,\n  });\n\n  final ProviderFactsBundle bundle;\n  final List<ProviderSignal>? prioritizedSignals;",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart",
    "    final current = bundle.displayableSignals;",
    "    final current = prioritizedSignals ?? bundle.displayableSignals;",
)

replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "import 'package:luma_nest/src/core/environment/provider_facts_providers.dart';\n",
    "import 'package:luma_nest/src/core/environment/provider_facts_providers.dart';\n"
    "import 'package:luma_nest/src/core/environment/provider_signal_relevance.dart';\n",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "    final composition = const ExploreCompositionEngine().compose(\n      snapshot: snapshot,\n      brief: briefState.brief,\n    );",
    "    final composition = const ExploreCompositionEngine().compose(\n      snapshot: snapshot,\n      brief: briefState.brief,\n    );\n"
    "    final providerSignals = providerFacts == null || snapshot == null\n"
    "        ? const <ProviderSignal>[]\n"
    "        : selectProviderSignalsForContext(providerFacts, snapshot);",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "        providerFacts: providerFacts,\n        refreshing:",
    "        providerFacts: providerFacts,\n        providerSignals: providerSignals,\n        refreshing:",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "    required this.providerFacts,\n    required this.refreshing,",
    "    required this.providerFacts,\n    required this.providerSignals,\n    required this.refreshing,",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "  final ProviderFactsBundle? providerFacts;\n  final bool refreshing;",
    "  final ProviderFactsBundle? providerFacts;\n  final List<ProviderSignal> providerSignals;\n  final bool refreshing;",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "              if (providerFacts?.hasDisplayableSignals ?? false) ...[",
    "              if (providerSignals.isNotEmpty) ...[",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "                  bundle: providerFacts!,\n                  onTap: () =>\n                      showV2ProviderFactsSheet(context, providerFacts!),",
    "                  bundle: providerFacts!,\n                  signals: providerSignals,\n                  onTap: () => showV2ProviderFactsSheet(\n                    context,\n                    providerFacts!,\n                    prioritizedSignals: providerSignals,\n                  ),",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "    final providerFacts = ref.watch(providerFactsProvider).asData?.value;\n    final mapCenter",
    "    final providerFacts = ref.watch(providerFactsProvider).asData?.value;\n"
    "    final providerSignals = providerFacts == null\n"
    "        ? const <ProviderSignal>[]\n"
    "        : selectProviderSignalsForContext(providerFacts, snapshot);\n"
    "    final mapCenter",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "                    if (providerFacts?.hasDisplayableSignals ?? false) ...[",
    "                    if (providerSignals.isNotEmpty) ...[",
)
replace_once(
    "lib/src/presentation_v2/explore/v2_explore_page.dart",
    "                        onTap: () =>\n                            showV2ProviderFactsSheet(context, providerFacts!),",
    "                        onTap: () => showV2ProviderFactsSheet(\n"
    "                          context,\n"
    "                          providerFacts!,\n"
    "                          prioritizedSignals: providerSignals,\n"
    "                        ),",
)

# ---------------------------------------------------------------------------
# Tests: runtime secrets, feeds, metrics, safety promotion, admin masking.
# ---------------------------------------------------------------------------
write(
    "services/lumanest-data-broker/test/provider-runtime-config.test.mjs",
    r'''import assert from 'node:assert/strict';
import test from 'node:test';

import {
  providerConfigured,
  providerSourceDefaults,
  safeProviderSources,
  validateProviderSources,
} from '../src/environment/provider-runtime-config.mjs';

test('provider defaults are production-safe and secrets are masked', () => {
  const configuration = validateProviderSources({
    ...providerSourceDefaults(),
    ebirdToken: 'ebird-secret-1234',
    firmsMapKey: 'firms-secret-5678',
  });
  const safe = safeProviderSources(configuration);
  assert.equal(safe.ebirdToken.configured, true);
  assert.equal(safe.ebirdToken.lastFour, '1234');
  assert.equal(JSON.stringify(safe).includes('ebird-secret'), false);
  assert.equal(providerConfigured('ebird', configuration), true);
});

test('official notice sources require HTTPS, coverage and authority before safety promotion', () => {
  assert.throws(() => validateProviderSources({
    officialNoticeSources: [{
      id: 'unsafe', name: 'Unsafe', feedUrl: 'http://example.com/feed',
      homepageUrl: 'https://example.com', format: 'rss', authoritative: true,
      promoteToSafety: true, coverage: { latitude: 30, longitude: 120, radiusKm: 20 },
      allowedKinds: ['closure'],
    }],
  }, { partial: true }), /HTTPS/);
  assert.throws(() => validateProviderSources({
    officialNoticeSources: [{
      id: 'reference', name: 'Reference', feedUrl: 'https://example.com/feed',
      homepageUrl: 'https://example.com', format: 'rss', authoritative: false,
      promoteToSafety: true, coverage: { latitude: 30, longitude: 120, radiusKm: 20 },
      allowedKinds: ['closure'],
    }],
  }, { partial: true }), /non-authoritative/);
});

test('unknown provider configuration fields are rejected', () => {
  assert.throws(
    () => validateProviderSources({ cookiePool: ['forbidden'] }, { partial: true }),
    /Unknown provider source field/,
  );
});
''',
)
write(
    "services/lumanest-data-broker/test/official-notice-feed.test.mjs",
    r'''import assert from 'node:assert/strict';
import test from 'node:test';

import { loadOfficialNoticeItems } from '../src/environment/official-notice-feed.mjs';
import { validateProviderSources } from '../src/environment/provider-runtime-config.mjs';

const now = new Date('2026-08-03T08:00:00Z');
const source = validateProviderSources({
  officialNoticeSources: [{
    id: 'zhejiang-scenic',
    name: '浙江景区公告',
    feedUrl: 'https://notice.test/feed.json',
    homepageUrl: 'https://notice.test/',
    format: 'jsonFeed',
    enabled: true,
    authoritative: true,
    promoteToSafety: true,
    allowDefaultSafetyExpiry: false,
    defaultExpiryMinutes: 360,
    refreshMinutes: 30,
    coverage: { latitude: 30.25, longitude: 120.15, radiusKm: 100, regionCodes: ['330000'] },
    allowedKinds: ['closure', 'reopening'],
  }],
}, { partial: true }).officialNoticeSources[0];

test('reviewed current closure with explicit expiry becomes safety eligible', async () => {
  const result = await loadOfficialNoticeItems({
    sources: [source],
    query: { latitude: 30.25, longitude: 120.15, radiusKm: 25 },
    now,
    fetcher: async () => new Response(JSON.stringify({ items: [{
      title: '景区临时关闭公告',
      summary: '受天气影响，景区自2026年8月3日关闭至2026年8月4日18:00。',
      url: 'https://notice.test/items/1',
      date_published: '2026-08-03T06:00:00Z',
    }] }), { status: 200, headers: { 'Content-Type': 'application/feed+json' } }),
  });
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].kind, 'closure');
  assert.equal(result.items[0].safetyEligible, true);
  assert.equal(result.items[0].expiryExplicit, true);
});

test('closure without explicit validity remains reference-only', async () => {
  const result = await loadOfficialNoticeItems({
    sources: [source],
    query: { latitude: 30.25, longitude: 120.15, radiusKm: 25 },
    now,
    fetcher: async () => new Response(JSON.stringify({ items: [{
      title: '景区临时关闭',
      summary: '请关注后续通知。',
      url: 'https://notice.test/items/2',
      date_published: '2026-08-03T07:00:00Z',
    }] }), { status: 200 }),
  });
  assert.equal(result.items[0].safetyEligible, false);
});

test('out-of-coverage feeds are not requested', async () => {
  let requests = 0;
  const result = await loadOfficialNoticeItems({
    sources: [source],
    query: { latitude: 43.8, longitude: 87.6, radiusKm: 25 },
    now,
    fetcher: async () => { requests += 1; throw new Error('must not request'); },
  });
  assert.equal(requests, 0);
  assert.equal(result.checkedSources, 0);
});
''',
)

# Append focused ProviderFacts tests.
provider_test_path = "services/lumanest-data-broker/test/provider-facts-service.test.mjs"
provider_tests = read(provider_test_path)
provider_tests += r'''

test('dynamic provider configuration, health and Sentinel derivatives stay traceable', async () => {
  let configuration = {
    enabled: true,
    enabledProviders: [...supportedProviderIds],
    timeoutMs: 8000,
    sentinelStacBaseUrl: 'https://stac.dynamic/v1',
    sentinelRasterGatewayUrl: 'https://raster.dynamic/facts',
    sentinelRasterToken: 'raster-token',
    camsGatewayUrl: '', camsApiKey: '',
    aeronetBaseUrl: 'https://aeronet.dynamic',
    officialNoticeGatewayUrl: '', officialNoticeGatewayToken: '', officialNoticeSources: [],
    overpassUrl: 'https://overpass.dynamic', wikidataEndpoint: 'https://wikidata.dynamic',
    commonsApiUrl: 'https://commons.dynamic', gbifBaseUrl: 'https://gbif.dynamic',
    ebirdBaseUrl: 'https://ebird.dynamic', ebirdToken: '',
    firmsBaseUrl: 'https://firms.dynamic', firmsMapKey: '',
    marineGatewayUrl: '', marineApiKey: '',
    horizonsBaseUrl: 'https://horizons.dynamic', swpcBaseUrl: 'https://swpc.dynamic',
  };
  const service = new ProviderFactsService({
    now: () => instant,
    configuration: () => configuration,
    fetcher: async (input, init = {}) => {
      const url = new URL(input);
      if (url.hostname === 'stac.dynamic') return json({ features: [{
        properties: { datetime: '2026-08-02T02:00:00Z', 'eo:cloud_cover': 8 },
        links: [{ rel: 'self', href: 'https://stac.dynamic/item' }],
      }] });
      if (url.hostname === 'raster.dynamic') {
        assert.equal(init.headers.Authorization, 'Bearer raster-token');
        return json({ observations: [{
          metric: 'ndvi', delta: 0.123, cloudCoverage: 8,
          spatialResolutionMeters: 10, confidence: 'high',
          comparisonStart: '2026-07-15T00:00:00Z', comparisonEnd: '2026-08-02T00:00:00Z',
          observedAt: '2026-08-02T02:00:00Z', expiresAt: '2026-08-04T02:00:00Z',
          sourceUrl: 'https://raster.dynamic/observations/1',
        }] });
      }
      throw new Error('offline');
    },
  });
  const result = await service.facts(query('sentinel2'));
  const signals = result.providers[0].signals;
  assert.equal(signals[0].kind, 'vegetationIndexChange');
  assert.match(signals[0].summary, /不代表现场已进入最佳状态/);
  const health = service.healthSnapshot();
  assert.equal(health.providers.find((item) => item.id === 'sentinel2').lastStatus, 'ready');
  configuration = { ...configuration, enabledProviders: [] };
  const disabled = await service.testProvider({ providerId: 'sentinel2', latitude: 30.25, longitude: 120.15 });
  assert.equal(disabled.status, 'unconfigured');
});

test('only authoritative current operational notices are promoted to Context warnings', async () => {
  const service = new ProviderFactsService({
    now: () => instant,
    officialNoticeGatewayUrl: 'https://notices.safe/facts',
    fetcher: async (input) => {
      const url = new URL(input);
      if (url.hostname !== 'notices.safe') throw new Error('unexpected');
      return json({ signals: [
        { kind: 'closure', title: '景区临时关闭', summary: '官方公告确认当前关闭。', verification: 'authoritative', observedAt: instant.toISOString(), expiresAt: '2026-08-04T08:00:00Z', sourceUrl: 'https://notices.safe/closure' },
        { kind: 'eventChange', title: '演出改期', summary: '演出时间调整。', verification: 'authoritative', observedAt: instant.toISOString(), expiresAt: '2026-08-04T08:00:00Z', sourceUrl: 'https://notices.safe/event' },
      ] });
    },
  });
  const warnings = await service.authoritativeSafetyNotices(query('officialNotices'));
  assert.equal(warnings.length, 1);
  assert.match(warnings[0].id, /^[a-f0-9]{12}$/);
  assert.equal(warnings[0].title, '景区临时关闭');
});
'''
write(provider_test_path, provider_tests)

# Runtime config tests for persistence and secret retention.
runtime_test_path = "services/lumanest-data-broker/test/runtime-config.test.mjs"
runtime_tests = read(runtime_test_path)
runtime_tests += r'''

test('provider configuration is persisted and omitted secrets remain encrypted', async () => {
  const store = new MemoryStore({
    providerSources: {
      ebirdToken: 'initial-ebird-token',
      firmsMapKey: 'initial-firms-key',
      enabledProviders: ['ebird', 'firms'],
    },
  });
  const service = new RuntimeConfigService({ defaults: environmentDefaults(), store });
  await service.initialize();
  await service.replace({
    providerSources: {
      enabledProviders: ['ebird'],
      ebirdBaseUrl: 'https://api.ebird.org',
    },
  });
  assert.equal(service.snapshot().providerSources.ebirdToken, 'initial-ebird-token');
  assert.equal(service.snapshot().providerSources.firmsMapKey, 'initial-firms-key');
  assert.deepEqual(service.snapshot().providerSources.enabledProviders, ['ebird']);
  assert.equal(store.value.providerSources.ebirdToken, 'initial-ebird-token');
});
'''
write(runtime_test_path, runtime_tests)

# Admin server test fixture and provider endpoint coverage.
admin_test_path = "services/lumanest-data-broker/test/admin-server.test.mjs"
admin_tests = read(admin_test_path)
admin_tests = admin_tests.replace(
    "  getBrokerHealth = async () => ({ status: 'unknown' }),\n  getAuditLogHealth",
    "  getBrokerHealth = async () => ({ status: 'unknown' }),\n  providerHub = null,\n  getAuditLogHealth",
    1,
)
admin_tests = admin_tests.replace(
    "    getBrokerHealth,\n    getAuditLogHealth,",
    "    getBrokerHealth,\n"
    "    getProviderHealth: async () => providerHub?.health ?? ({ provider: 'providerHub', enabled: true, providers: [], cache: {} }),\n"
    "    testProvider: async (query) => providerHub?.test?.(query) ?? ({ ok: false, error: 'not_configured' }),\n"
    "    getAuditLogHealth,",
    1,
)
admin_tests += r'''

test('provider configuration is masked and diagnostics never audit coordinates', async () => {
  await withAdmin(async ({ baseUrl, auditLog }) => {
    const credentials = await login(baseUrl);
    const config = await fetch(`${baseUrl}/admin-api/config`, { headers: { Cookie: credentials.cookie } });
    const text = await config.text();
    assert.equal(text.includes('provider-secret-value'), false);
    const parsed = JSON.parse(text);
    assert.equal(Array.isArray(parsed.providers.catalog), true);

    const headers = { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' };
    const response = await fetch(`${baseUrl}/admin-api/providers/test`, {
      method: 'POST', headers,
      body: JSON.stringify({ providerId: 'osm', latitude: 30.25, longitude: 120.15, radiusKm: 25 }),
    });
    assert.equal(response.status, 200);
    const entry = (await auditLog.list()).find((item) => item.operation === 'test_provider');
    assert.deepEqual(entry.details, { providerId: 'osm', traceId: 'provider-trace' });
    assert.doesNotMatch(JSON.stringify(entry), /30\.25|120\.15/);
  }, {
    providerHub: {
      health: { provider: 'providerHub', enabled: true, providers: [], cache: {} },
      test: () => ({ ok: true, providerId: 'osm', status: 'ready', signalCount: 1, latencyMs: 5, traceId: 'provider-trace', error: null }),
    },
  });
});
'''
write(admin_test_path, admin_tests)

# ---------------------------------------------------------------------------
# Ten-location deterministic acceptance matrix and runbook.
# ---------------------------------------------------------------------------
locations = [
    {"id": "hangzhou-west-lake", "name": "杭州西湖", "latitude": 30.2431, "longitude": 120.1503, "scene": "lake", "categories": ["surface", "atmosphere", "operations", "culture"]},
    {"id": "haining-yanguan", "name": "海宁盐官", "latitude": 30.4477, "longitude": 120.5574, "scene": "village", "categories": ["operations", "culture", "marine", "atmosphere"]},
    {"id": "sayram-lake", "name": "新疆赛里木湖", "latitude": 44.6092, "longitude": 81.1687, "scene": "lake", "categories": ["surface", "atmosphere", "operations", "outdoor"]},
    {"id": "duku-highway", "name": "独库公路", "latitude": 43.325, "longitude": 84.105, "scene": "mountain", "categories": ["operations", "outdoor", "surface", "fire"]},
    {"id": "delingha", "name": "青海德令哈", "latitude": 37.3694, "longitude": 97.3608, "scene": "desert", "categories": ["atmosphere", "surface", "fire", "astronomy"]},
    {"id": "everest-base-camp", "name": "珠峰大本营", "latitude": 28.1416, "longitude": 86.8515, "scene": "mountain", "categories": ["operations", "surface", "atmosphere", "outdoor"]},
    {"id": "gongga", "name": "川西贡嘎", "latitude": 29.5957, "longitude": 101.878, "scene": "mountain", "categories": ["operations", "surface", "atmosphere", "fire"]},
    {"id": "meili-snow-mountain", "name": "云南梅里雪山", "latitude": 28.4373, "longitude": 98.6862, "scene": "mountain", "categories": ["operations", "surface", "atmosphere", "outdoor"]},
    {"id": "pingtan", "name": "福建平潭", "latitude": 25.5037, "longitude": 119.7902, "scene": "lake", "categories": ["marine", "operations", "atmosphere", "culture"]},
    {"id": "ulan-buh-grassland", "name": "内蒙古乌兰布统", "latitude": 42.5035, "longitude": 117.2994, "scene": "desert", "categories": ["surface", "fire", "wildlife", "operations"]},
]
write(
    "services/lumanest-data-broker/test/fixtures/provider-acceptance-locations.json",
    json.dumps(locations, ensure_ascii=False, indent=2) + "\n",
)
write(
    "services/lumanest-data-broker/test/provider-acceptance-matrix.test.mjs",
    r'''import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const locations = JSON.parse(await readFile(new URL('./fixtures/provider-acceptance-locations.json', import.meta.url)));
const allowedScenes = new Set(['city', 'lake', 'mountain', 'desert', 'village']);
const allowedCategories = new Set(['surface', 'atmosphere', 'operations', 'outdoor', 'culture', 'wildlife', 'fire', 'marine', 'astronomy', 'spaceWeather']);

test('provider acceptance matrix covers ten distinct real-world travel scenes', () => {
  assert.equal(locations.length, 10);
  assert.equal(new Set(locations.map((item) => item.id)).size, locations.length);
  assert.equal(new Set(locations.map((item) => item.name)).size, locations.length);
  for (const item of locations) {
    assert.equal(Number.isFinite(item.latitude) && item.latitude >= -90 && item.latitude <= 90, true);
    assert.equal(Number.isFinite(item.longitude) && item.longitude >= -180 && item.longitude <= 180, true);
    assert.equal(allowedScenes.has(item.scene), true);
    assert.equal(item.categories.length >= 4, true);
    assert.equal(item.categories.every((category) => allowedCategories.has(category)), true);
    assert.equal(item.categories.includes('operations'), true);
  }
});
''',
)
write(
    "docs/provider-operations-runbook.md",
    """# Provider Hub 生产运行手册\n\n"
    "## 控制台职责\n\n"
    "所有 Provider 端点、Token、Map Key 和审核公告源均从 NAS 管理台的“密钥与服务 → Provider Hub”录入。密钥由现有加密配置存储保存，读取接口只返回是否配置和末四位。Flutter 不包含任何第三方凭据。\n\n"
    "## 数据闭环\n\n"
    "1. Broker 按 Provider 独立超时、缓存、合并并记录健康指标。\n"
    "2. Sentinel Raster Gateway 仅接受 NDVI/NDSI/NDWI/地表变化的结构化观测元数据，前端不得将变化指数改写为最佳季节结论。\n"
    "3. CAMS 和 Marine Gateway 只接受白名单信号类型。海洋模型不替代官方潮汐表。\n"
    "4. 官方公告可来自标准网关或审核 Feed 注册表。只有 HTTPS、覆盖当前位置、仍在有效期、权威且显式允许晋升的关闭/封路/防火/管制公告进入 Context V5 安全链。\n"
    "5. App 依据当前场景和路线状态显示最多四条信号；没有当前信号时不占位。\n\n"
    "## Sentinel Raster Gateway 合同\n\n"
    "返回 `observations` 数组，每项包含：`metric` (`ndvi|ndsi|ndwi|surfaceChange`)、`delta`、`cloudCoverage`、`spatialResolutionMeters`、`confidence`、`comparisonStart`、`comparisonEnd`、`observedAt`、`expiresAt`、`sourceUrl`。\n\n"
    "## 标准化 CAMS / Marine / 官方公告 Gateway 合同\n\n"
    "返回 `signals` 数组，每项包含：`kind`、`title`、`summary`、`verification`、`observedAt`、`expiresAt`、`sourceUrl`。Broker 会拒绝来源不明、过期、非 HTTPS 或类型不在白名单内的数据。\n\n"
    "## 验收矩阵\n\n"
    "仓库固定覆盖杭州西湖、海宁盐官、赛里木湖、独库公路、德令哈、珠峰大本营、贡嘎、梅里雪山、平潭和乌兰布统。上线后在控制台逐个选择坐标执行单源检测，并确认：无错误地理匹配、无过期信号、弱网不阻塞探索、海外源经当前后端出口可访问。\n"
    """,
)

# Update Provider Hub documentation to point at the completed operations layer.
provider_doc = read("docs/provider-hub.md")
provider_doc += """

## Production operations closure

Provider endpoints and credentials are runtime-managed in the encrypted NAS
admin console. The shared ProviderFactsService reads a fresh immutable runtime
snapshot for every cache miss, so changing a provider endpoint or token does not
require rebuilding Flutter. The console exposes only masked secrets, health,
latency, signal count, cache statistics and sanitized trace IDs.

Sentinel-2 may be augmented by a configured Raster Gateway that returns bounded
NDVI/NDSI/NDWI or surface-change observations. CAMS, Marine and official notice
gateways are type allow-listed. Reviewed official RSS/Atom/JSON feeds may also
be registered with explicit geographic coverage and validity policy.

Only current authoritative closure, road-closure, fire-restriction and regulation
notices that pass the reviewed source and spatial gates are promoted into the
existing Context V5 official-warning lane. Other Provider Hub data remains
supplementary and cannot alter safety state.
"""
write("docs/provider-hub.md", provider_doc)

print("Provider operations closure applied")
