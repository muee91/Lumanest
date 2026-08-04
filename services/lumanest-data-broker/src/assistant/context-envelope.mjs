import {
  coarseRouteCorridor,
  routeWeatherFacts,
  validRouteCorridorBinding,
} from './route-scout-context.mjs';

const regionBriefSections = Object.freeze([
  'identity', 'orientation', 'photoThemes', 'happeningNow', 'places',
  'localTaste', 'etiquette', 'practical',
]);

const sceneProviderIds = Object.freeze({
  urban: ['officialNotices', 'wikidata', 'wikimediaCommons', 'osm', 'cams', 'aeronet'],
  village: ['officialNotices', 'wikidata', 'wikimediaCommons', 'osm', 'sentinel2', 'gbif'],
  mountain: ['officialNotices', 'sentinel2', 'cams', 'aeronet', 'osm', 'firms', 'gbif', 'ebird'],
  plateau: ['officialNotices', 'sentinel2', 'cams', 'aeronet', 'osm', 'firms'],
  desert: ['officialNotices', 'sentinel2', 'cams', 'aeronet', 'osm', 'firms'],
  forest: ['officialNotices', 'sentinel2', 'firms', 'gbif', 'ebird', 'osm'],
  inlandWater: ['officialNotices', 'sentinel2', 'cams', 'aeronet', 'osm', 'gbif', 'ebird'],
  coast: ['officialNotices', 'copernicusMarine', 'cams', 'aeronet', 'osm', 'sentinel2'],
  wetland: ['officialNotices', 'sentinel2', 'gbif', 'ebird', 'osm', 'cams'],
  unknown: ['officialNotices', 'sentinel2', 'cams', 'aeronet', 'osm', 'wikidata'],
});

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function finite(value, minimum, maximum) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function boundedText(value, maximum = 280) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return normalized.length > 0 ? [...normalized].slice(0, maximum).join('') : null;
}

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function httpsUrl(value) {
  if (typeof value !== 'string' || value.length > 2_048) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url.toString() : null;
  } catch {
    return null;
  }
}

function sceneValue(snapshot, evidence) {
  const raw = boundedText(
    snapshot?.environment?.sceneContext?.primaryScene ?? snapshot?.environment?.scene,
    32,
  );
  if (raw != null) return raw;
  if (evidence?.urban === true) return 'city';
  if (evidence?.waterBody === true) return 'lake';
  if (evidence?.mountainous === true) return 'mountain';
  if (evidence?.aridLand === true) return 'desert';
  if (evidence?.settlement === true) return 'village';
  return 'unknown';
}

function physicalScene(raw) {
  return new Map([
    ['city', 'urban'], ['urban', 'urban'], ['lake', 'inlandWater'],
    ['inlandWater', 'inlandWater'], ['mountain', 'mountain'],
    ['desert', 'desert'], ['village', 'village'], ['forest', 'forest'],
    ['plateau', 'plateau'], ['coast', 'coast'], ['wetland', 'wetland'],
  ]).get(raw) ?? 'unknown';
}

function routeMode(route) {
  return route?.mode === 'driving' ? 'driving'
    : route?.mode === 'hiking' ? 'hiking'
      : 'stationary';
}

function routeStage(route) {
  return ['none', 'planned', 'active', 'paused'].includes(route?.stage)
    ? route.stage
    : 'none';
}

function rounded(value) {
  return Number(value.toFixed(6));
}

