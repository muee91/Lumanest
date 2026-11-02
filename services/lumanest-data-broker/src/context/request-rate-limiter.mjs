import { createClient } from 'redis';

// A fixed window lets a client send `limit` requests just before the boundary
// and `limit` more just after it, so the real burst is 2x the declared limit.
// A token bucket refills continuously instead: capacity is still `limit`, but
// the second half of a burst has to be earned back at `limit / windowMs`.
//
// Both implementations keep exactly two numbers per key (tokens, updatedAt),
// so the fallback limiter's memory stays bounded no matter how long a source
// stays busy.
const consumeScript = `local capacity = tonumber(ARGV[1])
local windowMs = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local state = redis.call('HMGET', KEYS[1], 'tokens', 'updatedAt')
local tokens = tonumber(state[1])
local updatedAt = tonumber(state[2])
if tokens == nil or updatedAt == nil then
  tokens = capacity
  updatedAt = now
end
if now > updatedAt then
  tokens = math.min(capacity, tokens + (now - updatedAt) * capacity / windowMs)
  updatedAt = now
end
local allowed = 0
if tokens >= 1 then
  tokens = tokens - 1
  allowed = 1
end
redis.call('HSET', KEYS[1], 'tokens', tostring(tokens), 'updatedAt', tostring(updatedAt))
redis.call('PEXPIRE', KEYS[1], math.ceil(windowMs * 2))
local retryAfter = 0
if allowed == 0 then retryAfter = math.ceil((1 - tokens) * windowMs / capacity) end
return {allowed, retryAfter`;

function bucketKey(key) {
  return `rate:v2:${key}`;
}

export class MemoryRequestRateLimiter {
  #buckets = new Map();

  constructor({ maximumKeys = 10_000 } = {}) {
    this.maximumKeys = maximumKeys;
  }

  get bucketCount() {
    return this.#buckets.size;
  }

  // Source addresses are attacker-controlled, so the fallback limiter must not
  // grow without bound. A bucket that has been idle for a full window is
  // indistinguishable from a fresh one, so it is dropped first; if that is not
  // enough, the least recently used bucket goes.
  #makeRoom(timestamp, windowMs) {
    for (const [key, bucket] of this.#buckets) {
      if (bucket.updatedAt + windowMs <= timestamp) this.#buckets.delete(key);
    }
    if (this.#buckets.size < this.maximumKeys) return;
    let oldestKey = null;
    let oldestUpdatedAt = Infinity;
    for (const [key, bucket] of this.#buckets) {
      if (bucket.updatedAt < oldestUpdatedAt) {
        oldestUpdatedAt = bucket.updatedAt;
        oldestKey = key;
      }
    }
    if (oldestKey != null) this.#buckets.delete(oldestKey);
  }

  async consume({ key, limit, windowMs, now = new Date() }) {
    const timestamp = now.getTime();
    if (this.#buckets.size >= this.maximumKeys) this.#makeRoom(timestamp, windowMs);
    const current = this.#buckets.get(key);
    const bucket = current != null
      ? current
      : { tokens: limit, updatedAt: timestamp };
    if (timestamp > bucket.updatedAt) {
      bucket.tokens = Math.min(
        limit,
        bucket.tokens + ((timestamp - bucket.updatedAt) * limit) / windowMs,
      );
      bucket.updatedAt = timestamp;
    }
    let allowed = false;
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      allowed = true;
    }
    this.#buckets.set(key, bucket);
    const retryAfterSeconds = allowed
      ? Math.max(1, Math.ceil(windowMs / 1_000))
      : Math.max(1, Math.ceil(((1 - bucket.tokens) * windowMs) / limit / 1_000));
    return { allowed, retryAfterSeconds };
  }
}

export class RedisRequestRateLimiter {
  constructor(client) {
    this.client = client;
  }

  static async connect(url) {
    if (!url) return null;
    const client = createClient({ url });
    client.on('error', () => {});
    try {
      await client.connect();
      return new RedisRequestRateLimiter(client);
    } catch {
      await client.close().catch(() => {});
      return null;
    }
  }

  async consume({ key, limit, windowMs, now = new Date() }) {
    try {
      const [allowed, retryAfterMilliseconds] = await this.client.eval(
        consumeScript,
        {
          keys: [bucketKey(key)],
          arguments: [
            String(limit),
            String(windowMs),
            String(now.getTime()),
          ],
        },
      );
      return {
        allowed: allowed === 1,
        retryAfterSeconds: Math.max(
          1,
          Math.ceil(
            (retryAfterMilliseconds > 0 ? retryAfterMilliseconds : windowMs) /
              1_000,
          ),
        ),
      };
    } catch {
      throw new Error('rate_limiter_unavailable');
    }
  }
}

export class FallbackRequestRateLimiter {
  constructor(primary, fallback = new MemoryRequestRateLimiter()) {
    this.primary = primary;
    this.fallback = fallback;
  }

  async consume(input) {
    try {
      return await this.primary.consume(input);
    } catch {
      return this.fallback.consume(input);
    }
  }
}
