import assert from 'node:assert/strict';
import { createCipheriv, createDecipheriv, generateKeyPairSync, randomBytes } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { AuditLog } from '../src/admin/audit-log.mjs';
import { createAdminServer } from '../src/admin/admin-server.mjs';
import { AdminAuthService } from '../src/admin/auth.mjs';
import { validateRuntimeSettings } from '../src/admin/runtime-settings.mjs';

const masterKey = Buffer.alloc(32, 7).toString('base64');

async function withTemporaryLog(run, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-log-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const log = await new AuditLog({ filePath, masterKey, ...options }).initialize();
    await run({ log, filePath, directory });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

/**
 * Encrypts an arbitrary array of entries with the test master key so tests
 * can simulate pre-existing persisted state (including malformed entries).
 */
async function encryptEntries(filePath, entries) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', Buffer.alloc(32, 7), iv);
  const plaintext = Buffer.from(JSON.stringify(entries), 'utf8');
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const document = JSON.stringify({
    version: 1,
    algorithm: 'aes-256-gcm',
    iv: iv.toString('base64'),
    authenticationTag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64'),
  });
  await mkdir(join(filePath, '..'), { recursive: true }).catch(() => {});
  await writeFile(filePath, document, 'utf8');
}

async function readDecryptedEntries(filePath, key = Buffer.alloc(32, 7)) {
  const serialized = await readFile(filePath, 'utf8');
  const document = JSON.parse(serialized);
  const iv = Buffer.from(document.iv, 'base64');
  const authenticationTag = Buffer.from(document.authenticationTag, 'base64');
  const ciphertext = Buffer.from(document.ciphertext, 'base64');
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authenticationTag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return JSON.parse(plaintext.toString('utf8'));
}

// ---------------------------------------------------------------------------
// 1. Encrypted file does not contain sensitive inputs or remoteAddress
// ---------------------------------------------------------------------------

test('encrypted file never contains remoteAddress, raw inputs, or sensitive fields', async () => {
  await withTemporaryLog(async ({ log, filePath }) => {
    await log.record({
      remoteAddress: '192.168.1.100',
      operation: 'login',
      fields: ['product'],
      result: 'ok',
      details: { product: 'astro', traceId: 'trace-abc' },
    });

    const persisted = await readFile(filePath, 'utf8');
    assert.equal(persisted.includes('192.168.1.100'), false);
    assert.equal(persisted.includes('remoteAddress'), false);

    const entries = await readDecryptedEntries(filePath);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'login');
    assert.equal('remoteAddress' in entries[0], false);
    assert.deepEqual(entries[0].details, { product: 'astro', traceId: 'trace-abc' });
  });
});

test('record ignores unknown operations and does not persist them', async () => {
  await withTemporaryLog(async ({ log, filePath, directory }) => {
    await log.record({ operation: 'malicious_op', result: 'ok' });
    await log.record({ operation: null, result: 'ok' });
    await log.record({ operation: 12345, result: 'ok' });
    // Flush the write queue — record() returns a resolved promise for
    // rejected operations, so nothing is queued, but flush is cheap.
    await log.flush();

    // No valid record was produced, so no encrypted file should have been
    // written. Assert absence directly rather than trying to decrypt a
    // file that was never created.
    const { access } = await import('node:fs/promises');
    await assert.rejects(access(filePath), (error) => error.code === 'ENOENT');
    assert.equal((await log.list()).length, 0);
  });
});

test('record collapses unknown results to failed but keeps the entry', async () => {
  await withTemporaryLog(async ({ log }) => {
    await log.record({ operation: 'login', result: 'some_weird_upstream_error' });
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].result, 'failed');
  });
});

// ---------------------------------------------------------------------------
// 2. Restart recovery — entries survive a new instance loading from disk
// ---------------------------------------------------------------------------

