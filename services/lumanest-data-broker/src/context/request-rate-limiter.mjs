import { createClient } from 'redis';

export class MemoryRequestRateLimiter {
  #buckets = new Map();

  async consume({ key, limit, windowMs, now = new Date() }) {
    const timestamp = now.getTime();
    const current = this.#buckets.get(key);
    const bucket = current != null && current.resetAt > timestamp
      ? current
      : { count: 0, resetAt: timestamp + windowMs };
    bucket.count += 1;
    this.#buckets.set(key, bucket);
    return {
      allowed: bucket.count <= limit,
      retryAfterSeconds: Math.max(1, Math.ceil((bucket.resetAt - timestamp) / 1_000)),
    };
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
    const window = Math.floor(now.getTime() / windowMs);
    const redisKey = `rate:v1:${key}:${window}`;
    try {
      const count = await this.client.incr(redisKey);
      if (count === 1) await this.client.pExpire(redisKey, windowMs);
      const ttl = await this.client.pTTL(redisKey);
      return {
        allowed: count <= limit,
        retryAfterSeconds: Math.max(1, Math.ceil((ttl > 0 ? ttl : windowMs) / 1_000)),
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
