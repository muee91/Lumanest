import { createClient } from 'redis';

const key = 'seven-timer:diagnostics:v1';

function clone(value) {
  return value == null ? null : structuredClone(value);
}

export class MemorySevenTimerDiagnosticsStore {
  constructor() { this.value = null; }
  async load() { return clone(this.value); }
  async save(value) { this.value = clone(value); }
  status() { return { mode: 'memory', available: true, durable: false }; }
}

export class RedisSevenTimerDiagnosticsStore {
  constructor(client) { this.client = client; }

  static async connect(url) {
    if (!url) return null;
    const client = createClient({ url });
    client.on('error', () => {});
    try {
      await client.connect();
      return new RedisSevenTimerDiagnosticsStore(client);
    } catch {
      await client.close().catch(() => {});
      return null;
    }
  }

  async load() {
    try {
      const raw = await this.client.get(key);
      return raw == null ? null : JSON.parse(raw);
    } catch {
      return null;
    }
  }

  async save(value) {
    await this.client.set(key, JSON.stringify(value), { EX: 7 * 24 * 60 * 60 });
  }

  status() { return { mode: 'redis', available: this.client.isReady, durable: true }; }
}
