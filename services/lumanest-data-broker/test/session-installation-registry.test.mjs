import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const ownerSecret = 'owner-secret-abcdefghijklmnopqrstuvwxyz-0123456789';

import { SessionInstallationRegistry } from '../src/session/installation-registry.mjs';

async function withTemporaryRegistry(run, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-session-registry-'));
  const filePath = join(directory, 'session-installations.json');
  try {
    const registry = await new SessionInstallationRegistry({ filePath, ...options }).initialize();
    await run({ registry, filePath, directory });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

test('validates constructor limits', () => {
  assert.throws(
    () => new SessionInstallationRegistry({ maximumIssuances: 0 }),
    /maximumIssuances/,
  );
  assert.throws(
    () => new SessionInstallationRegistry({ windowMilliseconds: 0 }),
    /windowMilliseconds/,
  );
});

test('caps issuance per installation over a rolling window', async () => {
  let clock = new Date('2026-11-01T00:00:00Z');
  await withTemporaryRegistry(async ({ registry }) => {
    const first = await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    assert.deepEqual(first, { allowed: true });
    const second = await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    assert.deepEqual(second, { allowed: true });

    const limited = await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    assert.equal(limited.allowed, false);
    assert.equal(limited.status, 429);
    // Retry-After points at when the oldest issuance leaves the window.
    assert.equal(limited.retryAfterSeconds, 3_600);

    // A different identifier has its own bucket.
    const other = await registry.recordIssuance({ ownerSecret, installationId: 'zyxwvutsrqponmlkjihgfedcba' });
    assert.deepEqual(other, { allowed: true });

    // Once the oldest issuance leaves the window, issuance is allowed again.
    clock = new Date('2026-11-01T01:00:01Z');
    const recovered = await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    assert.deepEqual(recovered, { allowed: true });
  }, {
    maximumIssuances: 2,
    windowMilliseconds: 60 * 60 * 1_000,
    now: () => clock,
  });
});

test('revocation blocks issuance and survives restarts', async () => {
  await withTemporaryRegistry(async ({ registry, filePath }) => {
    await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    await registry.setRevoked('abcdefghijklmnopqrstuvwx', true);
    assert.equal(registry.isRevoked('abcdefghijklmnopqrstuvwx'), true);
    const refused = await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    assert.deepEqual(refused, { allowed: false, status: 403 });

    const restarted = await new SessionInstallationRegistry({ filePath }).initialize();
    assert.equal(restarted.isRevoked('abcdefghijklmnopqrstuvwx'), true);
    const stillRefused = await restarted.recordIssuance({
      ownerSecret,
      installationId: 'abcdefghijklmnopqrstuvwx',
    });
    assert.deepEqual(stillRefused, { allowed: false, status: 403 });

    await restarted.setRevoked('abcdefghijklmnopqrstuvwx', false);
    assert.equal(restarted.isRevoked('abcdefghijklmnopqrstuvwx'), false);
    const restored = await restarted.recordIssuance({
      ownerSecret,
      installationId: 'abcdefghijklmnopqrstuvwx',
    });
    assert.deepEqual(restored, { allowed: true });
  });
});

test('binds an installation to its first owner secret and persists the binding', async () => {
  await withTemporaryRegistry(async ({ registry, filePath }) => {
    const installationId = 'abcdefghijklmnopqrstuvwx';
    const first = await registry.recordIssuance({
      installationId,
      ownerSecret,
      includeBindingHash: true,
    });
    assert.equal(first.allowed, true);
    assert.match(first.bindingHash, /^[a-f0-9]{64}$/);
    assert.equal(registry.describe(installationId).bound, true);

    const refused = await registry.recordIssuance({
      installationId,
      ownerSecret: 'owner-secret-zyxwvutsrqponmlkjihgfedcba-9876543210',
    });
    assert.deepEqual(refused, { allowed: false, status: 403, reason: 'identity_mismatch' });

    const restarted = await new SessionInstallationRegistry({ filePath }).initialize();
    assert.equal(restarted.describe(installationId).bound, true);
    const renewed = await restarted.recordIssuance({
      installationId,
      ownerSecret,
      includeBindingHash: true,
    });
    assert.deepEqual(renewed, { allowed: true, bindingHash: first.bindingHash });
    assert.equal(restarted.describe(installationId).ownerSecretHash, undefined);
  });
});

test('prunes stale records on save but keeps revoked ones', async () => {
  let clock = new Date('2026-11-01T00:00:00Z');
  await withTemporaryRegistry(async ({ filePath }) => {
    const first = await new SessionInstallationRegistry({
      filePath,
      now: () => clock,
      retentionMilliseconds: 60 * 60 * 1_000,
      windowMilliseconds: 30 * 60 * 1_000,
    }).initialize();
    await first.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    await first.setRevoked('zyxwvutsrqponmlkjihgfedcba', true);

    clock = new Date('2026-11-01T03:00:00Z');
    const restarted = await new SessionInstallationRegistry({
      filePath,
      now: () => clock,
      retentionMilliseconds: 60 * 60 * 1_000,
      windowMilliseconds: 30 * 60 * 1_000,
    }).initialize();
    assert.equal(restarted.isRevoked('zyxwvutsrqponmlkjihgfedcba'), true);

    // A fresh issuance triggers a save, which prunes the stale inactive record
    // but must never drop the revoked one.
    await restarted.recordIssuance({ ownerSecret, installationId: '0123456789abcdefghijklmn' });
    const document = JSON.parse(await readFile(filePath, 'utf8'));
    assert.equal(document.installations['abcdefghijklmnopqrstuvwx'], undefined);
    assert.equal(document.installations['zyxwvutsrqponmlkjihgfedcba'].revoked, true);
    assert.equal(document.installations['0123456789abcdefghijklmn'] != null, true);
  });
});

test('reports installations ordered by recent issuance', async () => {
  await withTemporaryRegistry(async ({ registry }) => {
    await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' });
    await registry.recordIssuance({ ownerSecret, installationId: 'zyxwvutsrqponmlkjihgfedcba' });
    const installations = registry.list();
    assert.equal(installations.length, 2);
    assert.equal(installations[0].installationId, 'zyxwvutsrqponmlkjihgfedcba');
    assert.equal(installations[0].totalIssuances, 1);
    assert.equal(typeof installations[0].lastIssuedAt, 'string');
    assert.deepEqual(registry.list({ limit: 1 }).length, 1);
  });
});

test('a corrupted document fails initialization instead of dropping revocations', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-session-registry-'));
  const filePath = join(directory, 'session-installations.json');
  try {
    await writeFile(filePath, 'not json', 'utf8');
    await assert.rejects(
      new SessionInstallationRegistry({ filePath }).initialize(),
      /Unable to parse session installation records/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('works without persistence when no file path is configured', async () => {
  const registry = await new SessionInstallationRegistry().initialize();
  assert.deepEqual(
    await registry.recordIssuance({ ownerSecret, installationId: 'abcdefghijklmnopqrstuvwx' }),
    { allowed: true },
  );
  assert.equal(registry.list().length, 1);
});

test('rejects malformed installation identifiers', async () => {
  const registry = await new SessionInstallationRegistry().initialize();
  await assert.rejects(
    registry.recordIssuance({ ownerSecret, installationId: 'short' }),
    /installationId/,
  );
  await assert.rejects(
    registry.setRevoked('also-short', true),
    /installationId/,
  );
  await assert.rejects(
    registry.recordIssuance({
      installationId: 'abcdefghijklmnopqrstuvwx',
      ownerSecret: 'too-short',
    }),
    /installationId/,
  );
});
