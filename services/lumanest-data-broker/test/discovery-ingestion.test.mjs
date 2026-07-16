import assert from 'node:assert/strict';
import test from 'node:test';

import { validateDiscoverySearchProfile } from '../src/discovery/search-profile.mjs';
import {
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
  assert.deepEqual(profile.sourcePolicies, [policy]);
  assert.throws(() => validateDiscoverySearchProfile({ ...profile, sourcePolicies: [{ ...policy, extra: true }] }), /Unknown/);
});

test('search accepts Chinese requests only for enabled reviewed domains', () => {
  const body = { query: '海宁 近期 摄影 展览', locale: 'zh-CN', freshnessDays: 14, domains: [policy.domain] };
  assert.equal(validDiscoverySearchRequest(body, [policy]), true);
  assert.equal(validDiscoverySearchRequest({ ...body, domains: [] }, [policy]), true);
  assert.equal(validDiscoverySearchRequest({ ...body, domains: ['www.mafengwo.cn'] }, [policy]), false);
  assert.equal(validDiscoverySearchRequest({ ...body, coordinate: { latitude: 30, longitude: 120 } }, [policy]), false);
});

test('Tavily results are filtered to reviewed HTTPS sources and retain attribution metadata', () => {
  const results = sanitizeTavilyResults({ results: [
    { title: '活动公告', content: '本周末在盐官举办摄影展。', url: 'https://culture.example.gov.cn/event?id=1', published_date: '2026-07-14' },
    { title: '未审核站点', content: '不应发布。', url: 'https://random.example/article' },
    { title: 'HTTP', content: '不应发布。', url: 'http://culture.example.gov.cn/old' },
  ] }, [policy]);
  assert.deepEqual(results, [{
    title: '活动公告', snippet: '本周末在盐官举办摄影展。', url: 'https://culture.example.gov.cn/event',
    sourceId: 'haining-culture', publisher: '海宁文化和旅游发布', license: 'CC BY 4.0', version: '2026-07',
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
  }] });
  assert.equal(parseDiscoveryCandidates(JSON.stringify({ candidates: [{
    title: '危险区域', kind: 'event', summary: '风险提示', sourceIndexes: [0],
  }] }), body.evidence), null);
});
