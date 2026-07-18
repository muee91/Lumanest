import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { AdminAuthService } from '../src/admin/auth.mjs';
import { runAdminCli } from '../src/admin/admin-cli.mjs';

test('reset-password replaces the hash without printing password or hash', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-admin-cli-'));
  const filePath = join(directory, 'admin-auth.json');
  const auth = new AdminAuthService({ filePath, bootstrapPassword: 'initial-password' });
  await auth.initialize();
  const output = [];
  try {
    const code = await runAdminCli({
      argv: ['reset-password'],
      environment: { LUMANEST_DATA_DIR: directory, LUMANEST_ADMIN_RESET_PASSWORD: 'replacement-password' },
      output: (value) => output.push(value),
    });
    assert.equal(code, 0);
    const restarted = new AdminAuthService({ filePath });
    await restarted.initialize();
    assert.equal(await restarted.verifyPassword('replacement-password'), true);
    assert.equal(output.join(' ').includes('replacement-password'), false);
    assert.equal(output.join(' ').includes('$argon2'), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('reset-password rejects a missing replacement password', async () => {
  await assert.rejects(
    () => runAdminCli({ argv: ['reset-password'], environment: {}, output: () => {} }),
    /LUMANEST_ADMIN_RESET_PASSWORD/,
  );
});
