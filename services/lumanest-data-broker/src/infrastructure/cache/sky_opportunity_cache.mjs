import { createClient } from 'redis';

const prefix = 'sky-opportunity:v1:';
const cityPrefix = 'sky-opportunity:city:v1:';

function cacheResult(entry, now) {
  if (entry == null || typeof entry !== 'object') return { status: 'miss', entry: null };
  const fetchedAt = Date.parse(entry.fetchedAt);
  const freshUntil = Date.parse(entry.freshUntil);
  const staleUntil = Date.parse(entry.staleUntil);
  if (![fetchedAt, freshUntil, staleUntil].every(Number.isFinite) || now.getTime() > staleUntil) {
    return { status: 'miss', entry: null };
  }
  return { status: now.getTime() <= freshUntil ? 'hit' : 'stale', entry: structuredClone(entry) };
}

function cityCacheResult(entry, now) {
  if (entry == null || typeof entry !== 'object') return { status: 'miss', entry: null };
  const expiresAt = Date.parse(entry.expiresAt);
  if (!Number.isFinite(expiresAt) || now.getTime() > expiresAt ||
      typeof entry.requestedCity !== 'string' || !Array.isArray(entry.candidates)) {
    return { status: 'miss', entry: null };
  }
  return {
    status: 'hit',
    entry: {
      requestedCity: entry.requestedCity,
      candidates: [...entry.candidates],
    },
  };
}

export class MemorySkyOpportunityCache {
  constructor() {
    this.entries = new Map();
    this.cityEntries = new Map();
  }

  async get(key, now = new Date()) {
    const result = cacheResult(this.entries.get(key), now);
    if (result.status === 'miss') this.entries.delete(key);
    return result;
  }

  async set(key, modelResult, { fetchedAt, freshTtlSeconds, staleTtlSeconds }) {
    const timestamp = fetchedAt.getTime();
    const entry = {
      modelResult: structuredClone(modelResult),
      fetchedAt: fetchedAt.toISOString(),
      freshUntil: new Date(timestamp + freshTtlSeconds * 1_000).toISOString(),
      staleUntil: new Date(timestamp + staleTtlSeconds * 1_000).toISOString(),
    };
    this.entries.set(key, entry);
  }

  async getCityCandidates(key, now = new Date()) {
    const result = cityCacheResult(this.cityEntries.get(key), now);
    if (result.status === 'miss') this.cityEntries.delete(key);
    return result;
  }

  async setCityCandidates(key, location, { now = new Date(), ttlSeconds }) {
    this.cityEntries.set(key, {
      requestedCity: location.requestedCity,
      candidates: [...location.candidates],
      expiresAt: new Date(now.getTime() + ttlSeconds * 1_000).toISOString(),
    });
  }

  async clear() {
    this.entries.clear();
    this.cityEntries.clear();
  }
}

export class RedisSkyOpportunityCache {
  constructor(client) {
    this.client = client;
  }

  static async connect(url) {
    if (!url) return null;
    const client = createClient({ url });
    client.on('error', () => {});
    try {
      await client.connect();
      return new RedisSkyOpportunityCache(client);
    } catch {
      await client.close().catch(() => {});
      return null;
    }
  }

  async get(key, now = new Date()) {
    try {
      const raw = await this.client.get(`${prefix}${key}`);
      return cacheResult(raw == null ? null : JSON.parse(raw), now);
    } catch {
      return { status: 'miss', entry: null };
    }
  }

  async set(key, modelResult, { fetchedAt, freshTtlSeconds, staleTtlSeconds }) {
    const timestamp = fetchedAt.getTime();
    const entry = {
      modelResult,
      fetchedAt: fetchedAt.toISOString(),
      freshUntil: new Date(timestamp + freshTtlSeconds * 1_000).toISOString(),
      staleUntil: new Date(timestamp + staleTtlSeconds * 1_000).toISOString(),
    };
    try {
      await this.client.set(`${prefix}${key}`, JSON.stringify(entry), { EX: staleTtlSeconds });
    } catch {
      // Sky opportunity data is optional and must remain usable without Redis.
    }
  }

  async getCityCandidates(key, now = new Date()) {
    try {
      const raw = await this.client.get(`${cityPrefix}${key}`);
      return cityCacheResult(raw == null ? null : JSON.parse(raw), now);
    } catch {
      return { status: 'miss', entry: null };
    }
  }

  async setCityCandidates(key, location, { now = new Date(), ttlSeconds }) {
    const entry = {
      requestedCity: location.requestedCity,
      candidates: [...location.candidates],
      expiresAt: new Date(now.getTime() + ttlSeconds * 1_000).toISOString(),
    };
    try {
      await this.client.set(`${cityPrefix}${key}`, JSON.stringify(entry), { EX: ttlSeconds });
    } catch {
      // City resolution is creative context and safely falls back to AMap.
    }
  }

  async clear() {
    const keys = [];
    for (const pattern of [`${prefix}*`, `${cityPrefix}*`]) {
      for await (const key of this.client.scanIterator({ MATCH: pattern, COUNT: 200 })) {
        keys.push(key);
      }
    }
    if (keys.length > 0) await this.client.del(keys);
  }
}
