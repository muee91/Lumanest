-- Run this file once with MISSION_MIGRATION_DATABASE_URL using the dedicated
-- migration role. The API and Worker roles must not receive DDL privileges.
CREATE SCHEMA IF NOT EXISTS mission;

CREATE TABLE IF NOT EXISTS mission.missions (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('planning', 'enRoute', 'field', 'completed', 'cancelled')),
  destination JSONB NOT NULL,
  intent TEXT NOT NULL CHECK (intent IN ('photography', 'food', 'supplies', 'fuel', 'wildlife')),
  locale TEXT NOT NULL CHECK (locale IN ('zh-CN', 'en')),
  watch_enabled BOOLEAN NOT NULL,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  version INTEGER NOT NULL CHECK (version > 0),
  next_check_at TIMESTAMPTZ,
  last_checked_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  lease_owner TEXT,
  lease_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS missions_one_open_per_owner
  ON mission.missions (owner_id)
  WHERE state IN ('planning', 'enRoute', 'field');
CREATE INDEX IF NOT EXISTS missions_due_checks
  ON mission.missions (next_check_at)
  WHERE watch_enabled = TRUE AND state IN ('planning', 'enRoute', 'field');

CREATE TABLE IF NOT EXISTS mission.mission_operations (
  owner_id TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  mission_id TEXT,
  status INTEGER NOT NULL CHECK (status BETWEEN 200 AND 299),
  response JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (owner_id, operation_id)
);
CREATE INDEX IF NOT EXISTS mission_operations_created_at
  ON mission.mission_operations (created_at);

CREATE TABLE IF NOT EXISTS mission.mission_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mission_id TEXT NOT NULL REFERENCES mission.missions(id) ON DELETE CASCADE,
  dedupe_key TEXT NOT NULL,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ,
  payload JSONB NOT NULL,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  UNIQUE (mission_id, dedupe_key)
);
CREATE INDEX IF NOT EXISTS mission_events_mission_created_at
  ON mission.mission_events (mission_id, created_at DESC);

CREATE TABLE IF NOT EXISTS mission.mission_checks (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mission_id TEXT NOT NULL REFERENCES mission.missions(id) ON DELETE CASCADE,
  worker_id TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('completed', 'failed')),
  context_id TEXT,
  error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS mission_checks_mission_created_at
  ON mission.mission_checks (mission_id, created_at DESC);
