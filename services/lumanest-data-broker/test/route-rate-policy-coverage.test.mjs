import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const serverSource = await readFile(new URL('../src/server.mjs', import.meta.url), 'utf8');

const routed = [...serverSource.matchAll(/requestUrl\.pathname === '(\/v1\/[^']+)'/g)]
  .map((match) => match[1]);
const limited = [...serverSource.matchAll(/\{ path: '(\/v1\/[^']+)', limit: (\d+), windowMs: [\d_ *]+, key: '([\w-]+)' \}/g)]
  .map((match) => ({ path: match[1], limit: Number(match[2]), key: match[3] }));

test('every /v1 route declares its own rate budget', () => {
  // An unlisted route used to inherit 60/min silently, which is looser than the
  // heaviest upstream fan-out deserves and produces no signal when it is hit.
  const covered = new Set(limited.map((policy) => policy.path));
  const unlisted = [...new Set(routed)].filter((path) => !covered.has(path));
  assert.deepEqual(unlisted, [], 'add a ratePolicies entry for each route above');
  assert.ok(routed.length >= 20, `expected the route chain to be scanned, got ${routed.length}`);
});

test('rate buckets are unique per key and per path', () => {
  const keys = limited.map((policy) => policy.key);
  assert.equal(new Set(keys).size, keys.length, 'two routes sharing one key share one bucket');
  const paths = limited.map((policy) => policy.path);
  assert.equal(new Set(paths).size, paths.length, 'a route is declared twice');
});

test('upstream-heavy routes are limited tighter than plain reads', () => {
  const byPath = new Map(limited.map((policy) => [policy.path, policy.limit]));
  // Measured cold: /v1/environment/provider-facts fans out to fourteen providers
  // and takes ~9s; /v1/context/snapshot is cached and answers in ~0.2s.
  assert.ok(byPath.get('/v1/environment/provider-facts') < byPath.get('/v1/context/snapshot'));
  assert.ok(byPath.get('/v1/amap/driving') <= 6);
});