export function createAssistantContextBinding({ coordinate, locale = 'zh-CN', route = null, snapshot = null, evidence = null }) {
  if (!object(coordinate) || !finite(coordinate.latitude, -90, 90) ||
      !finite(coordinate.longitude, -180, 180) ||
      typeof locale !== 'string' || !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(locale)) {
    return null;
  }
  const latitudeCell = Math.floor(coordinate.latitude / 0.05);
  const longitudeCell = Math.floor(coordinate.longitude / 0.05);
  const mobility = routeMode(route);
  const stage = routeStage(route);
  const scene = physicalScene(sceneValue(snapshot, evidence));
  return Object.freeze({
    locale,
    region: Object.freeze({
      latitude: rounded((latitudeCell + 0.5) * 0.05),
      longitude: rounded((longitudeCell + 0.5) * 0.05),
      radiusMeters: mobility === 'driving' ? 20_000 : 5_000,
    }),
    routeCorridor: coarseRouteCorridor(route),
    sceneProfile: Object.freeze({
      physicalScene: scene,
      facets: Object.freeze([]),
      settlement: scene === 'urban' ? 'urbanDistrict' : scene === 'village' ? 'village' : 'unknown',
      remoteness: 'unknown',
      altitude: 'unknown',
      poiDensity: 'unknown',
      mobility,
      routeStage: stage,
    }),
  });
}

function validBinding(value) {
  return object(value) && object(value.region) && object(value.sceneProfile) &&
    finite(value.region.latitude, -90, 90) && finite(value.region.longitude, -180, 180) &&
    Number.isInteger(value.region.radiusMeters) && value.region.radiusMeters >= 100 &&
    value.region.radiusMeters <= 50_000 && typeof value.locale === 'string' &&
    validRouteCorridorBinding(value.routeCorridor);
}

function selectedProviderIds(binding, snapshot) {
  const ids = [...(sceneProviderIds[binding.sceneProfile.physicalScene] ?? sceneProviderIds.unknown)];
  const dayPhase = snapshot?.environment?.dayPhase;
  if (dayPhase === 'night' || dayPhase === 'blueHour') {
    ids.push('jplHorizons', 'noaaSwpc');
  }
  return [...new Set(ids)].slice(0, 10);
}

async function settleWithin(task, timeoutMs) {
  if (task == null || typeof task.then !== 'function') return null;
  let timer;
  try {
    return await Promise.race([
      task.catch(() => null),
      new Promise((resolve) => { timer = setTimeout(() => resolve(null), timeoutMs); }),
    ]);
  } finally {
    if (timer != null) clearTimeout(timer);
  }
}

function current(value, now) {
  return validDate(value?.observedAt) && validDate(value?.expiresAt) &&
    Date.parse(value.observedAt) <= now.getTime() + 5 * 60_000 &&
    Date.parse(value.expiresAt) > now.getTime();
}

function currentGenerated(value, now) {
  return validDate(value?.generatedAt) && validDate(value?.expiresAt) &&
    Date.parse(value.generatedAt) <= now.getTime() + 5 * 60_000 &&
    Date.parse(value.expiresAt) > now.getTime();
}

function snapshotFactLines(snapshot, now) {
  const lines = [];
  const scene = boundedText(snapshot?.environment?.sceneContext?.primaryScene ?? snapshot?.environment?.scene, 32);
  const dayPhase = boundedText(snapshot?.environment?.dayPhase, 24);
  const weather = boundedText(snapshot?.environment?.weather, 32);
  const routeModeValue = boundedText(snapshot?.route?.mode, 24);
  const routeStageValue = boundedText(snapshot?.route?.stage, 24);
  const environment = [
    scene == null ? null : `场景${scene}`,
    dayPhase == null ? null : `时段${dayPhase}`,
    weather == null ? null : `天气${weather}`,
    routeModeValue == null ? null : `路线方式${routeModeValue}`,
    routeStageValue == null ? null : `路线状态${routeStageValue}`,
  ].filter(Boolean);
  if (environment.length > 0) lines.push(`当前环境：${environment.join('、')}`);
  const sessions = Array.isArray(snapshot?.facts?.shootingSessions)
    ? snapshot.facts.shootingSessions.filter((item) => current(item, now)).slice(0, 2)
    : [];
  for (const session of sessions) {
    const title = boundedText(session?.title, 100);
    const startAt = validDate(session?.startAt) ? session.startAt : null;
    const endAt = validDate(session?.endAt) ? session.endAt : null;
    if (title == null) continue;
    lines.push(`拍摄窗口：${title}${startAt && endAt ? `，${startAt}至${endAt}` : ''}`);
  }
  return lines;
}