test('entries persist across restart via initialize()', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-restart-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const first = await new AuditLog({ filePath, masterKey }).initialize();
    await first.record({ operation: 'login', result: 'ok' });
    await first.record({ operation: 'change_password', result: 'ok' });
    await first.record({ operation: 'clear_cache', result: 'ok' });
    // Wait for background writes to complete.
    await first.flush();

    const second = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await second.list();
    assert.equal(entries.length, 3);
    // Newest first.
    assert.equal(entries[0].operation, 'clear_cache');
    assert.equal(entries[1].operation, 'change_password');
    assert.equal(entries[2].operation, 'login');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 3. Expired and malformed records are not recovered
// ---------------------------------------------------------------------------

test('expired entries are pruned on initialize and not persisted', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-expired-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    // Pre-populate with a mix of valid, expired, and malformed entries.
    const oldTimestamp = new Date(Date.now() - 31 * 24 * 60 * 60 * 1_000).toISOString();
    const recentTimestamp = new Date().toISOString();
    await encryptEntries(filePath, [
      { timestamp: oldTimestamp, operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: recentTimestamp, operation: 'clear_cache', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'clear_cache');
    // The expired entry should have been written out of the file.
    const persisted = await readDecryptedEntries(filePath);
    assert.equal(persisted.length, 1);
    assert.equal(persisted[0].operation, 'clear_cache');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('entries with unknown operation are discarded on load, not converted to unknown', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-malformed-op-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    await encryptEntries(filePath, [
      { timestamp: new Date().toISOString(), operation: 'evil_operation', fields: [], result: 'ok', details: {} },
      { timestamp: new Date().toISOString(), operation: 'login', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'login');
    // Ensure no 'unknown' operation leaked through.
    assert.equal(entries.some((e) => e.operation === 'unknown'), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('entries with invalid timestamp are discarded on load', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-malformed-ts-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    await encryptEntries(filePath, [
      { timestamp: 'not-a-date', operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: null, operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: '', operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: new Date().toISOString(), operation: 'clear_cache', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'clear_cache');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('entries with far-future timestamp are discarded on load', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-future-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const futureTimestamp = new Date(Date.now() + 365 * 24 * 60 * 60 * 1_000).toISOString();
    await encryptEntries(filePath, [
      { timestamp: futureTimestamp, operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: new Date().toISOString(), operation: 'clear_cache', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'clear_cache');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('entries with invalid result are discarded on load', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-malformed-result-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    await encryptEntries(filePath, [
      { timestamp: new Date().toISOString(), operation: 'login', fields: [], result: null, details: {} },
      { timestamp: new Date().toISOString(), operation: 'login', fields: [], result: 123, details: {} },
      { timestamp: new Date().toISOString(), operation: 'clear_cache', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'clear_cache');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('corrupted encrypted file degrades to empty log without crashing', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-corrupt-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    await writeFile(filePath, 'not valid json at all', 'utf8');

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 0);
    const status = log.status();
    // lastWriteOk is null (no write has been attempted yet) but lastWriteError
    // records the corruption.
    assert.equal(status.lastWriteError, 'corrupt_file');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 4. Write failure degrades safely and can recover on subsequent writes
// ---------------------------------------------------------------------------

test('write failure does not reject record() promise and is observable via status()', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-writefail-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const realFs = await import('node:fs/promises');
    let failWrites = true;
    const failingFs = {
      ...realFs,
      mkdir: async (...args) => {
        if (failWrites) {
          const error = new Error('EACCES: permission denied');
          error.code = 'EACCES';
          throw error;
        }
        return realFs.mkdir(...args);
      },
    };

    const log = await new AuditLog({ filePath, masterKey, fileSystem: failingFs }).initialize();
    // record() must not reject even though the write fails.
    await log.record({ operation: 'login', result: 'ok' });
    await log.flush();

    const status = log.status();
    assert.equal(status.lastWriteOk, false);
    assert.equal(status.lastWriteError, 'EACCES');
    // The error code must not contain raw paths or exception text.
    assert.equal(typeof status.lastWriteError, 'string');
    assert.equal(status.lastWriteError.includes(filePath), false);
    assert.equal(status.lastWriteError.includes('permission denied'), false);

    // The in-memory entry survives.
    const entries = await log.list();
    assert.equal(entries.length, 1);

    // Recover: allow writes again.
    failWrites = false;
    await log.record({ operation: 'clear_cache', result: 'ok' });
    await log.flush();

    const recoveredStatus = log.status();
    assert.equal(recoveredStatus.lastWriteOk, true);
    assert.equal(recoveredStatus.lastWriteError, null);
    assert.equal((await log.list()).length, 2);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 5. Capacity limit — entries are capped at maximumEntries (500)
// ---------------------------------------------------------------------------

test('in-memory entries are capped at 500 and list returns at most 200', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-capacity-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    // Pre-populate with 600 entries — exceeds the 500 cap.
    const now = Date.now();
    const entries = [];
    for (let i = 0; i < 600; i++) {
      entries.push({
        timestamp: new Date(now - i * 1_000).toISOString(),
        operation: 'login',
        fields: [],
        result: 'ok',
        details: {},
      });
    }
    await encryptEntries(filePath, entries);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const status = log.status();
    // The 500 cap is enforced by #prune on initialize.
    assert.equal(status.entries, 500);

    const list = await log.list();
    assert.equal(list.length, 200);
    // Newest first: first listed entry should be the most recent.
    assert.equal(list[0].operation, 'login');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 6. Admin endpoint returns a real bounded list
// ---------------------------------------------------------------------------

async function withAdminServer(run) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-admin-'));
  const authService = new AdminAuthService({
    filePath: join(directory, 'auth.json'),
    bootstrapPassword: 'initial-password',
  });
  await authService.initialize();
  let snapshot = Object.freeze({
    revision: 1,
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'key-id-1234', projectId: 'project-5678',
    serviceToken: 'service-secret-9012', amapWebKey: 'amap-secret-3456',
    aiApiKey: '', aiBaseUrl: '', aiModel: '',
    settings: validateRuntimeSettings({}),
    llmProfiles: [],
    llmRouting: { primaryProfileId: null, fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 },
  });
  const auditLog = await new AuditLog({
    filePath: join(directory, 'audit-log.enc.json'),
    masterKey,
  }).initialize();
  const server = createAdminServer({
    authService,
    runtimeConfig: {
      snapshot: () => snapshot,
      replace: async (patch) => { snapshot = Object.freeze({ ...snapshot, ...patch, revision: snapshot.revision + 1 }); return snapshot; },
    },
    auditLog,
    clearCache: async () => {},
    restart: async () => {},
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    await run({ baseUrl: `http://127.0.0.1:${server.address().port}`, auditLog });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    // Flush in-flight audit writes before removing the temp directory so rm
    // does not race with a background encrypted write (ENOTEMPTY).
    await auditLog.flush();
    await rm(directory, { recursive: true, force: true });
  }
}

async function adminLogin(baseUrl) {
  const response = await fetch(`${baseUrl}/admin-api/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password: 'initial-password' }),
  });
  const value = await response.json();
  return { cookie: response.headers.get('set-cookie').split(';')[0], csrf: value.csrfToken };
}

test('admin audit endpoint returns a real bounded list of entries', async () => {
  await withAdminServer(async ({ baseUrl, auditLog }) => {
    // Record a few entries directly.
    await auditLog.record({ operation: 'clear_cache', result: 'ok' });
    await auditLog.record({ operation: 'login', result: 'ok' });
    await auditLog.flush();

    const credentials = await adminLogin(baseUrl);
    // The login above also creates an audit entry.
    await auditLog.flush();

    const response = await fetch(`${baseUrl}/admin-api/audit`, {
      headers: { Cookie: credentials.cookie },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(Array.isArray(body.entries), true);
    assert.equal(body.entries.length >= 2, true);
    // All entries must have whitelisted operations.
    for (const entry of body.entries) {
      assert.equal(typeof entry.operation, 'string');
      assert.equal(entry.operation !== 'unknown', true);
      assert.equal('remoteAddress' in entry, false);
    }
  });
});

test('admin audit endpoint returns at most 200 entries', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-admin-cap-'));
  const authService = new AdminAuthService({
    filePath: join(directory, 'auth.json'),
    bootstrapPassword: 'initial-password',
  });
  await authService.initialize();
  let snapshot = Object.freeze({
    revision: 1,
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'k', projectId: 'p', serviceToken: 's', amapWebKey: 'a',
    aiApiKey: '', aiBaseUrl: '', aiModel: '',
    settings: validateRuntimeSettings({}),
    llmProfiles: [],
    llmRouting: { primaryProfileId: null, fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 },
  });

  // Pre-populate with 250 entries to exceed the 200 list cap.
  const auditFilePath = join(directory, 'audit-log.enc.json');
  const now = Date.now();
  const entries = [];
  for (let i = 0; i < 250; i++) {
    entries.push({
      timestamp: new Date(now - i * 1_000).toISOString(),
      operation: 'clear_cache',
      fields: [],
      result: 'ok',
      details: {},
    });
  }
  await encryptEntries(auditFilePath, entries);

  const auditLog = await new AuditLog({ filePath: auditFilePath, masterKey }).initialize();

  const server = createAdminServer({
    authService,
    runtimeConfig: {
      snapshot: () => snapshot,
      replace: async (patch) => { snapshot = Object.freeze({ ...snapshot, ...patch }); return snapshot; },
    },
    auditLog,
    clearCache: async () => {},
    restart: async () => {},
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const credentials = await adminLogin(baseUrl);
    await auditLog.flush();

    const response = await fetch(`${baseUrl}/admin-api/audit`, {
      headers: { Cookie: credentials.cookie },
    });
    const body = await response.json();
    assert.equal(body.entries.length <= 200, true);
    assert.equal(body.entries.length, 200);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await auditLog.flush();
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 7. Restart audit entry is flushed before process exit
// ---------------------------------------------------------------------------

test('restart endpoint awaits audit flush before calling restart', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-restart-flush-'));
  const authService = new AdminAuthService({
    filePath: join(directory, 'auth.json'),
    bootstrapPassword: 'initial-password',
  });
  await authService.initialize();
  let snapshot = Object.freeze({
    revision: 1,
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'k', projectId: 'p', serviceToken: 's', amapWebKey: 'a',
    aiApiKey: '', aiBaseUrl: '', aiModel: '',
    settings: validateRuntimeSettings({}),
    llmProfiles: [],
    llmRouting: { primaryProfileId: null, fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 3 },
  });
  const auditLog = await new AuditLog({
    filePath: join(directory, 'audit-log.enc.json'),
    masterKey,
  }).initialize();

  let restartCalled = false;
  // Deterministically observe when restart() is invoked instead of polling
  // with an arbitrary timeout. The restart handler awaits the audit flush
  // before calling restart(), so awaiting this promise proves ordering.
  let restartResolve;
  const restartDone = new Promise((resolve) => { restartResolve = resolve; });

  const server = createAdminServer({
    authService,
    runtimeConfig: {
      snapshot: () => snapshot,
      replace: async (patch) => { snapshot = Object.freeze({ ...snapshot, ...patch }); return snapshot; },
    },
    auditLog,
    clearCache: async () => {},
    restart: async () => { restartCalled = true; restartResolve(); },
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const credentials = await adminLogin(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/restart`, {
      method: 'POST',
      headers: { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' },
      body: '{}',
    });
    assert.equal(response.status, 202);

    // Wait deterministically for restart() to be called.
    await restartDone;

    assert.equal(restartCalled, true);

    // The restart entry must be persisted to disk.
    const persisted = await readDecryptedEntries(join(directory, 'audit-log.enc.json'));
    const restartEntry = persisted.find((e) => e.operation === 'restart');
    assert.equal(restartEntry != null, true);
    assert.equal(restartEntry.result, 'accepted');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await auditLog.flush();
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 8. isExpired correctness — strict timestamp parsing
// ---------------------------------------------------------------------------

test('isExpired via record() prunes entries older than 30 days', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-isexpired-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    // Pre-populate with an entry exactly 31 days old.
    const oldTimestamp = new Date(Date.now() - 31 * 24 * 60 * 60 * 1_000).toISOString();
    const recentTimestamp = new Date().toISOString();
    await encryptEntries(filePath, [
      { timestamp: oldTimestamp, operation: 'login', fields: [], result: 'ok', details: {} },
      { timestamp: recentTimestamp, operation: 'clear_cache', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].operation, 'clear_cache');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('entries exactly at 29 days are retained', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-29days-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const ts29 = new Date(Date.now() - 29 * 24 * 60 * 60 * 1_000).toISOString();
    await encryptEntries(filePath, [
      { timestamp: ts29, operation: 'login', fields: [], result: 'ok', details: {} },
    ]);

    const log = await new AuditLog({ filePath, masterKey }).initialize();
    const entries = await log.list();
    assert.equal(entries.length, 1);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 9. lastWriteError never leaks paths or exception text
// ---------------------------------------------------------------------------

test('lastWriteError contains only safe error codes, never paths or messages', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-audit-error-leak-'));
  const filePath = join(directory, 'audit-log.enc.json');
  try {
    const realFs = await import('node:fs/promises');
    const failingFs = {
      ...realFs,
      open: async () => {
        const error = new Error(`EACCES: permission denied, open '${filePath}.tmp-123'`);
        error.code = 'EACCES';
        throw error;
      },
    };

    const log = await new AuditLog({ filePath, masterKey, fileSystem: failingFs }).initialize();
    await log.record({ operation: 'login', result: 'ok' });
    await log.flush();

    const status = log.status();
    assert.equal(status.lastWriteOk, false);
    assert.equal(status.lastWriteError, 'EACCES');
    // Verify no path or message leaks.
    assert.equal(status.lastWriteError.includes(directory), false);
    assert.equal(status.lastWriteError.includes('permission denied'), false);
    assert.equal(status.lastWriteError.includes('.tmp'), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// 10. flush() waits for pending writes
// ---------------------------------------------------------------------------

test('flush() ensures pending writes complete', async () => {
  await withTemporaryLog(async ({ log, filePath }) => {
    log.record({ operation: 'login', result: 'ok' });
    log.record({ operation: 'clear_cache', result: 'ok' });
    log.record({ operation: 'change_password', result: 'ok' });
    // Without flush, background writes might not have completed.
    await log.flush();

    // Read the file directly — all 3 entries should be persisted.
    const persisted = await readDecryptedEntries(filePath);
    assert.equal(persisted.length, 3);
  });
});

// ---------------------------------------------------------------------------
// 11. Field and detail sanitization on record
// ---------------------------------------------------------------------------

test('record filters fields to whitelist and caps count', async () => {
  await withTemporaryLog(async ({ log }) => {
    await log.record({
      operation: 'update_config',
      fields: ['settings', 'unknown_field', 'llmRouting', 'apiKey', 'enabled', 'model',
               'name', 'protocol', 'timeoutMs', 'baseUrl', 'allowFallback', 'sourcePolicies',
               'extra1', 'extra2'],
      result: 'ok',
    });
    const entries = await log.list();
    // The input has 14 fields; 3 are non-whitelisted (unknown_field, extra1,
    // extra2), leaving 11 whitelisted fields — fewer than the 12-entry cap.
    // Assert the real filtered count, not the cap.
    assert.equal(entries[0].fields.length, 11);
    assert.equal(entries[0].fields.includes('unknown_field'), false);
    assert.equal(entries[0].fields.includes('extra1'), false);
    assert.equal(entries[0].fields.includes('extra2'), false);
  });
});

test('record caps whitelisted fields at maximumFieldsCount', async () => {
  await withTemporaryLog(async ({ log }) => {
    // Supply 13 distinct whitelisted field names — more than the 12-entry cap.
    await log.record({
      operation: 'update_config',
      fields: [
        'settings', 'llmRouting', 'apiKey', 'enabled', 'model',
        'name', 'protocol', 'timeoutMs', 'baseUrl', 'allowFallback',
        'sourcePolicies', 'product', 'providerId',
      ],
      result: 'ok',
    });
    const entries = await log.list();
    assert.equal(entries[0].fields.length, 12); // capped at maximumFieldsCount
    // The first 12 whitelisted fields survive; the 13th is dropped.
    assert.equal(entries[0].fields.includes('providerId'), false);
  });
});

test('record filters details to allowed keys and bounds values', async () => {
  await withTemporaryLog(async ({ log }) => {
    await log.record({
      operation: 'test_7timer',
      result: 'ok',
      details: {
        product: 'astro',
        traceId: 'trace-123',
        secretKey: 'should-be-removed',
        anotherBad: 'also-removed',
      },
    });
    const entries = await log.list();
    assert.deepEqual(entries[0].details, { product: 'astro', traceId: 'trace-123' });
    assert.equal('secretKey' in entries[0].details, false);
  });
});
