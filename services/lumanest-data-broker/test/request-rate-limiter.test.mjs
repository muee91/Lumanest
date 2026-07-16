import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FallbackRequestRateLimiter,
  MemoryRequestRateLimiter,
  RedisRequestRateLimiter,
} from '../src/context/request-rate-limiter.mjs';

test('memory limiter enforces one fixed window and reports retry time', async () => {
  const limiter = new MemoryRequestRateLimiter();
  const now = new Date('2026-07-16T00:00:00.000Z');

  assert.equal((await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now })).allowed, true);
  assert.equal((await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now })).allowed, true);
  const limited = await limiter.consume({ key: 'narrative:source', limit: 2, windowMs: 60_000, now });
  assert.equal(limited.allowed, false);
  assert.equal(limited.retryAfterSeconds, 60);
  assert.equal(
    (await limiter.consume({
      key: 'narrative:source',
      limit: 2,
      windowMs: 60_000,
      now: new Date('2026-07-16T00:01:00.000Z'),
    })).allowed,
    true,
  );
});

test('Redis limiter uses an opaque fixed-window key and TTL', async () => {
  const calls = [];
  const client = {
    async incr(key) {
      calls.push(['incr', key]);
      return 1;
    },
    async pExpire(key, milliseconds) {
      calls.push(['pExpire', key, milliseconds]);
    },
    async pTTL(key) {
      calls.push(['pTTL', key]);
      return 45_000;
    },
  };
  const now = new Date('2026-07-16T00:00:12.000Z');
  const window = Math.floor(now.getTime() / 60_000);
  const result = await new RedisRequestRateLimiter(client).consume({
    key: 'context:hashed-source',
    limit: 30,
    windowMs: 60_000,
    now,
  });

  assert.deepEqual(calls, [
    ['incr', `rate:v1:context:hashed-source:${window}`],
    ['pExpire', `rate:v1:context:hashed-source:${window}`, 60_000],
    ['pTTL', `rate:v1:context:hashed-source:${window}`],
  ]);
  assert.deepEqual(result, { allowed: true, retryAfterSeconds: 45 });
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
