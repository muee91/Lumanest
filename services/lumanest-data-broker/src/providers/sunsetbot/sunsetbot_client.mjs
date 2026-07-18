import { randomInt } from 'node:crypto';

const retryStatuses = new Set([408, 425, 429, 500, 502, 503, 504]);
const maximumJsonBytes = 1024 * 1024;

class Semaphore {
  constructor(maximum) {
    this.maximum = maximum;
    this.active = 0;
    this.waiters = [];
  }

  async use(operation) {
    if (this.active >= this.maximum) {
      await new Promise((resolve) => this.waiters.push(resolve));
    }
    this.active += 1;
    try {
      return await operation();
    } finally {
      this.active -= 1;
      this.waiters.shift()?.();
    }
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function boundedJson(response) {
  const contentType = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
  if (!['application/json', 'text/json'].includes(contentType)) {
    return { ok: false, error: 'unexpected_content_type' };
  }
  const declared = Number.parseInt(response.headers.get('content-length') ?? '', 10);
  if (Number.isFinite(declared) && declared > maximumJsonBytes) {
    return { ok: false, error: 'response_too_large' };
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > maximumJsonBytes) return { ok: false, error: 'response_too_large' };
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    return value != null && typeof value === 'object' && !Array.isArray(value)
      ? { ok: true, value }
      : { ok: false, error: 'invalid_json_body' };
  } catch {
    return { ok: false, error: 'invalid_json' };
  }
}

export class SunsetBotClient {
  constructor({ config, fetcher = fetch, queryId = () => randomInt(1, 10_000_000), now = () => new Date() }) {
    this.config = config;
    this.fetcher = fetcher;
    this.queryId = queryId;
    this.now = now;
    this.global = new Semaphore(config.maxGlobalConcurrency);
    this.cities = new Map();
  }

  citySemaphore(city) {
    let value = this.cities.get(city);
    if (value == null) {
      value = new Semaphore(this.config.maxCityConcurrency);
      this.cities.set(city, value);
    }
    return value;
  }

  async fetchCity({ city, eventCode, model }) {
    return this.global.use(() => this.citySemaphore(city).use(async () => {
      let lastError = 'upstream_error';
      for (let attempt = 1; attempt <= this.config.maxAttempts; attempt += 1) {
        const id = this.queryId();
        const url = new URL(this.config.cityPath, this.config.baseUrl);
        url.searchParams.set('query_id', String(id));
        url.searchParams.set('intend', 'select_city');
        url.searchParams.set('query_city', city);
        url.searchParams.set('event_date', 'None');
        url.searchParams.set('event', eventCode);
        url.searchParams.set('times', 'None');
        url.searchParams.set('model', model);
        const started = this.now().getTime();
        try {
          const response = await this.fetcher(url, {
            headers: { Accept: 'application/json, text/json', 'User-Agent': this.config.userAgent },
            redirect: 'error',
            signal: AbortSignal.timeout(this.config.timeoutMs),
          });
          const durationMs = Math.max(0, this.now().getTime() - started);
          if (!response.ok) {
            lastError = response.status === 429 ? 'rate_limited' :
              response.status === 404 ? 'not_found' : 'upstream_error';
            if (attempt < this.config.maxAttempts && retryStatuses.has(response.status)) {
              await delay(this.config.retryDelayMs);
              continue;
            }
            return { ok: false, error: lastError, httpStatus: response.status, durationMs, attempts: attempt };
          }
          const parsed = await boundedJson(response);
          return parsed.ok
            ? { ok: true, body: parsed.value, httpStatus: response.status, durationMs, attempts: attempt }
            : { ok: false, error: parsed.error, httpStatus: response.status, durationMs, attempts: attempt };
        } catch (error) {
          lastError = error?.name === 'TimeoutError' ? 'timeout' : 'upstream_error';
          if (attempt < this.config.maxAttempts) {
            await delay(this.config.retryDelayMs);
            continue;
          }
          return {
            ok: false,
            error: lastError,
            httpStatus: null,
            durationMs: Math.max(0, this.now().getTime() - started),
            attempts: attempt,
          };
        }
      }
      return { ok: false, error: lastError, httpStatus: null, durationMs: 0, attempts: this.config.maxAttempts };
    }));
  }
}
