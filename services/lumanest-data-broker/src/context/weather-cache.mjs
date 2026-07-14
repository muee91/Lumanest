import { createClient } from 'redis';

const prefix = 'source:qweather:v1:';

export class MemoryWeatherCache {
  #entries = new Map();

  async get(key) {
    return this.#entries.get(key) ?? null;
  }

  async set(key, value) {
    this.#entries.set(key, structuredClone(value));
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
}
