import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import test from 'node:test';
import pg from 'pg';
import { MissionStore } from '../src/mission/store.mjs';

const databaseUrl = process.env.MISSION_TEST_DATABASE_URL;
const { Pool } = pg;

test('PostgreSQL serializes duplicate operation IDs and detects mismatched payloads',
  { skip: !databaseUrl }, async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    const cleanupPool = new Pool({ connectionString: process.env.MISSION_TEST_CLEANUP_DATABASE_URL ?? databaseUrl });
    const store = new MissionStore({ pool });
    const ownerId = randomBytes(16).toString('hex');
    const bindingHash = randomBytes(32).toString('hex');
    const operation = `integration-${randomBytes(16).toString('hex')}`;
    const request = {
      destination: { name: '西湖', latitude: 30.2, longitude: 120.1, system: 'wgs84' },
      intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null, watchEnabled: false,
    };
    try {
      const [first, second] = await Promise.all([
        store.create({ ownerId, bindingHash, request, operation }),
        store.create({ ownerId, bindingHash, request, operation }),
      ]);
      assert.equal(first.ok, true);
      assert.equal(second.ok, true);
      assert.equal(first.body.id, second.body.id);
      assert.equal([first.replayed, second.replayed].filter(Boolean).length, 1);
      const lookup = await store.getOperation(ownerId, bindingHash, operation);
      assert.deepEqual(lookup.body, { missionId: first.body.id, status: 201, verifiable: true });
      assert.deepEqual(await store.getOperation(ownerId, 'f'.repeat(64), operation),
        { ok: false, error: 'unauthorized' });
      const otherOwner = randomBytes(16).toString('hex');
      assert.equal((await store.getOperation(otherOwner, bindingHash, operation)).body, null);
      await cleanupPool.query('DELETE FROM mission.device_bindings WHERE principal_id = $1', [otherOwner]);
      const mismatch = await store.create({ ownerId, bindingHash, operation,
        request: { ...request, locale: 'en' } });
      assert.deepEqual(mismatch, { ok: false, error: 'idempotency_mismatch' });
      const counts = await pool.query('SELECT COUNT(*)::int AS count FROM mission.missions WHERE owner_id = $1', [ownerId]);
      assert.equal(counts.rows[0].count, 1);
      const authorizationRequest = {
        expectedVersion: 1, operation: 'authorizeWatch', watchEnabled: true,
        destination: null, intentRevision: 1,
      };
      const authorized = await store.patch({ ownerId, bindingHash, id: first.body.id,
        operation: `${operation}-authorize`, request: authorizationRequest });
      assert.equal(authorized.ok, true);
      const replayedAuthorization = await store.patch({ ownerId, bindingHash, id: first.body.id,
        operation: `${operation}-authorize`, request: authorizationRequest });
      assert.equal(replayedAuthorization.replayed, true);
      const stale = await store.patch({ ownerId, bindingHash, id: first.body.id,
        operation: `${operation}-stale`, request: { ...authorizationRequest, expectedVersion: 2, intentRevision: 1 } });
      assert.deepEqual(stale.error, 'stale_watch_intent');
      const [start, cancel] = await Promise.all([
        store.patch({ ownerId, bindingHash, id: first.body.id, operation: `${operation}-start`,
          request: { expectedVersion: 2, operation: 'start', watchEnabled: null, destination: null } }),
        store.patch({ ownerId, bindingHash, id: first.body.id, operation: `${operation}-cancel`,
          request: { expectedVersion: 2, operation: 'cancel', watchEnabled: null, destination: null } }),
      ]);
      assert.equal([start, cancel].filter((result) => result.ok).length, 1);
      assert.equal([start, cancel].filter((result) => result.error === 'conflict').length, 1);
      // Simulate a pre-002 operation record: preserve its association without
      // pretending the missing original request can be authenticated.
      await cleanupPool.query('UPDATE mission.mission_operations SET request_fingerprint = NULL, request_fingerprint_version = NULL WHERE owner_id = $1 AND operation_id = $2', [ownerId, operation]);
      assert.deepEqual((await store.getOperation(ownerId, bindingHash, operation)).body,
        { missionId: first.body.id, status: 201, verifiable: false });
      assert.deepEqual(await store.create({ ownerId, bindingHash, request, operation }),
        { ok: false, error: 'legacy_operation_unverifiable' });
    } finally {
      await cleanupPool.query('DELETE FROM mission.mission_operations WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.missions WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.device_bindings WHERE principal_id = $1', [ownerId]);
      await pool.end();
      await cleanupPool.end();
    }
  });

