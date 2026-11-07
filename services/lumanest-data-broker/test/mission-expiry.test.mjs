import assert from 'node:assert/strict';
import test from 'node:test';

import { MissionStore, defaultWatchDurationMilliseconds } from '../src/mission/store.mjs';

const ownerId = 'abcdefghijklmnopqrstuvwx';
const bindingHash = 'a'.repeat(64);
const missionId = 'mis_0123456789abcdef0123456789abcdef';

function row({ endsAt = null, watchEnabled = false, nextCheckAt = null, version = 1 } = {}) {
  const now = new Date('2026-11-07T00:00:00Z');
  return {
    id: missionId,
    owner_id: ownerId,
    state: 'planning',
    destination: { name: '西湖', latitude: 30.2, longitude: 120.1, system: 'wgs84' },
    intent: 'photography',
    locale: 'zh-CN',
    watch_enabled: watchEnabled,
    starts_at: null,
    ends_at: endsAt,
    version,
    next_check_at: nextCheckAt,
    last_checked_at: null,
    created_at: now,
    updated_at: now,
    watch_intent_revision: '0',
    watch_authorization_epoch: '0',
    lease_epoch: '0',
    lease_owner: null,
    lease_until: null,
  };
}

test('authorizing a watch with no endsAt assigns a bounded server expiry', async () => {
  const current = row();
  const pool = {
    async connect() {
      return {
        async query(sql, params = []) {
          if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql) || sql.includes('pg_advisory_xact_lock')) return { rows: [] };
          if (sql.includes('SELECT owner_secret_hash')) return { rows: [{ owner_secret_hash: bindingHash, revoked_at: null }] };
          if (sql.includes('UPDATE mission.device_bindings')) return { rows: [{ principal_id: ownerId }] };
          if (sql.includes('SELECT status, response, request_fingerprint')) return { rows: [] };
          if (sql.includes('SELECT * FROM mission.missions')) return { rows: [current] };
          if (sql.includes('UPDATE mission.missions')) {
            current.watch_enabled = params[2];
            current.next_check_at = params[3];
            current.version += 1;
            current.ends_at = params[12];
            return { rows: [current] };
          }
          if (sql.includes('INSERT INTO mission.watch_authorization_audit')) return { rows: [] };
          if (sql.includes('INSERT INTO mission.mission_operations')) return { rows: [] };
          throw new Error(`unexpected query: ${sql}`);
        },
        release() {},
      };
    },
  };
  const store = new MissionStore({ pool });
  const result = await store.patch({
    ownerId,
    bindingHash,
    id: missionId,
    operation: 'authorize-operation-123456',
    request: {
      expectedVersion: 1,
      operation: 'authorizeWatch',
      watchEnabled: true,
      destination: null,
      intentRevision: 1,
    },
  });
  assert.equal(result.ok, true);
  assert.equal(result.body.watchEnabled, true);
  const endsAt = Date.parse(result.body.endsAt);
  assert.ok(endsAt > Date.now());
  assert.ok(endsAt <= Date.now() + defaultWatchDurationMilliseconds + 1_000);
});

test('claimDue disables expired watches before leasing new work', async () => {
  const expired = row({
    endsAt: new Date('2026-11-06T23:59:00Z'),
    watchEnabled: true,
    nextCheckAt: new Date('2026-11-06T23:50:00Z'),
  });
  const statements = [];
  const pool = {
    async connect() {
      return {
        async query(sql) {
          statements.push(sql);
          if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql) || sql.includes('pg_advisory_xact_lock')) return { rows: [] };
          if (sql.includes('SET watch_enabled = FALSE') && sql.includes('ends_at <= ')) return { rows: [{ id: missionId }] };
          if (sql.includes('INSERT INTO mission.watch_authorization_audit')) return { rows: [] };
          if (sql.includes('SELECT * FROM mission.missions')) return { rows: [] };
          throw new Error(`unexpected query: ${sql}`);
        },
        release() {},
      };
    },
  };
  const store = new MissionStore({ pool });
  const result = await store.claimDue({ workerId: 'worker-expiry', now: new Date('2026-11-07T00:00:00Z') });
  assert.deepEqual(result, { ok: true, mission: null });
  assert.equal(statements.filter((sql) => sql.includes("'expired'")).length, 1);
});
