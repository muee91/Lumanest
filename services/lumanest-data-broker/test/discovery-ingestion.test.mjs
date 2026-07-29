import assert from 'node:assert/strict';
import test from 'node:test';

import { validateDiscoverySearchProfile } from '../src/discovery/search-profile.mjs';
import {
  discoveryExtractionPrompt,
  parseDiscoveryCandidates,
  searchTavily,
  sanitizeTavilyResults,
  validDiscoveryExtractRequest,
  validDiscoverySearchRequest,
} from '../src/discovery/ingestion.mjs';

const policy = {
  id: 'haining-culture', domain: 'culture.example.gov.cn',
  attribution: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07', enabled: true,
};

test('reviewed Tavily profile requires an enabled attributable source and keeps its key private', () => {
  assert.throws(() => validateDiscoverySearchProfile({
    baseUrl: 'https://api.tavily.com', apiKey: 'secret-search-key', enabled: true,
    timeoutMs: 8_000, sourcePolicies: [],
  }), /enabled reviewed source/);
  const profile = validateDiscoverySearchProfile({
    baseUrl: 'https://api.tavily.com/', apiKey: 'secret-search-key', enabled: true,
    timeoutMs: 8_000, sourcePolicies: [policy],
  });
  assert.equal(profile.baseUrl, 'https://api.tavily.com');
  assert.deepEqual(profile.sourcePolicies, [{
    ...policy,
    qualityTier: 'B',
    crawlEnabled: false,
    crawlMode: 'static',
    allowedPathPrefixes: [],
    deniedPathPatterns: [],
  }]);
  assert.throws(() => validateDiscoverySearchProfile({ ...profile, sourcePolicies: [{ ...policy, extra: true }] }), /Unknown/);
  assert.throws(() => validateDiscoverySearchProfile({
    ...profile,
    sourcePolicies: [{ ...policy, attribution: 'a'.repeat(81) }],
  }), /attribution/);
  assert.throws(() => validateDiscoverySearchProfile({
    ...profile,
    sourcePolicies: [{ ...policy, crawlEnabled: true }],
  }), /allowedPathPrefix/);
});

test('search accepts Chinese requests only for enabled reviewed domains', () => {
  const body = { query: '海宁 近期 摄影 展览', locale: 'zh-CN', freshnessDays: 14, domains: [policy.domain] };
  assert.equal(validDiscoverySearchRequest(body, [policy]), true);
  assert.equal(validDiscoverySearchRequest({ ...body, domains: [] }, [policy]), true);
  assert.equal(validDiscoverySearchRequest({ ...body, domains: ['www.mafengwo.cn'] }, [policy]), false);
  assert.equal(validDiscoverySearchRequest({ ...body, coordinate: { latitude: 30, longitude: 120 } }, [policy]), false);
  assert.equal(validDiscoverySearchRequest({ ...body, freshnessDays: null }, [policy]), true);
  assert.equal(validDiscoverySearchRequest({ ...body, freshnessDays: 0 }, [policy]), false);
});

test('evergreen searches omit upstream recency filtering rather than hiding archival official records', async () => {
  let requestBody;
  const result = await searchTavily({
    request: { query: '海宁 历史', locale: 'zh-CN', freshnessDays: null, domains: [policy.domain] },
    profile: {
      baseUrl: 'https://api.tavily.com', apiKey: 'tavily-test-key', enabled: true,
      timeoutMs: 8_000, sourcePolicies: [policy],
    },
    fetcher: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(JSON.stringify({ results: [] }), { status: 200 });
    },
  });
  assert.deepEqual(result, { ok: true, results: [] });
  assert.equal(Object.hasOwn(requestBody, 'days'), false);
});

test('Tavily results are filtered to reviewed HTTPS sources and retain attribution metadata', () => {
  const results = sanitizeTavilyResults({ results: [
    { title: '活动公告', content: '本周末在盐官举办摄影展。', url: 'https://culture.example.gov.cn/event?id=1', published_date: '2026-07-14' },
    { title: '未审核站点', content: '不应发布。', url: 'https://random.example/article' },
    { title: 'HTTP', content: '不应发布。', url: 'http://culture.example.gov.cn/old' },
  ] }, [policy]);
  assert.deepEqual(results, [{
    title: '活动公告', snippet: '本周末在盐官举办摄影展。', url: 'https://culture.example.gov.cn/event?id=1',
    sourceId: 'haining-culture', publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
    crawlEnabled: false, crawlMode: 'static',
    allowedPathPrefixes: [], deniedPathPatterns: [],
    publishedAt: '2026-07-14T00:00:00.000Z',
  }]);
});

test('search provider failures reduce to a stable error without response details or keys', async () => {
  const result = await searchTavily({
    request: { query: '海宁 摄影', locale: 'zh-CN', freshnessDays: 7, domains: [policy.domain] },
    profile: {
      baseUrl: 'https://api.tavily.com', apiKey: 'tavily-secret-1234', enabled: true,
      timeoutMs: 8_000, sourcePolicies: [policy],
    },
    fetcher: async () => new Response('provider says tavily-secret-1234 is rejected', { status: 401 }),
  });
  assert.deepEqual(result, { ok: false, error: 'upstream_unavailable' });
  assert.equal(JSON.stringify(result).includes('1234'), false);
});

