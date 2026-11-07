import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import pg from 'pg';

const { Pool } = pg;

const connectionString = process.env.MISSION_MIGRATION_DATABASE_URL?.trim();
if (!connectionString) {
  throw new Error('MISSION_MIGRATION_DATABASE_URL is required');
}

const migrations = ['001_mission.sql', '002_mission_operation_fingerprint.sql', '003_watch_authorization.sql', '004_mission_generations.sql', '005_mission_watch_expiry.sql'];
const baselineColumns = {
  missions: ['id', 'owner_id', 'state', 'destination', 'intent', 'locale', 'watch_enabled', 'starts_at', 'ends_at', 'version', 'next_check_at', 'last_checked_at', 'completed_at', 'lease_owner', 'lease_until', 'created_at', 'updated_at'],
  mission_operations: ['owner_id', 'operation_id', 'mission_id', 'status', 'response', 'created_at'],
  mission_events: ['id', 'mission_id', 'dedupe_key', 'kind', 'source', 'observed_at', 'expires_at', 'payload', 'delivered_at', 'created_at'],
  mission_checks: ['id', 'mission_id', 'worker_id', 'started_at', 'finished_at', 'status', 'context_id', 'error_code', 'created_at'],
};
const bindingColumns = ['principal_id', 'installation_id', 'owner_secret_hash', 'bound_at', 'last_seen_at', 'revoked_at'];
const pool = new Pool({ connectionString, max: 1 });
let client;
try {
  client = await pool.connect();
  await client.query('BEGIN');
  await client.query("SELECT pg_advisory_xact_lock(hashtext('lumanest-mission-migrations'))");
  // Both PR #39 and #40 predate the ledger. Refuse a partially created or
  // structurally incomplete legacy baseline instead of silently rebuilding it.
  const columns = await client.query(`SELECT table_name, column_name
    FROM information_schema.columns WHERE table_schema = 'mission'
      AND table_name = ANY($1::text[])`, [[...Object.keys(baselineColumns), 'device_bindings']]);
  const found = new Map();
  for (const row of columns.rows) {
    if (!found.has(row.table_name)) found.set(row.table_name, new Set());
    found.get(row.table_name).add(row.column_name);
  }
  if (found.size !== 0) {
    for (const [table, expected] of Object.entries(baselineColumns)) {
      const present = found.get(table);
      const missing = expected.filter((name) => !present?.has(name));
      if (missing.length) throw new Error(`Incomplete legacy Mission schema: ${table} missing ${missing.join(', ')}`);
    }
    if (found.has('device_bindings')) {
      const missing = bindingColumns.filter((name) => !found.get('device_bindings').has(name));
      if (missing.length) throw new Error(`Incomplete legacy Mission schema: device_bindings missing ${missing.join(', ')}`);
    }
  }
  const baseline = await readFile(new URL(`../migrations/${migrations[0]}`, import.meta.url), 'utf8');
  const schema = await client.query("SELECT to_regnamespace('mission') IS NOT NULL AS present");
  // PostgreSQL still checks database CREATE privilege for CREATE SCHEMA IF
  // NOT EXISTS. A dedicated migrator can own a precreated schema without that
  // broader privilege, so omit just that statement when it already exists.
  const executableBaseline = schema.rows[0].present
    ? baseline.replace(/^CREATE SCHEMA IF NOT EXISTS mission;\s*$/m, '')
    : baseline;
  await client.query(executableBaseline);
  await client.query(`CREATE TABLE IF NOT EXISTS mission.schema_migrations (
    version TEXT PRIMARY KEY, checksum TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`);
  for (const migration of migrations) {
    const sql = migration === migrations[0] ? baseline :
      await readFile(new URL(`../migrations/${migration}`, import.meta.url), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const applied = await client.query('SELECT checksum FROM mission.schema_migrations WHERE version = $1', [migration]);
    if (applied.rows.length !== 0) {
      if (applied.rows[0].checksum !== checksum) throw new Error(`Mission migration checksum mismatch: ${migration}`);
      continue;
    }
    if (migration !== migrations[0]) await client.query(sql);
    await client.query('INSERT INTO mission.schema_migrations (version, checksum) VALUES ($1, $2)', [migration, checksum]);
  }
  await client.query('COMMIT');
} catch (error) {
  if (client) await client.query('ROLLBACK').catch(() => {});
  throw error;
} finally {
  client?.release();
  await pool.end();
}
