import { createClient } from 'redis';

const prefix = 'seven-timer:v1:';

function result(entry, now) {
  if (entry == null || typeof entry !== 'object') return { status: 'miss', entry: null };
  const freshUntil = Date.parse(entry.freshUntil);
  const staleUntil = Date.parse(entry.staleUntil);
  if (!Number.isFinite(freshUntil) || !Number.isFinite(staleUntil) || now.getTime() > staleUntil) {
    return { status: 'miss', entry: null };
  }
  return {
    status: now.getTime() <= freshUntil ? 'hit' : 'stale',
    entry: structuredClone(entry),
  };
}

function entry(value, { now, freshTtlSeconds, staleTtlSeconds }) {
  return {
    value: structuredClone(value),
    freshUntil: new Date(now.getTime() + freshTtlSeconds * 1_000).toISOString(),
    staleUntil: new Date(now.getTime() + staleTtlSeconds * 1_000).toISOString(),
  };
}

export class MemorySevenTimerCache {
  constructor() {
    this.entries = new Map();
  }

  async get(key, now = new Date()) {
    const value = result(this.entries.get(key), now);
    if (value.status === 'miss') this.entries.delete(key);
    return value;
  }

  async set(key, value, options) {
    this.entries.set(key, entry(value, options));
  }

  async clear() { this.entries.clear(); }

  status() { return { mode: 'memory', available: true, durable: false }; }
}

export class RedisSevenTimerCache {
  constructor(client) {
    this.client = client;
  }

  static async connect(url) {
    if (!url) return null;
    const client = createClient({ url });
    client.on('error', () => {});
    try {
      await client.connect();
      return new RedisSevenTimerCache(client);
    } catch {
      await client.close().catch(() => {});
      return null;
    }
  }

  async get(key, now = new Date()) {
    try {
      const raw = await this.client.get(`${prefix}${key}`);
      return result(raw == null ? null : JSON.parse(raw), now);
    } catch {
      return { status: 'miss', entry: null };
    }
  }

  async set(key, value, options) {
    try {
      await this.client.set(
        `${prefix}${key}`,
        JSON.stringify(entry(value, options)),
        { EX: options.staleTtlSeconds },
      );
    } catch {
      // 7Timer is optional. Redis loss must not fail the provider request.
    }
  }

  async clear() {
    const keys = [];
    for await (const key of this.client.scanIterator({ MATCH: `${prefix}*`, COUNT: 200 })) {
      keys.push(key);
    }
    if (keys.length > 0) await this.client.del(keys);
  }

  status() { return { mode: 'redis', available: this.client.isReady, durable: true }; }
}
