import { createClient } from 'redis';

const prefix = 'source:qweather:v1:';
const safetyDetailPrefix = 'context:safety:v1:';

export class MemoryWeatherCache {
  #entries = new Map();
  #safetyDetails = new Map();

  async get(key) {
    return this.#entries.get(key) ?? null;
  }

  async set(key, value) {
    this.#entries.set(key, structuredClone(value));
  }

  async setSafetyDetails(contextId, details, expiresAt) {
    this.#safetyDetails.set(contextId, structuredClone({ details, expiresAt }));
  }

  async getSafetyDetail(contextId, eventId, now = new Date()) {
    const entry = this.#safetyDetails.get(contextId);
    if (entry == null || new Date(entry.expiresAt) <= now) {
      this.#safetyDetails.delete(contextId);
      return null;
    }
    return structuredClone(entry.details.find((detail) => detail.eventId === eventId) ?? null);
  }

  async clear() {
    this.#entries.clear();
    this.#safetyDetails.clear();
  }
}

export class RedisWeatherCache {
  constructor(client) {
    this.client = client;
  }

  static async connect(url) {
    if (!url) return null;
    const client = createClient({ url });
    client.on('error', () => {});
    try {
      await client.connect();
      return new RedisWeatherCache(client);
    } catch {
      await client.close().catch(() => {});
      return null;
    }
  }

  async get(key) {
    try {
      const raw = await this.client.get(`${prefix}${key}`);
      if (raw == null) return null;
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
      return null;
    }
  }

  async set(key, value) {
    try {
      await this.client.set(`${prefix}${key}`, JSON.stringify(value), { EX: 7_200 });
      await this.client.set('source:qweather:last-updated', new Date(value.cachedAt).toISOString());
    } catch {
      // A cache outage must not take the authoritative source path down.
    }
  }

  async setSafetyDetails(contextId, details, expiresAt) {
    const ttlSeconds = Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 1_000);
    if (!Number.isFinite(ttlSeconds) || ttlSeconds <= 0) return;
    try {
      await this.client.set(
        `${safetyDetailPrefix}${contextId}`,
        JSON.stringify({ details, expiresAt }),
        { EX: Math.min(ttlSeconds, 900) },
      );
    } catch {
      // Safety detail cache loss falls back to the local deterministic message.
    }
  }

  async getSafetyDetail(contextId, eventId, now = new Date()) {
    try {
      const raw = await this.client.get(`${safetyDetailPrefix}${contextId}`);
      if (raw == null) return null;
      const entry = JSON.parse(raw);
      if (entry == null || typeof entry !== 'object' ||
          !Array.isArray(entry.details) || new Date(entry.expiresAt) <= now) {
        return null;
      }
      const detail = entry.details.find((candidate) => candidate?.eventId === eventId);
      return detail && typeof detail === 'object' ? detail : null;
    } catch {
      return null;
    }
  }

  async clear() {
    const keys = [];
    for (const pattern of [`${prefix}*`, `${safetyDetailPrefix}*`]) {
      for await (const key of this.client.scanIterator({ MATCH: pattern, COUNT: 200 })) {
        keys.push(key);
      }
    }
    keys.push('source:qweather:last-updated');
    if (keys.length > 0) await this.client.del(keys);
  }
}