test('restricted API and worker roles can complete a leased check',
  { skip: !databaseUrl || !process.env.MISSION_TEST_WORKER_DATABASE_URL }, async () => {
    const apiPool = new Pool({ connectionString: databaseUrl });
    const workerPool = new Pool({ connectionString: process.env.MISSION_TEST_WORKER_DATABASE_URL });
    const cleanupPool = new Pool({ connectionString: process.env.MISSION_TEST_CLEANUP_DATABASE_URL });
    const api = new MissionStore({ pool: apiPool });
    const worker = new MissionStore({ pool: workerPool });
    const ownerId = randomBytes(16).toString('hex');
    const bindingHash = randomBytes(32).toString('hex');
    const operation = `integration-${randomBytes(16).toString('hex')}`;
    try {
      const created = await api.create({ ownerId, bindingHash, operation, request: {
        destination: { name: '西湖', latitude: 30.2, longitude: 120.1, system: 'wgs84' },
        intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null, watchEnabled: false,
      } });
      assert.equal(created.ok, true);
      const oldEnable = await api.patch({ ownerId, bindingHash, id: created.body.id, operation: `${operation}-old-enable`,
        request: { expectedVersion: 1, operation: 'setWatch', watchEnabled: true, destination: null } });
      assert.deepEqual(oldEnable, { ok: false, error: 'mission_consent_required' });
      const authorized = await api.patch({ ownerId, bindingHash, id: created.body.id, operation: `${operation}-authorize`,
        request: { expectedVersion: 1, operation: 'authorizeWatch', watchEnabled: true, destination: null, intentRevision: 1 } });
      assert.equal(authorized.body.watchEnabled, true);
      const now = new Date(Date.now() + 11 * 60_000);
      const claim = await worker.claimDue({ workerId: 'integration-worker', now });
      assert.equal(claim.mission.id, created.body.id);
      const stopped = await api.patch({ ownerId, bindingHash, id: created.body.id,
        operation: `${operation}-stop`, request: {
          expectedVersion: claim.mission.version, operation: 'setWatch',
          watchEnabled: false, destination: null,
        } });
      assert.equal(stopped.body.watchEnabled, false);
      assert.equal(stopped.body.watchIntentRevision, 2);
      const replayedOldAuthorization = await api.patch({ ownerId, bindingHash, id: created.body.id,
        operation: `${operation}-authorize`, request: {
          expectedVersion: 1, operation: 'authorizeWatch', watchEnabled: true,
          destination: null, intentRevision: 1,
        } });
      assert.equal(replayedOldAuthorization.replayed, true);
      assert.equal((await api.get(ownerId, bindingHash, created.body.id)).body.watchEnabled, false);
      const reauthorized = await api.patch({ ownerId, bindingHash, id: created.body.id,
        operation: `${operation}-reauthorize`, request: {
          expectedVersion: stopped.body.version, operation: 'authorizeWatch',
          watchEnabled: true, destination: null, intentRevision: 3,
        } });
      assert.equal(reauthorized.body.watchEnabled, true);
      await cleanupPool.query(
        "UPDATE mission.missions SET lease_epoch = 9007199254740993 WHERE id = $1",
        [created.body.id],
      );
      const stale = await worker.finishCheck({ mission: claim.mission, workerId: 'integration-worker',
        check: { ok: true, startedAt: now.toISOString(), contextId: 'ctx_old' }, now });
      assert.deepEqual(stale, { ok: false, error: 'lease_lost' });
      const staleWrites = await cleanupPool.query(
        'SELECT (SELECT COUNT(*) FROM mission.mission_checks WHERE mission_id = $1)::int AS checks, ' +
        '(SELECT COUNT(*) FROM mission.mission_events WHERE mission_id = $1)::int AS events',
        [created.body.id],
      );
      assert.deepEqual(staleWrites.rows[0], { checks: 0, events: 0 });
      const renewedAt = new Date(now.getTime() + 121_000);
      const renewed = await worker.claimDue({ workerId: 'integration-worker', now: renewedAt });
      assert.equal(renewed.mission.id, created.body.id);
      assert.equal(renewed.mission.lease_epoch, '9007199254740994');
      const result = await worker.finishCheck({ mission: renewed.mission, workerId: 'integration-worker',
        check: { ok: true, startedAt: renewedAt.toISOString(), contextId: 'ctx_test' }, now: renewedAt,
        events: [{ dedupeKey: 'event-test', kind: 'weather', source: 'test',
          observedAt: now.toISOString(), expiresAt: null, payload: { sample: true } }],
      });
      assert.deepEqual(result, { ok: true, insertedEvents: 1 });
      const nextAt = new Date(renewedAt.getTime() + 11 * 60_000);
      const beforeRevoke = await worker.claimDue({ workerId: 'integration-worker', now: nextAt });
      assert.equal(beforeRevoke.mission.id, created.body.id);
      assert.deepEqual(await api.setInstallationRevoked(ownerId, true), { ok: true });
      assert.deepEqual(await api.get(ownerId, bindingHash, created.body.id),
        { ok: false, error: 'unauthorized' });
      const afterRevoke = await worker.finishCheck({ mission: beforeRevoke.mission,
        workerId: 'integration-worker', check: { ok: true, startedAt: nextAt.toISOString() }, now: nextAt });
      assert.deepEqual(afterRevoke, { ok: false, error: 'lease_lost' });
      await assert.rejects(workerPool.query('SELECT * FROM mission.device_bindings'), { code: '42501' });
      await assert.rejects(apiPool.query('CREATE TABLE mission.not_allowed (id int)'), { code: '42501' });
    } finally {
      await cleanupPool.query('DELETE FROM mission.mission_operations WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.missions WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.device_bindings WHERE principal_id = $1', [ownerId]);
      await apiPool.end();
      await workerPool.end();
      await cleanupPool.end();
    }
  });

