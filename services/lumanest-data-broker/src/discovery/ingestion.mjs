import { routeNarrative } from '../llm/router.mjs';

const searchKeys = new Set(['query', 'locale', 'freshnessDays', 'domains']);
const extractKeys = new Set(['missionType', 'focus', 'locale', 'region', 'evidence']);
const regionKeys = new Set(['latitude', 'longitude']);
const evidenceKeys = new Set(['title', 'snippet', 'url', 'publishedAt', 'sourceId', 'publisher', 'license', 'version']);
const allowedCategories = new Set(['candidate_viewpoint', 'attraction', 'event']);
const prohibitedTerms = /(?:safety|risk|danger|warning|species|wildlife|animal|permit|route|popularity|热度|安全|风险|预警|物种|动物|许可|路线)/iu;
const unsafeFocusTerms = /(?:safety|risk|danger|warning|species|wildlife|animal|安全|风险|预警|物种|野生动物)/iu;

function isPlainObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function text(value, minimum, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  const length = [...normalized].length;
  return length >= minimum && length <= maximum ? normalized : null;
}

function parsedHttpsUrl(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 1_000) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password) return null;
    // Keep meaningful query parameters: an official event or catalogue URL
    // frequently uses one as its stable record identifier. Only fragments are
    // presentation-only and would make provenance comparisons needlessly vary.
    url.hash = '';
    return url;
  } catch {
    return null;
  }
}

function httpsUrl(value) {
  return parsedHttpsUrl(value)?.toString() ?? null;
}

function normalizedDomain(value, policies) {
  if (typeof value !== 'string') return null;
  const result = value.trim().toLowerCase();
  return policies.some((policy) => policy.enabled && policy.domain === result) ? result : null;
}

