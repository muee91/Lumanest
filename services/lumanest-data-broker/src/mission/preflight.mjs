import pg from 'pg';

const { Pool } = pg;

const requiredMigrations = [
  '001_mission.sql',
  '002_mission_operation_fingerprint.sql',
  '003_watch_authorization.sql',
  '004_mission_generations.sql',
];

const role = process.env.MISSION_PREFLIGHT_ROLE?.trim();
const connectionString = role === 'worker'
  ? process.env.MISSION_WORKER_DATABASE_URL?.trim()
  : role === 'api'
    ? process.env.MISSION_DATABASE_URL?.trim()
    : '';

if (!connectionString || !['api', 'worker'].includes(role)) {
  throw new Error('MISSION_PREFLIGHT_ROLE and its runtime database URL are required');
}

const pool = new Pool({
  connectionString,
  max: 1,
  connectionTimeoutMillis: 5_000,
  query_timeout: 5_000,
  statement_timeout: 5_000,
});

const privileges = role === 'api'
  ? [
      ['mission.device_bindings', 'SELECT'],
      ['mission.device_bindings', 'INSERT'],
      ['mission.device_bindings', 'UPDATE'],
      ['mission.missions', 'SELECT'],
      ['mission.missions', 'INSERT'],
      ['mission.missions', 'UPDATE'],
      ['mission.mission_operations', 'SELECT'],
      ['mission.mission_operations', 'INSERT'],
      ['mission.watch_authorization_audit', 'SELECT'],
      ['mission.watch_authorization_audit', 'INSERT'],
      ['mission.mission_events', 'SELECT'],
      ['mission.schema_migrations', 'SELECT'],
    ]
  : [
      ['mission.missions', 'SELECT'],
      ['mission.missions', 'INSERT'],
      ['mission.missions', 'UPDATE'],
      ['mission.mission_events', 'SELECT'],
      ['mission.mission_events', 'INSERT'],
      ['mission.mission_checks', 'SELECT'],
      ['mission.mission_checks', 'INSERT'],
      ['mission.schema_migrations', 'SELECT'],
    ];

const [schemaResult, privilegeResult] = await Promise.all([
  pool.query(
    'SELECT version FROM mission.schema_migrations WHERE version = ANY($1::text[])',
    [requiredMigrations],
  ),
  pool.query(
    `SELECT table_name, privilege_type
       FROM information_schema.role_table_grants
      WHERE grantee = current_user
        AND table_schema = 'mission'
        AND (table_name, privilege_type) IN (SELECT * FROM unnest($1::text[], $2::text[]))`,
    [privileges.map(([table]) => table.split('.')[1]), privileges.map(([, privilege]) => privilege)],
  ),
]);

const applied = new Set(schemaResult.rows.map((row) => row.version));
const missingMigrations = requiredMigrations.filter((migration) => !applied.has(migration));
if (missingMigrations.length !== 0) {
  throw new Error(`Mission migrations are incomplete: ${missingMigrations.join(', ')}`);
}

const granted = new Set(privilegeResult.rows.map((row) => `${row.table_name}:${row.privilege_type}`));
const missingPrivileges = privileges
  .filter(([table, privilege]) => !granted.has(`${table.split('.')[1]}:${privilege}`))
  .map(([table, privilege]) => `${table} ${privilege}`);
if (missingPrivileges.length !== 0) {
  throw new Error(`Mission runtime privileges are incomplete for ${role}: ${missingPrivileges.join(', ')}`);
}

console.log(`Mission ${role} preflight passed for ${requiredMigrations.length} migrations and ${privileges.length} privileges.`);
await pool.end();
