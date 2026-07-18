import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CompanionStore,
  validCompanionRefreshRequest,
  validIdempotencyKey,
  validInsightFeedbackRequest,
} from '../src/companion/orchestrator.mjs';

const request = {
  snapshotId: 'ctx_1234567890abcdef12345678',
  reason: 'manual_refresh',
  routeId: null,
  visiblePage: 'today',
  localTimeZone: 'Asia/Shanghai',
};

test('validates bounded refresh, feedback and idempotency contracts', () => {
  assert.equal(validCompanionRefreshRequest(request), true);
  assert.equal(validCompanionRefreshRequest({ ...request, reason: 'loop_forever' }), false);
  assert.equal(validInsightFeedbackRequest({ action: 'saved' }), true);
  assert.equal(validInsightFeedbackRequest({ action: 'unsafe' }), false);
  assert.equal(validIdempotencyKey('refresh:12345678'), true);
  assert.equal(validIdempotencyKey('short'), false);
});

test('refresh uses snapshot facts, excludes safety and keeps a 20-60 inventory', () => {
  const now = new Date('2026-07-18T10:00:00Z');
  const store = new CompanionStore({ now: () => now });
  store.rememberSnapshot({
    contextId: request.snapshotId,
    generatedAt: now.toISOString(),
    route: { active: false },
    events: [
      {
        id: 'session.city.blue_hour', channel: 'opportunity', source: 'solar',
        observedAt: now.toISOString(), expiresAt: '2026-07-18T11:00:00Z',
        geoScope: 'point', confidence: 0.9, allowedAction: 'openShootingWindow',
      },
      {
        id: 'thunderstorm', channel: 'safety', source: 'weather',
        observedAt: now.toISOString(), expiresAt: '2026-07-18T11:00:00Z',
        geoScope: 'region', confidence: 1, allowedAction: 'openSafetyDetail',
      },
    ],
  });

  const first = store.refresh(request, 'refresh:12345678');
  const repeated = store.refresh(request, 'refresh:12345678');
  const inventory = store.listInventory();

  assert.strictEqual(repeated, first);
  assert.equal(first.ok, true);
  assert.equal(first.body.primaryInsight.channel, 'photographyOpportunity');
  assert.equal(inventory.items.length >= 20, true);
  assert.equal(inventory.items.length <= 60, true);
  assert.equal(inventory.items.some((item) => item.channel === 'safety'), false);
});

test('feedback is idempotent and only records known inventory insights', () => {
  const now = new Date('2026-07-18T10:00:00Z');
  const store = new CompanionStore({ now: () => now });
  store.rememberSnapshot({ contextId: request.snapshotId, generatedAt: now.toISOString(), events: [] });
  store.refresh(request, 'refresh:abcdefgh');
  const insightId = store.listInventory({ limit: 1 }).items[0].id;

  const first = store.feedback(insightId, 'saved', 'feedback:12345678');
  const repeated = store.feedback(insightId, 'saved', 'feedback:12345678');

  assert.strictEqual(repeated, first);
  assert.equal(first.body.accepted, true);
  assert.equal(store.feedback('insight_missing', 'saved', 'feedback:abcdefgh').error, 'insight_not_found');
});
