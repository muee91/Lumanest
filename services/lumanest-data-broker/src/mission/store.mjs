import { randomBytes } from 'node:crypto';
import pg from 'pg';

import { apiErrorCodes } from '../api/error-codes.mjs';
import {
  missionEventResponse,
  missionResponse,
  missionStateTransitions,
} from './contract.mjs';

const { Pool } = pg;

const checkIntervalMilliseconds = 10 * 60 * 1_000;
const leaseMilliseconds = 2 * 60 * 1_000;

function missionId() {
  return `mis_${randomBytes(16).toString('hex')}`;
}

function asDate(value) {
  return value == null ? null : new Date(value);
}

function isUniqueViolation(error) {
  return error?.code === '23505';
}

function operationId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._-]{16,128}$/.test(value)
    ? value
    : null;
}

export class MissionStore {
  #pool;
  #ownsPool;

  constructor({ connectionString = '', pool = null, max = 8 } = {}) {
    this.#pool = pool ?? (connectionString ? new Pool({ connectionString, max }) : null);
    this.#ownsPool = pool == null && this.#pool != null;
  }

  get configured() {
    return this.#pool != null;
  }

  async close() {
    if (this.#ownsPool) await this.#pool.end();
  }

  async create({ ownerId, request, operation }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!operationId(operation)) return { ok: false, error: apiErrorCodes.invalidOperation };
    const client = await this.#pool.connect();
    const now = new Date();
    try {
      await client.query('BEGIN');
      const replay = await this.#replayOperation(client, ownerId, operation);
      if (replay != null) {
        await client.query('COMMIT');
        return { ok: true, replayed: true, status: replay.status, body: replay.body };
      }
      const id = missionId();
      const result = await client.query(
        `INSERT INTO mission.missions
          (id, owner_id, state, destination, intent, locale, watch_enabled,
           starts_at, ends_at, version, next_check_at, created_at, updated_at)
         VALUES ($1, $2, 'planning', $3::jsonb, $4, $5, $6, $7, $8, 1,
                 CASE WHEN $6 THEN COALESCE($7, $9) ELSE NULL END, $9, $9)
         RETURNING *`,
        [
          id,
          ownerId,
          JSON.stringify(request.destination),
          request.intent,
          request.locale,
          request.watchEnabled,
          asDate(request.startsAt),
          asDate(request.endsAt),
          now,
        ],
      );
      const body = missionResponse(result.rows[0]);
      await this.#saveOperation(client, ownerId, operation, id, 201, body, now);
      await client.query('COMMIT');
      return { ok: true, replayed: false, status: 201, body };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      if (isUniqueViolation(error)) return { ok: false, error: apiErrorCodes.conflict };
      throw error;
    } finally {
      client.release();
    }
  }