test('two connections converge an authorize and a newer stop revision',
  { skip: !databaseUrl }, async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    const cleanupPool = new Pool({ connectionString: process.env.MISSION_TEST_CLEANUP_DATABASE_URL ?? databaseUrl });
    const store = new MissionStore({ pool });
    const ownerId = randomBytes(16).toString('hex');
    const bindingHash = randomBytes(32).toString('hex');
    const operation = `integration-${randomBytes(16).toString('hex')}`;
    try {
      const created = await store.create({ ownerId, bindingHash, operation, request: {
        destination: { name: '西湖', latitude: 30.2, longitude: 120.1, system: 'wgs84' },
        intent: 'photography', locale: 'zh-CN', startsAt: null, endsAt: null, watchEnabled: false,
      } });
      const [authorize, stop] = await Promise.all([
        store.patch({ ownerId, bindingHash, id: created.body.id, operation: `${operation}-authorize`,
          request: { expectedVersion: 1, operation: 'authorizeWatch', watchEnabled: true,
            destination: null, intentRevision: 11 } }),
        store.patch({ ownerId, bindingHash, id: created.body.id, operation: `${operation}-stop`,
          request: { expectedVersion: 1, operation: 'setWatch', watchEnabled: false,
            destination: null, intentRevision: 12 } }),
      ]);
      assert.equal([authorize.ok, stop.ok].filter(Boolean).length, 1);
      const current = (await store.get(ownerId, bindingHash, created.body.id)).body;
      if (current.watchEnabled || current.watchIntentRevision < 12) {
        const reconciled = await store.patch({ ownerId, bindingHash, id: created.body.id,
          operation: `${operation}-stop-retry`, request: {
            expectedVersion: current.version, operation: 'setWatch', watchEnabled: false,
            destination: null, intentRevision: 12,
          } });
        assert.equal(reconciled.body.watchEnabled, false);
      }
      const final = (await store.get(ownerId, bindingHash, created.body.id)).body;
      assert.equal(final.watchEnabled, false);
      assert.equal(final.watchIntentRevision, 12);
    } finally {
      await cleanupPool.query('DELETE FROM mission.mission_operations WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.missions WHERE owner_id = $1', [ownerId]);
      await cleanupPool.query('DELETE FROM mission.device_bindings WHERE principal_id = $1', [ownerId]);
      await pool.end();
      await cleanupPool.end();
    }
  });
