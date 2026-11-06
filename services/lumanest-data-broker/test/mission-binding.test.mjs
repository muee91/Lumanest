import assert from 'node:assert/strict';
import test from 'node:test';

import { MissionStore } from '../src/mission/store.mjs';

test('a stored Mission binding refuses a different device secret digest', async () => {
  const ownerId = 'abcdefghijklmnopqrstuvwx';
  const originalHash = 'a'.repeat(64);
  const queries = [];
  const pool = {
    async query(sql) {
      queries.push(sql);
      if (sql.includes('SELECT owner_secret_hash')) {
        return { rows: [{ owner_secret_hash: originalHash, revoked_at: null }] };
      }
      if (sql.includes('UPDATE mission.device_bindings')) return { rows: [] };
      throw new Error('unauthorized request must not read missions');
    },
  };
  const store = new MissionStore({ pool });
  const result = await store.list(ownerId, 'b'.repeat(64));
  assert.deepEqual(result, { ok: false, error: 'unauthorized' });
  assert.equal(queries.some((sql) => sql.includes('FROM mission.missions')), false);
});

test('first binding is conditional on no previously unbound missions', async () => {
  const ownerId = 'abcdefghijklmnopqrstuvwx';
  const queries = [];
  const pool = {
    async query(sql) {
      queries.push(sql);
      if (sql.includes('SELECT owner_secret_hash')) return { rows: [] };
      if (sql.includes('INSERT INTO mission.device_bindings')) return { rows: [] };
      if (sql.includes('UPDATE mission.device_bindings')) return { rows: [] };
      throw new Error('unbound existing missions must not be read');
    },
  };
  const store = new MissionStore({ pool });
  assert.deepEqual(await store.list(ownerId, 'a'.repeat(64)), {
    ok: false, error: 'unauthorized',
  });
  assert.match(queries.find((sql) => sql.includes('INSERT INTO mission.device_bindings')), /NOT EXISTS/);
});

test('binding heartbeat rechecks the secret and revocation in one update', async () => {
  const ownerId = 'abcdefghijklmnopqrstuvwx';
  const bindingHash = 'a'.repeat(64);
  let updateParams;
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT owner_secret_hash')) {
        return { rows: [{ owner_secret_hash: bindingHash, revoked_at: null }] };
      }
      if (sql.includes('UPDATE mission.device_bindings')) {
        updateParams = params;
        assert.match(sql, /owner_secret_hash = \$3/);
        assert.match(sql, /revoked_at IS NULL/);
        return { rows: [{ principal_id: ownerId }] };
      }
      if (sql.includes('SELECT \* FROM mission.missions')) return { rows: [] };
      throw new Error(`unexpected query: ${sql}`);
    },
  };
  const store = new MissionStore({ pool });
  assert.deepEqual(await store.list(ownerId, bindingHash), { ok: true, body: [] });
  assert.equal(updateParams[1], ownerId);
  assert.equal(updateParams[2], bindingHash);
});