function briefFacts(result, now) {
  const body = result?.ok === true ? result.body : null;
  if (!object(body) || !currentGenerated(body, now) ||
      !['ready', 'partial', 'refreshing'].includes(body.status)) {
    return { lines: [], sources: [], factIds: [], expiresAt: null };
  }
  const lines = [];
  const sources = [];
  const factIds = [];
  const regionName = boundedText(body.regionName, 120);
  const identity = boundedText(body.identity?.summary, 160);
  const orientation = boundedText(body.orientation?.summary, 160);
  if (regionName != null && identity != null) lines.push(`区域身份：${regionName}，${identity}`);
  if (orientation != null) lines.push(`区域方向：${orientation}`);
  const themes = Array.isArray(body.photoThemes)
    ? body.photoThemes.map((item) => boundedText(item?.label, 32)).filter(Boolean).slice(0, 5)
    : [];
  if (themes.length > 0) lines.push(`区域摄影题材：${themes.join('、')}`);
  const sourceById = new Map(
    (Array.isArray(body.sources) ? body.sources : [])
      .filter((item) => object(item))
      .map((item) => [item.id, item]),
  );
  const insights = (Array.isArray(body.insights) ? body.insights : [])
    .filter((item) => current(item, now) &&
      ['authoritative', 'corroborated', 'singleSource'].includes(item.verification))
    .slice(0, 6);
  for (const insight of insights) {
    const title = boundedText(insight.title, 100);
    const summary = boundedText(insight.summary, 220);
    if (title == null || summary == null) continue;
    lines.push(`区域事实（${insight.verification}）：${title}，${summary}`);
    if (typeof insight.id === 'string') factIds.push(insight.id);
    for (const evidenceId of Array.isArray(insight.evidenceIds) ? insight.evidenceIds : []) {
      const source = sourceById.get(evidenceId);
      const url = httpsUrl(source?.url);
      const sourceTitle = boundedText(source?.title, 200);
      const publisher = boundedText(source?.publisher, 120);
      if (url && sourceTitle && publisher) sources.push({ title: sourceTitle, publisher, url });
    }
  }
  return { lines, sources, factIds, expiresAt: body.expiresAt };
}

function providerFacts(bundle, now) {
  if (!object(bundle) || !currentGenerated(bundle, now)) {
    return { lines: [], sources: [], factIds: [], expiresAt: null };
  }
  const lines = [];
  const sources = [];
  const factIds = [];
  let hasOfficialOperationalNotice = false;
  const providers = Array.isArray(bundle.providers) ? bundle.providers : [];
  for (const provider of providers) {
    if (provider?.status !== 'ready') continue;
    const sourceTitle = boundedText(provider?.source?.title, 200);
    const sourcePublisher = boundedText(provider?.source?.publisher, 120);
    const providerUrl = httpsUrl(provider?.source?.url);
    for (const item of (Array.isArray(provider.signals) ? provider.signals : []).slice(0, 8)) {
      if (!current(item, now) || item.verification === 'candidate') continue;
      const sourceUrl = httpsUrl(item.sourceUrl) ?? providerUrl;
      if (provider.id === 'officialNotices') {
        if (item.verification === 'authoritative') hasOfficialOperationalNotice = true;
      } else {
        const title = boundedText(item.title, 100);
        const summary = boundedText(item.summary, 220);
        if (title == null || summary == null) continue;
        lines.push(`补充数据（${item.verification}）：${title}，${summary}`);
      }
      if (typeof item.id === 'string') factIds.push(item.id);
      if (sourceUrl && sourceTitle && sourcePublisher) {
        sources.push({ title: sourceTitle, publisher: sourcePublisher, url: sourceUrl });
      }
    }
  }
  if (hasOfficialOperationalNotice) {
    lines.unshift('运营状态：当前存在独立官方公告；具体安全与管制内容只以安全卡和官方来源为准。');
  }
  return { lines: lines.slice(0, 8), sources, factIds, expiresAt: bundle.expiresAt };
}