  async list(ownerId) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const result = await this.#pool.query(
      `SELECT * FROM mission.missions WHERE owner_id = $1
       ORDER BY updated_at DESC LIMIT 50`,
      [ownerId],
    );
    return { ok: true, body: result.rows.map(missionResponse) };
  }

  async get(ownerId, id) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const result = await this.#pool.query(
      'SELECT * FROM mission.missions WHERE owner_id = $1 AND id = $2',
      [ownerId, id],
    );
    return { ok: true, body: result.rows.length === 0 ? null : missionResponse(result.rows[0]) };
  }

  async patch({ ownerId, id, request, operation }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!operationId(operation)) return { ok: false, error: apiErrorCodes.invalidOperation };
    const client = await this.#pool.connect();
    const now = new Date();
    try {
      await client.query('BEGIN');
      const replay = await this.#replayOperation(client, ownerId, operation);
      if (replay != null) {
        await client.query('COMMIT');
        return { ok: true, replayed: true, status: replay.status, body: replay.body };
      }
      const currentResult = await client.query(
        'SELECT * FROM mission.missions WHERE owner_id = $1 AND id = $2 FOR UPDATE',
        [ownerId, id],
      );
      if (currentResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.notFound };
      }
      const current = currentResult.rows[0];
      if (current.version !== request.expectedVersion) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
      }
      let state = current.state;
      let watchEnabled = current.watch_enabled;
      let destination = current.destination;
      if (request.operation === 'cancel') {
        if (!['planning', 'enRoute', 'field'].includes(state)) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        state = 'cancelled';
      } else if (request.operation === 'setWatch') {
        if (['completed', 'cancelled'].includes(state)) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        watchEnabled = request.watchEnabled;
      } else if (request.operation === 'updateDestination') {
        if (state !== 'planning') {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        destination = request.destination;
      } else {
        const transition = missionStateTransitions[request.operation];
        if (transition == null || state !== transition[0]) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        state = transition[1];
      }
      const nextCheckAt = watchEnabled && !['completed', 'cancelled'].includes(state)
        ? new Date(now.getTime() + checkIntervalMilliseconds)
        : null;
      const result = await client.query(
        `UPDATE mission.missions
            SET state = $1, destination = $2::jsonb, watch_enabled = $3,
                version = version + 1, next_check_at = $4,
                updated_at = $5, completed_at = CASE WHEN $1 IN ('completed', 'cancelled') THEN $5 ELSE completed_at END
          WHERE owner_id = $6 AND id = $7 AND version = $8
          RETURNING *`,
        [state, JSON.stringify(destination), watchEnabled, nextCheckAt, now, ownerId, id, request.expectedVersion],
      );
      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.conflict };
      }
      const body = missionResponse(result.rows[0]);
      await this.#saveOperation(client, ownerId, operation, id, 200, body, now);
      await client.query('COMMIT');
      return { ok: true, replayed: false, status: 200, body };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      if (isUniqueViolation(error)) return { ok: false, error: apiErrorCodes.conflict };
      throw error;
    } finally {
      client.release();
    }
  }

  async events(ownerId, missionIdValue) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const mission = await this.#pool.query(
      'SELECT 1 FROM mission.missions WHERE owner_id = $1 AND id = $2',
      [ownerId, missionIdValue],
    );
    if (mission.rows.length === 0) return { ok: true, body: null };
    const result = await this.#pool.query(
      `SELECT event.*
         FROM mission.mission_events event
         JOIN mission.missions mission ON mission.id = event.mission_id
        WHERE mission.owner_id = $1 AND mission.id = $2
        ORDER BY event.created_at DESC LIMIT 100`,
      [ownerId, missionIdValue],
    );
    return { ok: true, body: result.rows.map(missionEventResponse) };
  }

  async claimDue({ workerId, now = new Date() } = {}) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `SELECT * FROM mission.missions
          WHERE state IN ('planning', 'enRoute', 'field')
            AND watch_enabled = TRUE
            AND next_check_at IS NOT NULL AND next_check_at <= $1
            AND (lease_until IS NULL OR lease_until < $1)
          ORDER BY next_check_at ASC
          FOR UPDATE SKIP LOCKED LIMIT 1`,
        [now],
      );
      if (result.rows.length === 0) {
        await client.query('COMMIT');
        return { ok: true, mission: null };
      }
      const mission = result.rows[0];
      const leaseUntil = new Date(now.getTime() + leaseMilliseconds);
      const leased = await client.query(
        `UPDATE mission.missions
            SET lease_owner = $1, lease_until = $2, updated_at = $3
          WHERE id = $4 AND version = $5 AND watch_enabled = TRUE
          RETURNING *`,
        [workerId, leaseUntil, now, mission.id, mission.version],
      );
      await client.query('COMMIT');
      return { ok: true, mission: leased.rows.length === 0 ? null : leased.rows[0] };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async finishCheck({ mission, workerId, check, events = [], now = new Date() }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      const currentResult = await client.query(
        `SELECT * FROM mission.missions
          WHERE id = $1 AND version = $2 AND lease_owner = $3
          FOR UPDATE`,
        [mission.id, mission.version, workerId],
      );
      if (currentResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.leaseLost };
      }
      const current = currentResult.rows[0];
      const stillActive = current.watch_enabled &&
        ['planning', 'enRoute', 'field'].includes(current.state);
      const nextCheckAt = stillActive
        ? new Date(now.getTime() + checkIntervalMilliseconds)
        : null;
      await client.query(
        `UPDATE mission.missions
            SET lease_owner = NULL, lease_until = NULL, last_checked_at = $1,
                next_check_at = $2, updated_at = $1
          WHERE id = $3 AND version = $4 AND lease_owner = $5`,
        [now, nextCheckAt, mission.id, mission.version, workerId],
      );
      let insertedEvents = 0;
      if (stillActive && check.ok) {
        for (const event of events) {
          const inserted = await client.query(
            `INSERT INTO mission.mission_events
              (mission_id, dedupe_key, kind, source, observed_at, expires_at, payload, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)
             ON CONFLICT (mission_id, dedupe_key) DO NOTHING`,
            [mission.id, event.dedupeKey, event.kind, event.source, asDate(event.observedAt),
              asDate(event.expiresAt), JSON.stringify(event.payload), now],
          );
          insertedEvents += inserted.rowCount;
        }
      }
      await client.query(
        `INSERT INTO mission.mission_checks
          (mission_id, worker_id, started_at, finished_at, status, context_id, error_code, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [mission.id, workerId, asDate(check.startedAt), now, check.ok ? 'completed' : 'failed',
          check.contextId ?? null, check.ok ? null : check.error ?? 'evaluation_failed', now],
      );
      await client.query('COMMIT');
      return { ok: true, insertedEvents };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async #replayOperation(client, ownerId, operation) {
    const result = await client.query(
      'SELECT status, response FROM mission.mission_operations WHERE owner_id = $1 AND operation_id = $2',
      [ownerId, operation],
    );
    if (result.rows.length === 0) return null;
    return { status: result.rows[0].status, body: result.rows[0].response };
  }

  async #saveOperation(client, ownerId, operation, missionIdValue, status, body, now) {
    await client.query(
      `INSERT INTO mission.mission_operations
        (owner_id, operation_id, mission_id, status, response, created_at)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6)`,
      [ownerId, operation, missionIdValue, status, JSON.stringify(body), now],
    );
  }
}

export { checkIntervalMilliseconds };
