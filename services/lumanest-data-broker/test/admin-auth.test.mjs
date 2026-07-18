import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { AdminAuthService } from '../src/admin/auth.mjs';

async function withAuth(run, overrides = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-admin-auth-'));
  const filePath = join(directory, 'admin-auth.json');
  try {
    const service = new AdminAuthService({
      filePath,
      bootstrapPassword: 'initial-password',
      ...overrides,
    });
    await service.initialize();
    await run({ service, filePath });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

test('bootstrap password becomes Argon2id hash and plaintext is never persisted', async () => {
  await withAuth(async ({ filePath }) => {
    const persisted = await readFile(filePath, 'utf8');
    assert.equal(persisted.includes('initial-password'), false);
    assert.match(JSON.parse(persisted).passwordHash, /^\$argon2id\$/);
  });
});

test('a later bootstrap value never replaces the persisted administrator password', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-admin-auth-restart-'));
  const filePath = join(directory, 'admin-auth.json');
  try {
    const first = new AdminAuthService({ filePath, bootstrapPassword: 'initial-password' });
    await first.initialize();
    const restarted = new AdminAuthService({ filePath, bootstrapPassword: 'different-password' });
    await restarted.initialize();
    assert.equal(await restarted.verifyPassword('initial-password'), true);
    assert.equal(await restarted.verifyPassword('different-password'), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('verifies correct and incorrect administrator passwords', async () => {
  await withAuth(async ({ service }) => {
    assert.equal(await service.verifyPassword('initial-password'), true);
    assert.equal(await service.verifyPassword('incorrect-password'), false);
  });
});

test('five failures in fifteen minutes lock that IP for fifteen minutes', async () => {
  let milliseconds = Date.parse('2026-07-13T00:00:00Z');
  await withAuth(async ({ service }) => {
    for (let attempt = 1; attempt <= 4; attempt += 1) {
      const result = await service.login({ password: 'wrong', ipAddress: '192.168.1.10' });
      assert.equal(result.reason, 'invalid_credentials');
    }
    const fifth = await service.login({ password: 'wrong', ipAddress: '192.168.1.10' });
    assert.equal(fifth.reason, 'rate_limited');

    const otherIp = await service.login({
      password: 'initial-password',
      ipAddress: '192.168.1.11',
    });
    assert.equal(otherIp.ok, true);

    milliseconds += 15 * 60 * 1_000 + 1;
    const recovered = await service.login({
      password: 'initial-password',
      ipAddress: '192.168.1.10',
    });
    assert.equal(recovered.ok, true);
  }, { now: () => new Date(milliseconds) });
});

test('successful login clears the IP failure counter', async () => {
  await withAuth(async ({ service }) => {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      await service.login({ password: 'wrong', ipAddress: '192.168.1.20' });
    }
    assert.equal((await service.login({
      password: 'initial-password', ipAddress: '192.168.1.20',
    })).ok, true);

    for (let attempt = 0; attempt < 4; attempt += 1) {
      assert.equal((await service.login({
        password: 'wrong', ipAddress: '192.168.1.20',
      })).reason, 'invalid_credentials');
    }
  });
});

test('stores only a SHA-256 session digest and emits a hardened cookie', async () => {
  await withAuth(async ({ service, filePath }) => {
    const result = await service.login({
      password: 'initial-password',
      ipAddress: '192.168.1.30',
    });
    assert.equal(result.ok, true);
    assert.equal(typeof result.sessionToken, 'string');
    assert.equal(typeof result.csrfToken, 'string');
    assert.match(result.cookie, /^lumanest_admin=/);
    assert.match(result.cookie, /HttpOnly/);
    assert.match(result.cookie, /SameSite=Strict/);
    assert.match(result.cookie, /Path=\//);
    assert.match(result.cookie, /Max-Age=2592000/);

    const persisted = await readFile(filePath, 'utf8');
    assert.equal(persisted.includes(result.sessionToken), false);
    assert.equal(persisted.includes(result.csrfToken), false);
    assert.match(JSON.parse(persisted).sessions[0].tokenDigest, /^[a-f0-9]{64}$/);
  });
});

test('session expires after thirty days', async () => {
  let milliseconds = Date.parse('2026-07-13T00:00:00Z');
  await withAuth(async ({ service }) => {
    const login = await service.login({
      password: 'initial-password', ipAddress: '192.168.1.40',
    });
    assert.equal((await service.authenticate({ sessionToken: login.sessionToken })).ok, true);

    milliseconds += 30 * 24 * 60 * 60 * 1_000 + 1;
    assert.equal((await service.authenticate({ sessionToken: login.sessionToken })).ok, false);
  }, { now: () => new Date(milliseconds) });
});

test('rejects CSRF mismatch on state-changing authentication', async () => {
  await withAuth(async ({ service }) => {
    const login = await service.login({
      password: 'initial-password', ipAddress: '192.168.1.50',
    });
    assert.equal((await service.authenticate({
      sessionToken: login.sessionToken,
      csrfToken: 'wrong-csrf',
      requireCsrf: true,
    })).reason, 'csrf_mismatch');
    assert.equal((await service.authenticate({
      sessionToken: login.sessionToken,
      csrfToken: login.csrfToken,
      requireCsrf: true,
    })).ok, true);
  });
});

test('password change invalidates all sessions', async () => {
  await withAuth(async ({ service }) => {
    const first = await service.login({
      password: 'initial-password', ipAddress: '192.168.1.60',
    });
    const second = await service.login({
      password: 'initial-password', ipAddress: '192.168.1.61',
    });

    await service.changePassword('replacement-password');
    assert.equal((await service.authenticate({ sessionToken: first.sessionToken })).ok, false);
    assert.equal((await service.authenticate({ sessionToken: second.sessionToken })).ok, false);
    assert.equal(await service.verifyPassword('replacement-password'), true);
    assert.equal(await service.verifyPassword('initial-password'), false);
  });
});

test('password change verifies the current password before replacing the hash', async () => {
  await withAuth(async ({ service }) => {
    assert.deepEqual(await service.changePassword('replacement-password', {
      currentPassword: 'incorrect-password',
    }), { ok: false, reason: 'invalid_current_password' });
    assert.equal(await service.verifyPassword('initial-password'), true);
    assert.deepEqual(await service.changePassword('replacement-password', {
      currentPassword: 'initial-password',
    }), { ok: true });
    assert.equal(await service.verifyPassword('replacement-password'), true);
  });
});
