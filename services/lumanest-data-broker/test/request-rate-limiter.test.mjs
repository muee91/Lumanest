import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FallbackRequestRateLimiter,
  MemoryRequestRateLimiter,
  RedisRequestRateLimiter,
} from '../src/context/request-rate-limiter.mjs';

test('memory limiter enforces the limit within one window and reports retry time', async () => {
  const limiter = new MemoryRequestRateLimiter();
  const now = new Date('2026-07-16T00:00:00.000Z');

  assert.equal((await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now })).allowed, true);
  assert.equal((await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now })).allowed, true);
  const limited = await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now });
  assert.equal(limited.allowed, false);
  // Two tokens refill over one window, so the next single request is earned
  // back in half a window instead of the whole window a fixed counter needed.
  assert.equal(limited.retryAfterSeconds, 30);
  assert.equal(
    (await limiter.consume({
      key: 'narrative:source',
      limit: 2,
      windowMs: 60_000,
      now: new Date('2026-07-16T00:00:30.000Z'),
    })).allowed,
    true,
  );
});

test('a window boundary no longer allows a double burst', async () => {
  // The fixed-window implementation let a client spend the whole budget just
  // before a boundary and the whole budget again just after it, so the real
  // peak was 2x the declared limit. The token bucket must refuse the second
  // half of that burst.
  const limiter = new MemoryRequestRateLimiter();
  const windowMs = 60_000;
  const limit = 10;
  const start = new Date('2026-07-16T00:00:59.000Z').getTime();
  for (let index = 0; index < limit; index += 1) {
    assert.equal(
      (await limiter.consume({ key: 'burst', limit, windowMs, now: new Date(start) })).allowed,
      true,
    );
  }
  const justAfter = new Date(start + 1_000);
  assert.equal(
    (await limiter.consume({ key: 'burst', limit, windowMs, now: justAfter })).allowed,
    false,
    'one second after the boundary the bucket must still be empty',
  );
});

test('Redis limiter keeps the whole refill in one atomic script', async () => {
  const calls = [];
  const client = {
    async eval(script, options) {
      calls.push([script, options]);
      return [1, 0];
    },
  };
  const now = new Date('2026-07-16T00:00:12.000Z');
  const result = await new RedisRequestRateLimiter(client).consume({
    key: 'context:hashed-source',
    limit: 30,
    windowMs: 60_000,
    now,
  });

  assert.equal(calls.length, 1);
  const [script, options] = calls[0];
  // Read, refill, decrement and expiry must be one step: a crash between two
  // round trips would otherwise leave a counter that never resets.
  assert.match(script, /HMGET/);
  assert.match(script, /HSET/);
  assert.match(script, /PEXPIRE/);
  assert.deepEqual(options, {
    keys: ['rate:v2:context:hashed-source'],
    arguments: ['30', '60000', String(now.getTime())],
  });
  assert.deepEqual(result, { allowed: true, retryAfterSeconds: 60 });
});

test('memory limiter evicts buckets instead of growing without bound', async () => {
  const limiter = new MemoryRequestRateLimiter({ maximumKeys: 3 });
  const now = new Date('2026-07-16T00:00:00.000Z');
  for (const key of ['a', 'b', 'c', 'd']) {
    await limiter.consume({ key, limit: 5, windowMs: 60_000, now });
  }
  assert.equal(limiter.bucketCount, 3);
  // The least recently used bucket was evicted, so it starts again with a full
  // allowance. A surviving bucket would still hold only the four tokens left
  // after the loop above.
  let allowed = 0;
  while ((await limiter.consume({ key: 'a', limit: 5, windowMs: 60_000, now })).allowed) {
    allowed += 1;
  }
  assert.equal(allowed, 5);
});

test('memory limiter drops buckets that have been idle for a full window', async () => {
  const limiter = new MemoryRequestRateLimiter({ maximumKeys: 2 });
  await limiter.consume({
    key: 'old', limit: 5, windowMs: 1_000, now: new Date('2026-07-16T00:00:00.000Z'),
  });
  await limiter.consume({
    key: 'new', limit: 5, windowMs: 60_000, now: new Date('2026-07-16T00:00:30.000Z'),
  });
  await limiter.consume({
    key: 'newer', limit: 5, windowMs: 60_000, now: new Date('2026-07-16T00:00:31.000Z'),
  });
  assert.equal(limiter.bucketCount, 2);
});

test('fallback limiter protects requests when Redis is unavailable', async () => {
  const limiter = new FallbackRequestRateLimiter({
    async consume() {
      throw new Error('redis unavailable');
    },
  });
  const result = await limiter.consume({
    key: 'weather:hashed-source',
    limit: 1,
    windowMs: 60_000,
    now: new Date('2026-07-16T00:00:00.000Z'),
  });

  assert.equal(result.allowed, true);
  assert.equal(
    (await limiter.consume({
      key: 'weather:hashed-source',
      limit: 1,
      windowMs: 60_000,
      now: new Date('2026-07-16T00:00:00.000Z'),
    })).allowed,
    false,
  );
});
