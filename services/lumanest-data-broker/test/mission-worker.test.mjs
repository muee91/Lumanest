import assert from 'node:assert/strict';
import test from 'node:test';

import { validMissionCreateRequest, validMissionPatchRequest } from '../src/mission/contract.mjs';
import { validContextRequest } from '../src/context/proxy.mjs';
import { MissionWorker } from '../src/mission/worker.mjs';

const mission = {
  id: 'mis_0123456789abcdef0123456789abcdef',
  version: 1,
  destination: { name: '西湖', latitude: 30.24, longitude: 120.15, system: 'wgs84' },
  intent: 'photography', locale: 'zh-CN',
};

test('mission contracts require bounded destination and explicit watch state', () => {
  assert.equal(validMissionCreateRequest({
    destination: mission.destination,
    intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null,
    watchEnabled: true,
  }), true);
  assert.equal(validMissionCreateRequest({
    destination: { ...mission.destination, latitude: 120 },
    intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null,
    watchEnabled: true,
  }), false);
  assert.equal(validMissionPatchRequest({
    expectedVersion: 1, operation: 'start', watchEnabled: null, destination: null,
  }), true);
  assert.equal(validMissionPatchRequest({
    expectedVersion: 1, operation: 'setWatch', watchEnabled: false, destination: null,
  }), true);
});

test('mission worker evaluates a leased mission and deduplicates facts in the store', async () => {
  const calls = [];
  const store = {
    async claimDue() { return { ok: true, mission }; },
    async finishCheck(value) { calls.push(value); return { ok: true, insertedEvents: value.events.length }; },
  };
  const worker = new MissionWorker({
    store,
    brokerUrl: 'http://broker.test',
    workerToken: 'worker-token',
    id: 'worker-test',
    now: () => new Date('2026-11-03T00:00:00Z'),
    fetcher: async (url, options) => {
      assert.equal(url.pathname, '/internal/v1/mission/check');
      assert.equal(options.headers['X-Mission-Worker-Token'], 'worker-token');
      const body = JSON.parse(options.body);
      assert.equal(validContextRequest(body), true);
      assert.equal(body.coordinate.latitude, 30.24);
      return new Response(JSON.stringify({
        contextId: 'ctx_0123456789abcdef01234567',
        generatedAt: '2026-11-03T00:00:00Z',
        facts: { events: [{
          id: 'weather-warning-test', channel: 'safety', source: 'official',
          observedAt: '2026-11-03T00:00:00Z', expiresAt: '2026-11-03T01:00:00Z',
          severity: 'warning', allowedAction: 'openSafetyDetail', title: '大风',
        }] },
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  });
  const result = await worker.runOnce();
  assert.equal(result.ok, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].events[0].dedupeKey, 'weather-warning-test:2026-11-03T01:00:00Z');
  assert.equal(calls[0].check.contextId, 'ctx_0123456789abcdef01234567');
});

test('mission worker records a failed check when the internal evaluator is unavailable', async () => {
  const checks = [];
  const store = {
    async claimDue() { return { ok: true, mission }; },
    async finishCheck(value) { checks.push(value); return { ok: true, insertedEvents: 0 }; },
  };
  const worker = new MissionWorker({ store, brokerUrl: '', workerToken: '', id: 'worker-test' });
  await worker.runOnce();
  assert.equal(checks[0].check.ok, false);
  assert.equal(checks[0].check.error, 'not_configured');
});
