import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildAssistantContextEnvelope,
  createAssistantContextBinding,
  mergeAssistantSources,
} from '../src/assistant/context-envelope.mjs';

const now = new Date('2026-08-03T12:00:00Z');

function snapshot(binding) {
  return {
    contextId: 'ctx_1234567890abcdef12345678',
    generatedAt: '2026-08-03T11:55:00Z',
    expiresAt: '2026-08-03T13:00:00Z',
    stale: false,
    environment: { scene: 'mountain', dayPhase: 'sunset', weather: 'cloudy' },
    route: { active: true, mode: 'driving', stage: 'active' },
    facts: {
      events: [],
      shootingSessions: [{
        id: 'session.sunset', title: '山地日落窗口',
        observedAt: '2026-08-03T11:55:00Z',
        startAt: '2026-08-03T12:20:00Z', endAt: '2026-08-03T12:50:00Z',
        expiresAt: '2026-08-03T13:00:00Z',
      }],
    },
    assistantContextBinding: binding,
  };
}

test('assistant binding retains only a coarse cell centre', () => {
  const binding = createAssistantContextBinding({
    coordinate: { latitude: 30.267891, longitude: 120.153476 },
    locale: 'zh-CN',
    route: { mode: 'driving', stage: 'active' },
    snapshot: { environment: { scene: 'city' } },
  });
  assert.ok(binding);
  assert.notEqual(binding.region.latitude, 30.267891);
  assert.notEqual(binding.region.longitude, 120.153476);
  assert.equal(binding.region.radiusMeters, 20_000);
  assert.equal(binding.sceneProfile.physicalScene, 'urban');
  assert.equal(binding.sceneProfile.mobility, 'driving');
});

test('assistant envelope combines Region Brief and current Provider evidence', async () => {
  const binding = createAssistantContextBinding({
    coordinate: { latitude: 30.267891, longitude: 120.153476 },
    locale: 'zh-CN',
    route: { mode: 'driving', stage: 'active' },
    snapshot: { environment: { scene: 'mountain' } },
  });
  const providerFactsService = {
    async facts(query) {
      assert.equal(query.latitude, binding.region.latitude);
      assert.ok(query.providerIds.includes('sentinel2'));
      return {
        observedAt: now.toISOString(),
        generatedAt: now.toISOString(),
        expiresAt: '2026-08-03T12:40:00Z',
        providers: [{
          id: 'sentinel2', status: 'ready',
          source: {
            title: 'Sentinel-2 catalogue', publisher: 'Copernicus',
            url: 'https://dataspace.copernicus.eu/',
          },
          signals: [{
            id: 'signal_satellite', kind: 'opticalAcquisition',
            verification: 'observed', title: '近期光学卫星观测',
            summary: '最近目录影像已更新，不能据此断言现场景观变化。',
            observedAt: '2026-08-03T11:30:00Z',
            expiresAt: '2026-08-03T12:40:00Z',
            sourceUrl: 'https://dataspace.copernicus.eu/browser/',
          }],
        }, {
          id: 'officialNotices', status: 'ready',
          source: {
            title: 'Official notice', publisher: 'Local authority',
            url: 'https://gov.example/notices',
          },
          signals: [{
            id: 'signal_notice', kind: 'closure', verification: 'authoritative',
            title: '区域管制公告', summary: '不要在助手中展开具体安全建议。',
            observedAt: '2026-08-03T11:30:00Z',
            expiresAt: '2026-08-03T12:40:00Z',
            sourceUrl: 'https://gov.example/notices/1',
          }],
        }],
      };
    },
  };
  let observedCoverage = null;
  const envelope = await buildAssistantContextEnvelope({
    snapshot: snapshot(binding),
    providerFactsService,
    now,
    observe: (coverage) => { observedCoverage = coverage; },
    loadRegionBrief: async (request) => {
      assert.equal(request.snapshotId, 'ctx_1234567890abcdef12345678');
      assert.equal(request.region.latitude, binding.region.latitude);
      return {
        ok: true,
        body: {
          status: 'ready', regionName: '测试山地',
          generatedAt: '2026-08-03T11:50:00Z',
          expiresAt: '2026-08-03T12:30:00Z',
          identity: { summary: '这里以山地地貌和聚落文化为主要特征。' },
          orientation: { summary: '先理解区域，再按当前光线选择观察方向。' },
          photoThemes: [{ id: 'theme.mountain', label: '山地地貌' }],
          sources: [{
            id: 'source.region', title: '区域资料', publisher: '地方文旅部门',
            url: 'https://gov.example/region',
          }],
          insights: [{
            id: 'insight.region', title: '区域文化', summary: '本地聚落具有可核验的人文材料。',
            verification: 'authoritative', observedAt: '2026-08-03T11:50:00Z',
            expiresAt: '2026-08-03T12:30:00Z', evidenceIds: ['source.region'],
          }],
        },
      };
    },
  });
  assert.match(envelope.contextFacts, /区域身份：测试山地/);
  assert.match(envelope.contextFacts, /山地日落窗口/);
  assert.match(envelope.contextFacts, /近期光学卫星观测/);
  assert.match(envelope.contextFacts, /独立官方公告/);
  assert.doesNotMatch(envelope.contextFacts, /不要在助手中展开具体安全建议/);
  assert.equal(envelope.expiresAt, '2026-08-03T12:30:00.000Z');
  assert.ok(envelope.factIds.includes('insight.region'));
  assert.ok(envelope.sources.some((item) => item.publisher === '地方文旅部门'));
  assert.equal(envelope.coverage.status, 'ready');
  assert.equal(envelope.coverage.components.regionBrief.status, 'ready');
  assert.equal(envelope.coverage.components.providers.status, 'ready');
  assert.equal(envelope.coverage.verifiedEvidence, true);
  assert.ok(envelope.coverage.limits.includes('safety_chain_separate'));
  assert.deepEqual(observedCoverage, envelope.coverage);
  assert.doesNotMatch(JSON.stringify(envelope.coverage), /测试山地|30\.267|120\.153/);
});

test('assistant sources are HTTPS-only, deduplicated and bounded', () => {
  const merged = mergeAssistantSources(
    [{ title: 'A', publisher: 'P', url: 'https://example.com/a' }],
    [
      { title: 'A copy', publisher: 'P', url: 'https://example.com/a' },
      { title: 'B', publisher: 'P2', url: 'https://example.com/b' },
      { title: 'C', publisher: 'P3', url: 'https://example.com/c' },
      { title: 'D', publisher: 'P4', url: 'https://example.com/d' },
      { title: 'E', publisher: 'P5', url: 'https://example.com/e' },
    ],
  );
  assert.equal(merged.length, 4);
  assert.equal(merged[0].url, 'https://example.com/a');
});
