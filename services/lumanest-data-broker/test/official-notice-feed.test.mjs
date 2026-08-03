import assert from 'node:assert/strict';
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