function uniqueSources(values) {
  const seen = new Set();
  return values.filter((item) => {
    const key = `${item.publisher}|${item.url}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 4);
}

function earliestExpiry(values, fallback, now) {
  const times = values.filter(validDate).map((value) => Date.parse(value))
    .filter((value) => value > now.getTime());
  return new Date(times.length === 0 ? Date.parse(fallback) : Math.min(...times)).toISOString();
}

export async function buildAssistantContextEnvelope({
  snapshot,
  providerFactsService,
  loadRegionBrief,
  loadRouteWeather,
  now = new Date(),
  timeoutMs = 2_000,
}) {
  const empty = Object.freeze({
    contextFacts: '', sources: Object.freeze([]), factIds: Object.freeze([]),
    expiresAt: snapshot?.expiresAt ?? now.toISOString(),
  });
  const binding = snapshot?.assistantContextBinding;
  if (!validBinding(binding) || typeof snapshot?.contextId !== 'string' || !validDate(snapshot.expiresAt)) {
    return empty;
  }
  const providerIds = selectedProviderIds(binding, snapshot);
  const providerTask = providerFactsService == null
    ? null
    : Promise.resolve().then(() => providerFactsService.facts({
    latitude: binding.region.latitude,
    longitude: binding.region.longitude,
    radiusKm: Math.max(5, Math.min(50, Math.ceil(binding.region.radiusMeters / 1_000))),
    locale: binding.locale,
    observedAt: now.toISOString(),
    providerIds,
  }));
  const regionTask = typeof loadRegionBrief === 'function'
    ? Promise.resolve().then(() => loadRegionBrief({
        contractVersion: 2,
        snapshotId: snapshot.contextId,
        activationType: 'foreground_opportunistic',
        locale: binding.locale,
        region: binding.region,
        sceneProfile: binding.sceneProfile,
        requestedSections: regionBriefSections,
      }))
    : null;
  const routeTask = typeof loadRouteWeather === 'function' && binding.routeCorridor != null
    ? Promise.resolve().then(() => loadRouteWeather({
        routeId: binding.routeCorridor.routeId,
        samples: binding.routeCorridor.samples,
      }))
    : null;
  const [providerBundle, regionResult, routeResult] = await Promise.all([
    settleWithin(providerTask, timeoutMs),
    settleWithin(regionTask, timeoutMs),
    settleWithin(routeTask, timeoutMs),
  ]);
  const baseLines = snapshotFactLines(snapshot, now);
  const region = briefFacts(regionResult, now);
  const providers = providerFacts(providerBundle, now);
  const route = routeWeatherFacts(routeResult, now);
  const contextFacts = [...baseLines, ...route.lines, ...region.lines, ...providers.lines]
    .map((line) => boundedText(line, 420))
    .filter(Boolean)
    .join('；');
  const boundedFacts = [...contextFacts].slice(0, 3_600).join('');
  return Object.freeze({
    contextFacts: boundedFacts,
    sources: Object.freeze(uniqueSources([...region.sources, ...providers.sources])),
    factIds: Object.freeze([
      ...new Set([...route.factIds, ...region.factIds, ...providers.factIds]),
    ].slice(0, 12)),
    expiresAt: earliestExpiry(
      [snapshot.expiresAt, route.expiresAt, region.expiresAt, providers.expiresAt],
      snapshot.expiresAt,
      now,
    ),
  });
}

export function mergeAssistantSources(...groups) {
  return uniqueSources(groups.flatMap((group) => Array.isArray(group) ? group : []));
}