test('extract contract requires attributable evidence and rejects safety or wildlife schema abuse', () => {
  const body = {
    missionType: 'humanityEvents',
    focus: '海宁近期摄影活动', locale: 'zh-CN', region: { latitude: 30.52, longitude: 120.68 },
    evidence: [{
      title: '活动公告', snippet: '本周末在盐官举办摄影展。', url: 'https://culture.example.gov.cn/event',
      sourceId: 'haining-culture', publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
    }],
  };
  assert.equal(validDiscoveryExtractRequest(body), true);
  assert.equal(validDiscoveryExtractRequest({ ...body, safety: 'high' }), false);
  assert.equal(validDiscoveryExtractRequest({ ...body, focus: '野生动物观察' }), false);
  assert.deepEqual(parseDiscoveryCandidates(JSON.stringify({ candidates: [{
    title: '盐官摄影展', kind: 'event', summary: '本周末举办，详情见发布机构公告。', sourceIndexes: [0],
  }] }), body.evidence), { candidates: [{
    title: '盐官摄影展', kind: 'event', summary: '本周末举办，详情见发布机构公告。', sourceIndexes: [0],
  }], insights: [] });
  assert.equal(parseDiscoveryCandidates(JSON.stringify({ candidates: [{
    title: '危险区域', kind: 'event', summary: '风险提示', sourceIndexes: [0],
  }] }), body.evidence), null);
});

test('local story extraction can produce the identity and orientation required by Region Brief', () => {
  const evidence = [{
    title: '盐官古城介绍',
    snippet: '盐官古城是以观潮文化和传统街巷为主要特征的历史街区。核心街区位于宣德门以北，主要入口在南侧。',
    url: 'https://culture.example.gov.cn/yanguan', sourceId: 'haining-culture',
    publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
  }];
  const body = {
    missionType: 'localStories', focus: '盐官古城区域资料', locale: 'zh-CN',
    region: { latitude: 30.45, longitude: 120.67 }, evidence,
  };
  const prompt = discoveryExtractionPrompt(body);
  assert.match(prompt.system, /areaIdentity\|orientation/);
  assert.match(prompt.system, /不得依据坐标自行计算或推断/);

  const parsed = parseDiscoveryCandidates(JSON.stringify({
    candidates: [],
    insights: [{
      type: 'areaIdentity', title: '盐官古城',
      summary: '盐官古城是以观潮文化和传统街巷为主要特征的历史街区。',
      factText: '盐官古城是以观潮文化和传统街巷为主要特征的历史街区。',
      sourceIndexes: [0], timeSensitive: false, actionability: 'detail',
      sceneTags: ['oldTown', 'architecture'], photoThemeTags: ['传统街巷'],
    }, {
      type: 'orientation', title: '核心街区方向',
      summary: '核心街区位于宣德门以北，主要入口在南侧。',
      factText: '核心街区位于宣德门以北，主要入口在南侧。',
      sourceIndexes: [0], timeSensitive: false, actionability: 'detail',
      sceneTags: ['oldTown'], photoThemeTags: [],
    }],
  }), evidence);
  assert.deepEqual(parsed?.insights.map((item) => item.type), ['areaIdentity', 'orientation']);
});

test('model coordinates require an exact coordinate string in their linked evidence', () => {
  const evidence = [{
    title: '地点公告', snippet: '官方坐标：30.280,120.130。', url: 'https://culture.example.gov.cn/place',
    sourceId: 'haining-culture', publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
  }];
  const valid = JSON.stringify({ candidates: [{
    title: '候选观景点', kind: 'candidate_viewpoint', summary: '来源公布的地点。', sourceIndexes: [0],
    coordinate: { latitude: 30.28, longitude: 120.13 }, coordinateEvidence: '30.280,120.130',
  }] });
  assert.deepEqual(parseDiscoveryCandidates(valid, evidence)?.candidates[0]?.coordinateEvidence, '30.280,120.130');
  const invented = valid.replace('30.280,120.130', '30.281,120.131');
  assert.equal(parseDiscoveryCandidates(invented, evidence), null);
});

test('regional insights retain an exact source fact and cannot request navigation', () => {
  const evidence = [{
    title: '古镇简介', snippet: '古镇因水运商贸兴起，沿河仍保留传统街巷。',
    url: 'https://culture.example.gov.cn/town', sourceId: 'haining-culture',
    publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
  }];
  const parsed = parseDiscoveryCandidates(JSON.stringify({
    candidates: [],
    insights: [{
      type: 'areaIdentity', title: '沿河古镇', summary: '古镇因水运商贸兴起，',
      factText: '古镇因水运商贸兴起，沿河仍保留传统街巷。', sourceIndexes: [0],
      timeSensitive: false, actionability: 'detail', sceneTags: ['oldTown'], photoThemeTags: ['传统建筑'],
    }],
  }), evidence);
  assert.equal(parsed?.insights.length, 1);
  assert.equal(parseDiscoveryCandidates(JSON.stringify({
    candidates: [], insights: [{
      type: 'areaIdentity', title: '沿河古镇', summary: '古镇因水运商贸兴起，',
      factText: '古镇因水运商贸兴起，沿河仍保留传统街巷。', sourceIndexes: [0],
      timeSensitive: false, actionability: 'navigate', sceneTags: [], photoThemeTags: [],
    }],
  }), evidence), null);
});
