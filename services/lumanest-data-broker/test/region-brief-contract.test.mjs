import assert from 'node:assert/strict';
import test from 'node:test';
import {
  validRegionBriefRequest,
  validRegionBriefResponse,
} from '../src/discovery/region-brief-contract.mjs';
import { forwardRegionBrief } from '../src/discovery/region-brief-proxy.mjs';

const profile = {
  physicalScene: 'urban',
  facets: ['oldTown', 'architecture'],
  settlement: 'historicDistrict',
  remoteness: 'connected',
  altitude: 'low',
  poiDensity: 'dense',
  mobility: 'walking',
  routeStage: 'none',
};

const request = {
  contractVersion: 2,
  snapshotId: 'ctx_0123456789abcdef01234567',
  activationType: 'foreground_opportunistic',
  locale: 'zh-CN',
  region: { latitude: 30.2, longitude: 120.1, radiusMeters: 8_000 },
  sceneProfile: profile,
  requestedSections: ['identity', 'photoThemes', 'places'],
};

const source = {
  id: 'source_1',
  sourcePolicyId: 'official-culture',
  publisher: '地方文旅局',
  title: '古镇介绍',
  url: 'https://culture.example.gov.cn/town',
  observedAt: '2026-07-21T10:00:00Z',
  qualityTier: 'A',
  license: 'CC BY 4.0',
  version: '2026-07',
};

const response = {
  contractVersion: 2,
  briefId: 'brief_1',
  regionId: 'region_1',
  regionName: '示例古镇',
  profile,
  generatedAt: '2026-07-21T10:00:00Z',
  expiresAt: '2026-07-21T16:00:00Z',
  status: 'ready',
  completeness: 'actionable',
  identity: { summary: '这里保留了传统街巷。', factIds: ['fact_identity_1'] },
  orientation: { summary: '核心街区位于北侧。', factIds: ['fact_orientation_1'] },
  photoThemes: [{ id: 'theme_architecture', label: '传统建筑' }],
  sources: [source],
  insights: [{
    id: 'insight_1',
    regionId: 'region_1',
    type: 'architecture',
    title: '沿河街巷',
    summary: '沿河保留传统建筑。',
    verification: 'singleSource',
    factIds: ['fact_identity_1'],
    evidenceIds: ['source_1'],
    observedAt: '2026-07-21T10:00:00Z',
    expiresAt: '2026-08-01T10:00:00Z',
    placeId: null,
    coordinate: null,
    startsAt: null,
    endsAt: null,
    timeSensitive: false,
    actionability: 'detail',
    sceneTags: ['oldTown', 'architecture'],
    photoThemeTags: ['传统建筑'],
  }, {
    id: 'insight_2',
    regionId: 'region_1',
    type: 'orientation',
    title: '核心街区方向',
    summary: '核心街区位于北侧。',
    verification: 'singleSource',
    factIds: ['fact_orientation_1'],
    evidenceIds: ['source_1'],
    observedAt: '2026-07-21T10:00:00Z',
    expiresAt: '2026-08-01T10:00:00Z',
    placeId: null,
    coordinate: null,
    startsAt: null,
    endsAt: null,
    timeSensitive: false,
    actionability: 'detail',
    sceneTags: ['oldTown'],
    photoThemeTags: [],
  }],
  refresh: { refreshingMissions: [], retryAfterSeconds: null },
};

test('Region Brief request is bounded, snapshot-scoped and privacy-safe', () => {
  assert.equal(validRegionBriefRequest(request), true);
  assert.equal(validRegionBriefRequest({ ...request, userId: 'not-allowed' }), false);
  assert.equal(validRegionBriefRequest({ ...request, requestedSections: ['identity', 'identity'] }), false);
});

test('Region Brief response keeps fact, source and insight references closed', () => {
  assert.equal(validRegionBriefResponse(response), true);
  assert.equal(validRegionBriefResponse({
    ...response,
    insights: [{ ...response.insights[0], evidenceIds: ['unknown-source'] }],
  }), false);
  assert.equal(validRegionBriefResponse({
    ...response,
    identity: { summary: '没有事实绑定', factIds: [] },
  }), false);
});

test('pending brief never fabricates a fallback identity', () => {
  const pending = {
    ...response,
    status: 'pending',
    identity: null,
    orientation: null,
    photoThemes: [],
    insights: [],
    sources: [],
    refresh: { refreshingMissions: ['localStories'], retryAfterSeconds: 30 },
  };
  assert.equal(validRegionBriefResponse(pending), true);
  assert.equal(validRegionBriefResponse({
    ...pending,
    identity: response.identity,
  }), false);
});

test('Region Brief proxy forwards only reviewed source policy metadata', async () => {
  let captured;
  const result = await forwardRegionBrief({
    body: request,
    serviceUrl: 'http://discovery-api:8001',
    internalToken: 'internal-discovery-token',
    sourcePolicies: [
      { id: 'official-culture', version: '2026-07', qualityTier: 'A', enabled: true, apiKey: 'never-forward' },
      { id: 'revoked', version: '2026-06', qualityTier: 'C', enabled: false },
    ],
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify(response), { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  });
  assert.deepEqual(result, { ok: true, status: 200, body: response });
  assert.equal(captured.url.toString(), 'http://discovery-api:8001/internal/v1/explore/brief');
  assert.deepEqual(JSON.parse(captured.options.body), {
    ...request,
    sourcePolicies: [{ id: 'official-culture', version: '2026-07', qualityTier: 'A' }],
  });
  assert.equal(captured.options.body.includes('never-forward'), false);
});
