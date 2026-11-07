import { createHash, randomBytes } from 'node:crypto';
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
const defaultWatchDurationMilliseconds = 24 * 60 * 60 * 1_000;

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

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value != null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function requestFingerprint(kind, missionIdValue, request) {
  return createHash('sha256').update(canonicalJson({ fingerprintVersion: 1, kind, missionId: missionIdValue, request })).digest('hex');
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

  async setInstallationRevoked(installationId, revoked) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const client = await this.#pool.connect();
    const now = new Date();
    try {
      await client.query('BEGIN');
      // Binding first, Mission second: the API uses the same lock order. The
      // transition predicate makes retries idempotent, so a repeated revoke
      // cannot bump Mission versions or append duplicate audit rows.
      const bindings = await client.query(
        `UPDATE mission.device_bindings SET revoked_at = $2
         WHERE installation_id = $1
           AND (($3::boolean AND revoked_at IS NULL) OR
                (NOT $3::boolean AND revoked_at IS NOT NULL))
         RETURNING principal_id`,
        [installationId, revoked ? now : null, revoked],
      );
      if (revoked && bindings.rows.length > 0) {
        const owners = [...new Set([installationId, ...bindings.rows.map((row) => row.principal_id)])];
        const missions = await client.query(
          `UPDATE mission.missions SET watch_enabled = FALSE, watch_consent_version = NULL,
             watch_consented_at = NULL, next_check_at = NULL, lease_owner = NULL,
             lease_until = NULL, version = version + 1, updated_at = $1
           WHERE owner_id = ANY($2::text[]) AND state IN ('planning', 'enRoute', 'field')
           RETURNING id`, [now, owners],
        );
        for (const mission of missions.rows) {
          await client.query(
            `INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
             VALUES ($1, $2, 'device_revoked', $3)`,
            [`revoke-${randomBytes(16).toString('hex')}`, mission.id, now],
          );
        }
      }
      await client.query('COMMIT');
      return { ok: true };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async create({ ownerId, bindingHash, request, operation }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!operationId(operation)) return { ok: false, error: apiErrorCodes.invalidOperation };
    // A create is not an explicit authorization to run background checks.
    if (request.watchEnabled) return { ok: false, error: apiErrorCodes.missionConsentRequired };
    const client = await this.#pool.connect();
    const now = new Date();
    const fingerprint = requestFingerprint('create', null, request);
    try {
      await client.query('BEGIN');
      if (!await this.#ensureBinding(client, ownerId, bindingHash, now)) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.unauthorized };
      }
      await this.#lockOperation(client, ownerId, operation);
      const replay = await this.#replayOperation(client, ownerId, operation, fingerprint);
      if (replay != null) {
        if (replay.conflict) {
          await client.query('ROLLBACK');
          return { ok: false, error: replay.error };
        }
        await client.query('COMMIT');
        return { ok: true, replayed: true, status: replay.status, body: replay.body };
      }
      const id = missionId();
      const result = await client.query(
        `INSERT INTO mission.missions
          (id, owner_id, state, destination, intent, locale, watch_enabled,
           starts_at, ends_at, version, next_check_at, created_at, updated_at)
         VALUES ($1, $2, 'planning', $3::jsonb, $4, $5, $6, $7::timestamptz, $8::timestamptz, 1,
                 CASE WHEN $6 THEN COALESCE($7::timestamptz, $9::timestamptz) ELSE NULL END,
                 $9::timestamptz, $9::timestamptz)
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
      await this.#saveOperation(client, ownerId, operation, id, 201, body, now, fingerprint);
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

  async list(ownerId, bindingHash) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!await this.#ensureBinding(this.#pool, ownerId, bindingHash, new Date())) {
      return { ok: false, error: apiErrorCodes.unauthorized };
    }
    const result = await this.#pool.query(
      `SELECT * FROM mission.missions WHERE owner_id = $1
       ORDER BY updated_at DESC LIMIT 50`,
      [ownerId],
    );
    return { ok: true, body: result.rows.map(missionResponse) };
  }

  async get(ownerId, bindingHash, id) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!await this.#ensureBinding(this.#pool, ownerId, bindingHash, new Date())) {
      return { ok: false, error: apiErrorCodes.unauthorized };
    }
    const result = await this.#pool.query(
      'SELECT * FROM mission.missions WHERE owner_id = $1 AND id = $2',
      [ownerId, id],
    );
    return { ok: true, body: result.rows.length === 0 ? null : missionResponse(result.rows[0]) };
  }

  async getOperation(ownerId, bindingHash, operation) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!operationId(operation)) return { ok: false, error: apiErrorCodes.invalidOperation };
    if (!await this.#ensureBinding(this.#pool, ownerId, bindingHash, new Date())) {
      return { ok: false, error: apiErrorCodes.unauthorized };
    }
    const result = await this.#pool.query(
      `SELECT mission_id, status, request_fingerprint, request_fingerprint_version
       FROM mission.mission_operations WHERE owner_id = $1 AND operation_id = $2`,
      [ownerId, operation],
    );
    if (result.rows.length === 0) return { ok: true, body: null };
    const row = result.rows[0];
    return { ok: true, body: {
      missionId: row.mission_id,
      status: row.status,
      verifiable: row.request_fingerprint != null && row.request_fingerprint_version === 1,
    } };
  }

  async patch({ ownerId, bindingHash, id, request, operation }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!operationId(operation)) return { ok: false, error: apiErrorCodes.invalidOperation };
    const client = await this.#pool.connect();
    const now = new Date();
    const fingerprint = requestFingerprint('patch', id, request);
    try {
      await client.query('BEGIN');
      if (!await this.#ensureBinding(client, ownerId, bindingHash, now)) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.unauthorized };
      }
      await this.#lockOperation(client, ownerId, operation);
      const replay = await this.#replayOperation(client, ownerId, operation, fingerprint);
      if (replay != null) {
        if (replay.conflict) {
          await client.query('ROLLBACK');
          return { ok: false, error: replay.error };
        }
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
      let consentVersion = current.watch_consent_version;
      let consentedAt = current.watch_consented_at;
      let authorizationEpoch = BigInt(current.watch_authorization_epoch ?? 0);
      let endsAt = current.ends_at;
      const currentIntentRevision = BigInt(current.watch_intent_revision ?? 0);
      if (request.operation === 'authorizeWatch' && request.intentRevision == null) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.missionConsentRequired };
      }
      const intentRevision = request.intentRevision != null
        ? BigInt(request.intentRevision)
        : (request.operation === 'setWatch' && request.watchEnabled === false
          ? currentIntentRevision + 1n
          : currentIntentRevision);
      if (request.intentRevision != null && BigInt(request.intentRevision) <= currentIntentRevision) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.staleWatchIntent, current: missionResponse(current) };
      }
      let consentAudit = null;
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
        if (request.watchEnabled) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.missionConsentRequired };
        }
        watchEnabled = false;
        consentVersion = null;
        consentedAt = null;
        consentAudit = 'disabled';
      } else if (request.operation === 'authorizeWatch') {
        if (['completed', 'cancelled'].includes(state)) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        if (endsAt != null && new Date(endsAt).getTime() <= now.getTime()) {
          await client.query('ROLLBACK');
          return { ok: false, error: apiErrorCodes.conflict, current: missionResponse(current) };
        }
        if (endsAt == null) {
          endsAt = new Date(now.getTime() + defaultWatchDurationMilliseconds);
        }
        watchEnabled = true;
        consentVersion = 1;
        consentedAt = now;
        authorizationEpoch += 1n;
        consentAudit = 'authorized';
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
      if (['completed', 'cancelled'].includes(state)) {
        if (watchEnabled || consentVersion != null) consentAudit = 'disabled';
        watchEnabled = false;
        consentVersion = null;
        consentedAt = null;
      }
      const nextCheckAt = watchEnabled && !['completed', 'cancelled'].includes(state)
        ? new Date(now.getTime() + checkIntervalMilliseconds)
        : null;
      const result = await client.query(
        `UPDATE mission.missions
            SET state = $1, destination = $2::jsonb, watch_enabled = $3,
                version = version + 1, next_check_at = $4,
                updated_at = $5, completed_at = CASE WHEN $1 IN ('completed', 'cancelled') THEN $5 ELSE completed_at END,
                watch_consent_version = $9, watch_consented_at = $10,
                watch_intent_revision = $11, watch_authorization_epoch = $12,
                ends_at = $13
          WHERE owner_id = $6 AND id = $7 AND version = $8
          RETURNING *`,
        [state, JSON.stringify(destination), watchEnabled, nextCheckAt, now, ownerId, id, request.expectedVersion, consentVersion, consentedAt, intentRevision.toString(), authorizationEpoch.toString(), endsAt],
      );
      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.conflict };
      }
      const body = missionResponse(result.rows[0]);
      if (consentAudit != null) {
        await client.query(
          `INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
           VALUES ($1, $2, $3, $4)`,
          [`consent-${randomBytes(16).toString('hex')}`, id, consentAudit, now],
        );
      }
      await this.#saveOperation(client, ownerId, operation, id, 200, body, now, fingerprint);
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

  async events(ownerId, bindingHash, missionIdValue) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    if (!await this.#ensureBinding(this.#pool, ownerId, bindingHash, new Date())) {
      return { ok: false, error: apiErrorCodes.unauthorized };
    }
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

  async claimDue({ workerId, now = null } = {}) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      const expired = await client.query(
        `UPDATE mission.missions
            SET watch_enabled = FALSE, watch_consent_version = NULL,
                watch_consented_at = NULL, next_check_at = NULL,
                lease_owner = NULL, lease_until = NULL,
                version = version + 1, updated_at = COALESCE($1::timestamptz, clock_timestamp())
          WHERE state IN ('planning', 'enRoute', 'field')
            AND watch_enabled = TRUE
            AND ends_at IS NOT NULL
            AND ends_at <= COALESCE($1::timestamptz, clock_timestamp())
          RETURNING id`,
        [now],
      );
      for (const row of expired.rows) {
        await client.query(
          `INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
           VALUES ($1, $2, 'expired', COALESCE($3::timestamptz, clock_timestamp()))`,
          [`expire-${randomBytes(16).toString('hex')}`, row.id, now],
        );
      }
      const result = await client.query(
        `SELECT * FROM mission.missions
          WHERE state IN ('planning', 'enRoute', 'field')
            AND watch_enabled = TRUE
            AND watch_consent_version = 1 AND watch_consented_at IS NOT NULL
            AND next_check_at IS NOT NULL AND next_check_at <= COALESCE($1::timestamptz, clock_timestamp())
            AND (ends_at IS NULL OR ends_at > COALESCE($1::timestamptz, clock_timestamp()))
            AND (lease_until IS NULL OR lease_until < COALESCE($1::timestamptz, clock_timestamp()))
          ORDER BY next_check_at ASC
          FOR UPDATE SKIP LOCKED LIMIT 1`,
        [now],
      );
      if (result.rows.length === 0) {
        await client.query('COMMIT');
        return { ok: true, mission: null };
      }
      const mission = result.rows[0];
      const leased = await client.query(
        `UPDATE mission.missions
            SET lease_owner = $1,
                lease_until = COALESCE($2::timestamptz, clock_timestamp()) + interval '2 minutes',
                lease_epoch = lease_epoch + 1,
                updated_at = COALESCE($2::timestamptz, clock_timestamp())
          WHERE id = $3 AND version = $4 AND watch_enabled = TRUE
          RETURNING *`,
        [workerId, now, mission.id, mission.version],
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

  async finishCheck({ mission, workerId, check, events = [], now = null }) {
    if (!this.#pool) return { ok: false, error: apiErrorCodes.notConfigured };
    const client = await this.#pool.connect();
    try {
      await client.query('BEGIN');
      const currentResult = await client.query(
        `SELECT * FROM mission.missions
          WHERE id = $1 AND version = $2 AND lease_owner = $3
            AND lease_until > COALESCE($4::timestamptz, clock_timestamp())
            AND lease_until = $5 AND lease_epoch = $6
            AND watch_consent_version = 1 AND watch_consented_at IS NOT NULL
            AND watch_authorization_epoch = $7
          FOR UPDATE`,
        [mission.id, mission.version, workerId, now, mission.lease_until, mission.lease_epoch, mission.watch_authorization_epoch],
      );
      if (currentResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { ok: false, error: apiErrorCodes.leaseLost };
      }
      const current = currentResult.rows[0];
      const databaseNowResult = await client.query(
        'SELECT COALESCE($1::timestamptz, clock_timestamp()) AS now',
        [now],
      );
      const commitNow = new Date(databaseNowResult.rows[0].now);
      if (current.ends_at != null && new Date(current.ends_at).getTime() <= commitNow.getTime()) {
        await client.query(
          `UPDATE mission.missions
              SET watch_enabled = FALSE, watch_consent_version = NULL,
                  watch_consented_at = NULL, next_check_at = NULL,
                  lease_owner = NULL, lease_until = NULL,
                  version = version + 1, updated_at = $1
            WHERE id = $2 AND version = $3 AND lease_owner = $4`,
          [commitNow, mission.id, mission.version, workerId],
        );
        await client.query(
          `INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
           VALUES ($1, $2, 'expired', $3)`,
          [`expire-${randomBytes(16).toString('hex')}`, mission.id, commitNow],
        );
        await client.query('COMMIT');
        return { ok: false, error: apiErrorCodes.leaseLost };
      }
      const stillActive = current.watch_enabled &&
        ['planning', 'enRoute', 'field'].includes(current.state);
      const nextCheckAt = stillActive
        ? new Date(commitNow.getTime() + checkIntervalMilliseconds)
        : null;
      await client.query(
        `UPDATE mission.missions
            SET lease_owner = NULL, lease_until = NULL, last_checked_at = $1,
                next_check_at = $2, updated_at = $1
          WHERE id = $3 AND version = $4 AND lease_owner = $5`,
        [commitNow, nextCheckAt, mission.id, mission.version, workerId],
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
              asDate(event.expiresAt), JSON.stringify(event.payload), commitNow],
          );
          insertedEvents += inserted.rowCount;
        }
      }
      await client.query(
        `INSERT INTO mission.mission_checks
          (mission_id, worker_id, started_at, finished_at, status, context_id, error_code, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [mission.id, workerId, asDate(check.startedAt), commitNow, check.ok ? 'completed' : 'failed',
          check.contextId ?? null, check.ok ? null : check.error ?? 'evaluation_failed', commitNow],
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

  async #lockOperation(client, ownerId, operation) {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`${ownerId}:${operation}`]);
  }

  async #replayOperation(client, ownerId, operation, fingerprint) {
    const result = await client.query(
      'SELECT status, response, request_fingerprint, request_fingerprint_version FROM mission.mission_operations WHERE owner_id = $1 AND operation_id = $2',
      [ownerId, operation],
    );
    if (result.rows.length === 0) return null;
    if (result.rows[0].request_fingerprint == null) {
      return { conflict: true, error: apiErrorCodes.missionLegacyOperationUnverifiable };
    }
    if (result.rows[0].request_fingerprint_version !== 1 || result.rows[0].request_fingerprint !== fingerprint) {
      return { conflict: true, error: apiErrorCodes.missionIdempotencyMismatch };
    }
    return { status: result.rows[0].status, body: result.rows[0].response };
  }

  async #ensureBinding(queryable, ownerId, bindingHash, now) {
    if (typeof ownerId !== 'string' || !/^[A-Za-z0-9_-]{22,80}$/.test(ownerId) ||
        typeof bindingHash !== 'string' || !/^[a-f0-9]{64}$/.test(bindingHash)) {
      return false;
    }
    const existing = await queryable.query(
      'SELECT owner_secret_hash, revoked_at FROM mission.device_bindings WHERE principal_id = $1',
      [ownerId],
    );
    if (existing.rows.length === 0) {
      await queryable.query(
        `INSERT INTO mission.device_bindings
          (principal_id, installation_id, owner_secret_hash, bound_at, last_seen_at)
         SELECT $1, $1, $2, $3, $3
          WHERE NOT EXISTS (SELECT 1 FROM mission.missions WHERE owner_id = $1)
         ON CONFLICT DO NOTHING`,
        [ownerId, bindingHash, now],
      );
    }
    // Re-check the binding and update its heartbeat in one conditional
    // statement. Write callers hold the row lock until their surrounding
    // transaction commits, so an administrator revoking the device cannot
    // race a stale pre-check into a Mission mutation.
    const bound = await queryable.query(
      `UPDATE mission.device_bindings
          SET last_seen_at = $1
        WHERE principal_id = $2
          AND owner_secret_hash = $3
          AND revoked_at IS NULL
      RETURNING principal_id`,
      [now, ownerId, bindingHash],
    );
    return bound.rows.length === 1;
  }

  async #saveOperation(client, ownerId, operation, missionIdValue, status, body, now, fingerprint) {
    await client.query(
      `INSERT INTO mission.mission_operations
        (owner_id, operation_id, mission_id, status, response, created_at, request_fingerprint, request_fingerprint_version)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, 1)`,
      [ownerId, operation, missionIdValue, status, JSON.stringify(body), now, fingerprint],
    );
  }
}

export { checkIntervalMilliseconds, defaultWatchDurationMilliseconds };
