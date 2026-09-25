import assert from 'node:assert/strict';
import test from 'node:test';

import { BoundedTtlMap } from '../src/infrastructure/cache/bounded-ttl-map.mjs';

test('the cache stops growing instead of waiting for a key to be revisited', () => {
  const cache = new BoundedTtlMap(3);
  for (const key of ['a', 'b', 'c', 'd']) cache.set(key, { value: key });

  assert.equal(cache.size, 3);
  assert.equal(cache.has('a'), false, 'the least recently touched entry goes first');
  assert.deepEqual(['b', 'c', 'd'].filter((key) => cache.has(key)), ['b', 'c', 'd']);
});

test('reading an entry keeps it alive over one written later', () => {
  const cache = new BoundedTtlMap(2);
  cache.set('old', 1);
  cache.set('new', 2);
  assert.equal(cache.get('old'), 1);
  cache.set('third', 3);

  assert.equal(cache.has('old'), true, 'a just-read entry is not the one to evict');
  assert.equal(cache.has('new'), false);
});

test('misses stay undefined and re-setting refreshes position', () => {
  const cache = new BoundedTtlMap(2);
  assert.equal(cache.get('nothing'), undefined);
  assert.equal(cache.delete('nothing'), false);

  cache.set('a', 1);
  cache.set('b', 2);
  cache.set('a', 3);
  cache.set('c', 4);
  assert.equal(cache.get('a'), 3);
  assert.equal(cache.has('b'), false);
});

test('clear empties it and a bad ceiling is refused at construction', () => {
  const cache = new BoundedTtlMap(4);
  cache.set('a', 1);
  cache.clear();
  assert.equal(cache.size, 0);

  for (const invalid of [0, -1, 1.5, '8', Number.NaN]) {
    assert.throws(() => new BoundedTtlMap(invalid), RangeError, String(invalid));
  }
});
