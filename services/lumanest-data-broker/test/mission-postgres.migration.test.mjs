import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import pg from 'pg';

const adminUrl = process.env.MISSION_TEST_MIGRATION_ADMIN_URL;
const { Pool } = pg;
const execFileAsync = promisify(execFile);

test('legacy migration freezes unconfirmed watch without losing its Mission',
  { skip: !adminUrl }, async () => {
    const admin = new Pool({ connectionString: adminUrl });
    const database = `lumanest_migration_${randomBytes(6).toString('hex')}`;
    const targetUrl = new URL(adminUrl);
    targetUrl.pathname = `/${database}`;
    let target;
    try {
      await admin.query(`CREATE DATABASE ${database}`);
      target = new Pool({ connectionString: targetUrl.toString() });
      await target.query(await readFile(new URL('../migrations/001_mission.sql', import.meta.url), 'utf8'));
      await target.query(`INSERT INTO mission.missions
        (id, owner_id, state, destination, intent, locale, watch_enabled, version,
         next_check_at, lease_owner, lease_until, created_at, updated_at)
        VALUES ('mis_legacy', 'owner_legacy', 'planning', '{}'::jsonb, 'photography',
          'zh-CN', TRUE, 1, now(), 'old-worker', now() + interval '1 hour', now(), now())`);
      const env = { ...process.env, MISSION_MIGRATION_DATABASE_URL: targetUrl.toString() };
      const script = fileURLToPath(new URL('../scripts/migrate-mission.mjs', import.meta.url));
      await execFileAsync(process.execPath, [script], { env });
      await execFileAsync(process.execPath, [script], { env });
      const result = await target.query(`SELECT watch_enabled, version, next_check_at,
        lease_owner, lease_until FROM mission.missions WHERE id = 'mis_legacy'`);
      assert.deepEqual(result.rows[0], { watch_enabled: false, version: 2,
        next_check_at: null, lease_owner: null, lease_until: null });
      const audit = await target.query("SELECT action FROM mission.watch_authorization_audit WHERE mission_id = 'mis_legacy'");
      assert.deepEqual(audit.rows, [{ action: 'legacy_suspended' }]);
      await assert.rejects(target.query("UPDATE mission.missions SET watch_enabled = TRUE WHERE id = 'mis_legacy'"),
        { code: '23514' });
      await assert.rejects(target.query("UPDATE mission.missions SET watch_intent_revision = 9007199254740992 WHERE id = 'mis_legacy'"),
        { code: '23514' });
      await assert.rejects(target.query("UPDATE mission.missions SET watch_authorization_epoch = 9007199254740992 WHERE id = 'mis_legacy'"),
        { code: '23514' });
      const safeValues = await target.query("SELECT watch_intent_revision, watch_authorization_epoch FROM mission.missions WHERE id = 'mis_legacy'");
      assert.deepEqual(safeValues.rows[0], { watch_intent_revision: '0', watch_authorization_epoch: '0' });
    } finally {
      await target?.end();
      await admin.query(`DROP DATABASE IF EXISTS ${database}`);
      await admin.end();
    }
  });
