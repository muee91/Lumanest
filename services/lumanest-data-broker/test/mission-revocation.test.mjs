import assert from 'node:assert/strict';
import test from 'node:test';

import { MissionStore } from '../src/mission/store.mjs';

test('Mission device revocation is idempotent across retries and restore', async () => {
  const installationId = 'abcdefghijklmnopqrstuvwx';
  let revoked = false;
  let missionUpdates = 0;
  let auditRows = 0;
  const pool = {
    async connect() {
      return {
        async query(sql, params = []) {
          if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return { rows: [] };
          if (sql.includes('UPDATE mission.device_bindings')) {
            const requestedRevoked = params[2] === true;
            const changed = requestedRevoked !== revoked;
            if (changed) revoked = requestedRevoked;
            return { rows: changed ? [{ principal_id: 'owner-1' }] : [] };
          }
          if (sql.includes('UPDATE mission.missions')) {
            missionUpdates += 1;
            return { rows: [{ id: 'mis_1' }] };
          }
          if (sql.includes('INSERT INTO mission.watch_authorization_audit')) {
            auditRows += 1;
            return { rows: [] };
          }
          throw new Error(`unexpected query: ${sql}`);
        },
        release() {},
      };
    },
  };
  const store = new MissionStore({ pool });

  assert.deepEqual(await store.setInstallationRevoked(installationId, true), { ok: true });
  assert.deepEqual(await store.setInstallationRevoked(installationId, true), { ok: true });
  assert.deepEqual(await store.setInstallationRevoked(installationId, false), { ok: true });
  assert.deepEqual(await store.setInstallationRevoked(installationId, false), { ok: true });
  assert.equal(missionUpdates, 1);
  assert.equal(auditRows, 1);
});
