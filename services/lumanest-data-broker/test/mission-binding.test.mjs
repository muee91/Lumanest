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
      throw new Error('unbound existing missions must not be read');
    },
  };
  const store = new MissionStore({ pool });
  assert.deepEqual(await store.list(ownerId, 'a'.repeat(64)), {
    ok: false, error: 'unauthorized',
  });
  assert.match(queries.find((sql) => sql.includes('INSERT INTO mission.device_bindings')), /NOT EXISTS/);
});