export function validDiscoverySearchRequest(body, sourcePolicies = []) {
  if (!isPlainObject(body) || Object.keys(body).some((key) => !searchKeys.has(key))) return false;
  if (text(body.query, 2, 180) == null || !/^[\p{L}\p{N}\s\-_'.,，。？！、（）()]+$/u.test(body.query)) return false;
  if (typeof body.locale !== 'string' || !/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(body.locale)) return false;
  if (!Number.isInteger(body.freshnessDays) || body.freshnessDays < 1 || body.freshnessDays > 31) return false;
  if (!Array.isArray(body.domains) || body.domains.length > 8) return false;
  if (body.domains.length === 0) return sourcePolicies.some((policy) => policy.enabled);
  const domains = body.domains.map((domain) => normalizedDomain(domain, sourcePolicies));
  return domains.every((domain) => domain != null) && new Set(domains).size === domains.length;
}

export function normalizedDiscoverySearchRequest(body, sourcePolicies) {
  return Object.freeze({
    query: text(body.query, 2, 180),
    locale: body.locale,
    freshnessDays: body.freshnessDays,
    domains: Object.freeze(body.domains.length === 0
      ? sourcePolicies.filter((policy) => policy.enabled).map((policy) => policy.domain)
      : body.domains.map((domain) => normalizedDomain(domain, sourcePolicies))),
  });
}

function normalizedPublishedAt(value) {
  if (typeof value !== 'string' || value.length > 80) return null;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return null;
  return new Date(timestamp).toISOString();
}

function sourcePolicyForUrl(url, policies) {
  const hostname = url.hostname.toLowerCase();
  return policies.find((policy) => policy.enabled &&
    (hostname === policy.domain || hostname.endsWith(`.${policy.domain}`))) ?? null;
}

export function sanitizeTavilyResults(payload, sourcePolicies) {
  if (!isPlainObject(payload) || !Array.isArray(payload.results)) return [];
  const seen = new Set();
  const results = [];
  for (const item of payload.results) {
    if (!isPlainObject(item)) continue;
    const title = text(item.title, 1, 200);
    const snippet = text(item.content, 1, 1_200);
    const parsedUrl = parsedHttpsUrl(item.url);
    const url = parsedUrl?.toString() ?? null;
    const source = parsedUrl == null ? null : sourcePolicyForUrl(parsedUrl, sourcePolicies);
    if (title == null || snippet == null || url == null || source == null || seen.has(url)) continue;
    seen.add(url);
    const publishedAt = normalizedPublishedAt(item.published_date);
    results.push(Object.freeze({
      title,
      snippet,
      url,
      sourceId: source.id,
      publisher: source.attribution,
      license: source.license,
      version: source.version,
      ...(publishedAt == null ? {} : { publishedAt }),
    }));
    if (results.length === 8) break;
  }
  return results;
}

export async function searchTavily({ request, profile, fetcher = fetch, signal }) {
  if (!profile?.enabled || !profile.apiKey || !profile.sourcePolicies?.some((policy) => policy.enabled)) {
    return { ok: false, error: 'search_unconfigured' };
  }
  try {
    const response = await fetcher(new URL('/search', profile.baseUrl), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: signal == null
        ? AbortSignal.timeout(profile.timeoutMs)
        : AbortSignal.any([signal, AbortSignal.timeout(profile.timeoutMs)]),
      body: JSON.stringify({
        api_key: profile.apiKey,
        query: request.query,
        search_depth: 'basic',
        max_results: 8,
        topic: 'general',
        ...(request.domains.length === 0 ? {} : { include_domains: request.domains }),
        days: request.freshnessDays,
      }),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) return { ok: false, error: 'upstream_unavailable' };
    return { ok: true, results: sanitizeTavilyResults(payload, profile.sourcePolicies) };
  } catch {
    return { ok: false, error: 'upstream_unavailable' };
  }
}

function hasProhibitedTerms(value) {
  if (typeof value === 'string') return prohibitedTerms.test(value);
  if (Array.isArray(value)) return value.some(hasProhibitedTerms);
  if (isPlainObject(value)) return Object.entries(value).some(([key, item]) =>
    prohibitedTerms.test(key) || hasProhibitedTerms(item));
  return false;
}

function validEvidence(value) {
  if (!isPlainObject(value) || Object.keys(value).some((key) => !evidenceKeys.has(key))) return false;
  if (text(value.title, 1, 200) == null || text(value.snippet, 1, 1_200) == null || httpsUrl(value.url) == null ||
      text(value.sourceId, 1, 64) == null || text(value.publisher, 1, 80) == null ||
      text(value.license, 1, 120) == null || text(value.version, 1, 80) == null) return false;
  return value.publishedAt === undefined || normalizedPublishedAt(value.publishedAt) != null;
}

export function validDiscoveryExtractRequest(body) {
  if (!isPlainObject(body) || Object.keys(body).length !== extractKeys.size ||
      Object.keys(body).some((key) => !extractKeys.has(key))) return false;
  if (!['popularPlaces', 'hiddenPlaces', 'humanityEvents', 'localStories', 'seasonalSignals'].includes(body.missionType)) return false;
  if (text(body.focus, 2, 180) == null || typeof body.locale !== 'string' ||
      unsafeFocusTerms.test(body.focus) || !/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(body.locale)) return false;
  if (!isPlainObject(body.region) || Object.keys(body.region).some((key) => !regionKeys.has(key)) ||
      !Number.isFinite(body.region.latitude) || !Number.isFinite(body.region.longitude) ||
      body.region.latitude < -90 || body.region.latitude > 90 ||
      body.region.longitude < -180 || body.region.longitude > 180) return false;
  return Array.isArray(body.evidence) && body.evidence.length > 0 && body.evidence.length <= 8 &&
    body.evidence.every(validEvidence);
}

export function discoveryExtractionPrompt(body) {
  const missionRule = {
    popularPlaces: '只提取地点和来源，不得输出热度、排名或趋势。',
    hiddenPlaces: '只提取有明确来源的地点线索。',
    humanityEvents: '活动时间必须来自来源，不得自行推断。',
    localStories: '无可靠坐标时只保留文化线索，不得伪造坐标。',
    seasonalSignals: '来源不足时只表达季节线索，不得生成精确花期或迁徙事实。',
  }[body.missionType];
  return {
    system: `你是摄影探索资料的结构化编辑。${missionRule}只能从给定来源证据中提取候选观景点、景点或活动；不得补充事实、热度、许可、路线、安全、风险、野生动物、物种或个人信息。坐标仅可在来源明确给出且靠近指定区域时返回。若返回 coordinate，必须返回 coordinateEvidence：它必须是来源原文中可直接找到的“纬度,经度”或“经度,纬度”坐标文本，且数值必须与 coordinate 完全对应。只输出 JSON：{"candidates":[{"title":"不超过80字","kind":"candidate_viewpoint|attraction|event","summary":"不超过180字","sourceIndexes":[0],"coordinate":{"latitude":0,"longitude":0},"coordinateEvidence":"30.280,120.130","startsAt":"ISO 时间","endsAt":"ISO 时间"}]}。最多 6 项；sourceIndexes 必须引用证据数组索引，时间与坐标均可省略。`,
    user: JSON.stringify({ missionType: body.missionType, focus: body.focus, locale: body.locale, region: body.region, evidence: body.evidence }),
  };
}

function validCandidateCoordinate(value) {
  return isPlainObject(value) && Object.keys(value).every((key) => regionKeys.has(key)) &&
    Number.isFinite(value.latitude) && Number.isFinite(value.longitude) &&
    value.latitude >= -90 && value.latitude <= 90 && value.longitude >= -180 && value.longitude <= 180;
}

function validCandidateTime(value) {
  return typeof value === 'string' && value.length <= 80 && Number.isFinite(Date.parse(value));
}

function coordinateEvidenceSupports(coordinate, coordinateEvidence, sources) {
  if (typeof coordinateEvidence !== 'string' || coordinateEvidence.length > 120) return false;
  const match = /^\s*(-?\d{1,2}(?:\.\d{1,6})?)\s*,\s*(-?\d{1,3}(?:\.\d{1,6})?)\s*$/.exec(coordinateEvidence);
  if (match == null || !sources.some((source) =>
    `${source.title}\n${source.snippet}`.includes(coordinateEvidence))) return false;
  const first = Number(match[1]);
  const second = Number(match[2]);
  const tolerance = 0.00001;
  return (Math.abs(first - coordinate.latitude) <= tolerance && Math.abs(second - coordinate.longitude) <= tolerance) ||
    (Math.abs(second - coordinate.latitude) <= tolerance && Math.abs(first - coordinate.longitude) <= tolerance);
}

export function parseDiscoveryCandidates(value, evidence) {
  try {
    const parsed = JSON.parse(value);
    if (!isPlainObject(parsed) || Object.keys(parsed).length !== 1 || !Array.isArray(parsed.candidates) ||
        parsed.candidates.length > 6 || hasProhibitedTerms(parsed)) return null;
    const candidates = [];
    const seen = new Set();
    for (const item of parsed.candidates) {
      if (!isPlainObject(item) || Object.keys(item).some((key) => !['title', 'kind', 'summary', 'sourceIndexes', 'coordinate', 'coordinateEvidence', 'startsAt', 'endsAt'].includes(key))) return null;
      const title = text(item.title, 1, 80);
      const summary = text(item.summary, 1, 180);
      if (!Array.isArray(item.sourceIndexes) || item.sourceIndexes.length === 0 || item.sourceIndexes.length > evidence.length ||
          item.sourceIndexes.some((index) => !Number.isInteger(index) || index < 0 || index >= evidence.length) ||
          new Set(item.sourceIndexes).size !== item.sourceIndexes.length ||
          title == null || summary == null || !allowedCategories.has(item.kind) ||
          (item.coordinate !== undefined && (!validCandidateCoordinate(item.coordinate) ||
            !coordinateEvidenceSupports(item.coordinate, item.coordinateEvidence,
              item.sourceIndexes.map((index) => evidence[index])))) ||
          (item.coordinate === undefined && item.coordinateEvidence !== undefined) ||
          (item.startsAt !== undefined && !validCandidateTime(item.startsAt)) ||
          (item.endsAt !== undefined && !validCandidateTime(item.endsAt)) ||
          (item.startsAt !== undefined && item.endsAt !== undefined && Date.parse(item.startsAt) > Date.parse(item.endsAt)) ||
          seen.has(`${title}\n${item.kind}`)) return null;
      seen.add(`${title}\n${item.kind}`);
      candidates.push({
        title, kind: item.kind, summary, sourceIndexes: item.sourceIndexes,
        ...(item.coordinate === undefined ? {} : { coordinate: item.coordinate, coordinateEvidence: item.coordinateEvidence }),
        ...(item.startsAt === undefined ? {} : { startsAt: new Date(Date.parse(item.startsAt)).toISOString() }),
        ...(item.endsAt === undefined ? {} : { endsAt: new Date(Date.parse(item.endsAt)).toISOString() }),
      });
    }
    return { candidates };
  } catch {
    return null;
  }
}

export async function extractDiscoveryCandidates({
  body, profiles, routing, fetcher = fetch, signal, callBudget,
}) {
  const routed = await routeNarrative({
    profiles,
    routing,
    prompt: discoveryExtractionPrompt(body),
    fetcher,
    signal,
    callBudget,
  });
  if (!routed.ok) return { ok: false, error: routed.error === 'ai_unconfigured' ? 'ai_unconfigured' : 'upstream_unavailable' };
  const result = parseDiscoveryCandidates(routed.text, body.evidence);
  return result == null ? { ok: false, error: 'upstream_unavailable' } : { ok: true, ...result };
}
