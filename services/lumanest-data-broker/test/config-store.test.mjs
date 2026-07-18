import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { EncryptedConfigStore } from '../src/admin/config-store.mjs';

const masterKey = Buffer.alloc(32, 7).toString('base64');

async function withTemporaryStore(run, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-config-store-'));
  const filePath = join(directory, 'config.enc.json');
  try {
    const store = new EncryptedConfigStore({ filePath, masterKey, ...options });
    await run({ store, filePath, directory });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

test('requires a base64 encoded 32-byte master key', () => {
  assert.throws(
    () => new EncryptedConfigStore({ filePath: '/tmp/config', masterKey: 'not-base64' }),
    /32-byte base64/,
  );
  assert.throws(
    () => new EncryptedConfigStore({
      filePath: '/tmp/config',
      masterKey: Buffer.alloc(31).toString('base64'),
    }),
    /32-byte base64/,
  );
});

test('persists no sensitive plaintext and restores values with the same key', async () => {
  await withTemporaryStore(async ({ store, filePath }) => {
    const value = {
      serviceToken: 'sk-secret-1234',
      amapWebKey: 'amap-secret-5678',
      settings: { aiEnabled: true },
    };
    await store.write(value);

    const persisted = await readFile(filePath, 'utf8');
    assert.equal(persisted.includes('sk-secret-1234'), false);
    assert.equal(persisted.includes('amap-secret-5678'), false);
    assert.deepEqual(await store.read(), value);

    const restarted = new EncryptedConfigStore({ filePath, masterKey });
    assert.deepEqual(await restarted.read(), value);
  });
});

test('rejects a corrupted authentication tag', async () => {
  await withTemporaryStore(async ({ store, filePath }) => {
    await store.write({ serviceToken: 'sk-secret-1234' });
    const document = JSON.parse(await readFile(filePath, 'utf8'));
    document.authenticationTag = Buffer.alloc(16, 9).toString('base64');
    await import('node:fs/promises').then(({ writeFile }) =>
      writeFile(filePath, JSON.stringify(document), { mode: 0o600 }));

    await assert.rejects(() => store.read(), /decrypt encrypted configuration/);
  });
});

test('writes through a temporary file and atomically renames it', async () => {
  const operations = [];
  const fileSystem = await import('node:fs/promises');
  await withTemporaryStore(async ({ store, filePath }) => {
    await store.write({ serviceToken: 'first' });
    assert.equal(operations.length, 1);
    assert.match(operations[0].from, /\.tmp-/);
    assert.equal(operations[0].to, filePath);
  }, {
    fileSystem: {
      ...fileSystem,
      rename: async (from, to) => {
        operations.push({ from, to });
        await fileSystem.rename(from, to);
      },
    },
  });
});

test('a failed rename leaves the previous configuration readable', async () => {
  const fileSystem = await import('node:fs/promises');
  let failRename = false;
  await withTemporaryStore(async ({ store }) => {
    await store.write({ serviceToken: 'first' });
    failRename = true;
    await assert.rejects(() => store.write({ serviceToken: 'second' }), /simulated rename failure/);
    assert.deepEqual(await store.read(), { serviceToken: 'first' });
  }, {
    fileSystem: {
      ...fileSystem,
      rename: async (from, to) => {
        if (failRename) throw new Error('simulated rename failure');
        await fileSystem.rename(from, to);
      },
    },
  });
});

test('serializes concurrent saves into one valid final document', async () => {
  await withTemporaryStore(async ({ store }) => {
    await Promise.all([
      store.write({ revision: 1, serviceToken: 'first' }),
      store.write({ revision: 2, serviceToken: 'second' }),
    ]);
    assert.deepEqual(await store.read(), { revision: 2, serviceToken: 'second' });
  });
});

test('masked output reports only configuration state and last four characters', async () => {
  await withTemporaryStore(async ({ store }) => {
    assert.deepEqual(store.masked({
      serviceToken: 'sk-secret-1234',
      amapWebKey: '',
      aiModel: 'qwen-plus',
    }), {
      serviceToken: { configured: true, lastFour: '1234' },
      amapWebKey: { configured: false, lastFour: null },
      aiModel: 'qwen-plus',
    });
  });
});
