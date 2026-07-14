import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const scripts = [
  new URL('../scripts/nas-deploy.sh', import.meta.url),
  new URL('../scripts/nas-rollback.sh', import.meta.url),
];

test('NAS release scripts are POSIX-valid and never require host root volume access', async () => {
  for (const script of scripts) {
    const path = fileURLToPath(script);
    const syntax = spawnSync('sh', ['-n', path], { encoding: 'utf8' });
    assert.equal(syntax.status, 0, syntax.stderr);
    const source = await readFile(path, 'utf8');
    assert.doesNotMatch(source, /Run this script with sudo|Mountpoint|mountpoint=/);
    assert.match(source, /docker info/);
    assert.match(source, /--network none --read-only --cap-drop ALL/);
    assert.match(source, /--security-opt no-new-privileges/);
  }
});

test('rollback remains explicitly confirmed before destructive volume restore', async () => {
  const source = await readFile(scripts[1], 'utf8');
  assert.match(source, /CONFIRM_ROLLBACK/);
  assert.match(source, /Unsafe Docker volume name/);
  assert.match(source, /find \/target .* rm -rf/);
});
