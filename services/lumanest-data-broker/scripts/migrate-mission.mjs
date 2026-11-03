import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';

const connectionString = process.env.MISSION_MIGRATION_DATABASE_URL?.trim();
if (!connectionString) {
  throw new Error('MISSION_MIGRATION_DATABASE_URL is required');
}

const sql = await readFile(new URL('../migrations/001_mission.sql', import.meta.url), 'utf8');
const pool = new Pool({ connectionString, max: 1 });
try {
  await pool.query(sql);
} finally {
  await pool.end();
}
