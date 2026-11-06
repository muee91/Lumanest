import assert from 'node:assert/strict';
import test from 'node:test';
import { MissionStore } from '../src/mission/store.mjs';

const ownerId = 'abcdefghijklmnopqrstuvwx';
const bindingHash = 'a'.repeat(64);
const operation = 'trip_operation_123456789';
const draft = {
  destination: { name: '西湖', latitude: 30.2, longitude: 120.1, system: 'wgs84' },
  intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null, watchEnabled: false,
};

function fakePool({ unsafeRevision = false } = {}) {
  const operations = new Map();
  let creates = 0;
  const client = {
    async query(sql, params = []) {
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql) || sql.includes('pg_advisory_xact_lock')) return { rows: [] };
      if (sql.includes('SELECT owner_secret_hash')) return { rows: [{ owner_secret_hash: bindingHash, revoked_at: null }] };
      if (sql.includes('UPDATE mission.device_bindings')) return { rows: [] };
      if (sql.includes('SELECT status, response, request_fingerprint')) {
        const row = operations.get(params[1]);
        return { rows: row ? [row] : [] };
      }
      if (sql.includes('INSERT INTO mission.missions')) {
        creates += 1;
        return { rows: [{ id: params[0], owner_id: params[1], state: 'planning',
          destination: JSON.parse(params[2]), intent: params[3], locale: params[4],
          watch_enabled: params[5], starts_at: params[6], ends_at: params[7],
          version: 1, created_at: params[8], updated_at: params[8],
          watch_intent_revision: unsafeRevision ? '9007199254740992' : '0',
          watch_authorization_epoch: '0' }] };
      }
      if (sql.includes('INSERT INTO mission.mission_operations')) {
        operations.set(params[1], { status: params[3], response: JSON.parse(params[4]), request_fingerprint: params[6], request_fingerprint_version: 1 });
        return { rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };
  return { operations, get creates() { return creates; }, async connect() { return client; } };
}

test('operation ID replays the same request and rejects changed or legacy payloads', async () => {
  const pool = fakePool();
  const store = new MissionStore({ pool });
  const original = await store.create({ ownerId, bindingHash, request: draft, operation });
  const reordered = { ...draft, destination: { system: 'wgs84', longitude: 120.1, latitude: 30.2, name: '西湖' } };
  const replay = await store.create({ ownerId, bindingHash, request: reordered, operation });
  assert.equal(original.ok, true);
  assert.equal(replay.replayed, true);
  assert.equal(replay.body.id, original.body.id);
  assert.equal(pool.creates, 1);
  assert.deepEqual(await store.create({ ownerId, bindingHash, request: { ...draft, locale: 'en' }, operation }),
    { ok: false, error: 'idempotency_mismatch' });
  assert.deepEqual(await store.patch({ ownerId, bindingHash, id: original.body.id,
    request: { operation: 'cancel', expectedVersion: 1, watchEnabled: null, destination: null }, operation }),
    { ok: false, error: 'idempotency_mismatch' });
  pool.operations.get(operation).request_fingerprint = null;
  assert.deepEqual(await store.create({ ownerId, bindingHash, request: draft, operation }),
    { ok: false, error: 'legacy_operation_unverifiable' });
  assert.equal(pool.creates, 1);
});

test('unsafe public BIGINT values fail before an operation can commit', async () => {
  const pool = fakePool({ unsafeRevision: true });
  const store = new MissionStore({ pool });
  await assert.rejects(
    store.create({ ownerId, bindingHash, request: draft, operation: `${operation}-unsafe` }),
    /watch_intent_revision exceeds JSON safe integer range/,
  );
  assert.equal(pool.operations.has(`${operation}-unsafe`), false);
});
