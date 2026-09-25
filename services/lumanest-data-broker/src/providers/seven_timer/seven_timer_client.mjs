import { apiErrorCodes } from '../../api/error-codes.mjs';

import { randomInt } from 'node:crypto';

const retryStatuses = new Set([408, 425, 429, 500, 502, 503, 504]);
const redirectStatuses = new Set([301, 302, 303, 307, 308]);
const redirectPaths = Object.freeze({
  astro: '/bin/astro.php',
  meteo: '/bin/meteo.php',
  two: '/bin/two.php',
});

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
function safeRedirect(response, originalUrl, product) {
  const allowedPath = redirectPaths[product];
  const location = response.headers.get('location');
  if (allowedPath == null || location == null) return null;
  try {
    const url = new URL(location, originalUrl);
    if (url.protocol !== 'https:' || url.hostname !== 'www.7timer.info' ||
        (url.port !== '' && url.port !== '443') || url.pathname !== allowedPath ||
        url.username !== '' || url.password !== '' || url.hash !== '') return null;
    return url;
  } catch {
    return null;
  }
}

async function boundedJson(response, maximumBytes) {
  const declared = Number.parseInt(response.headers.get('content-length') ?? '', 10);
  if (Number.isFinite(declared) && declared > maximumBytes) {
    return { ok: false, error: apiErrorCodes.responseTooLarge };
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > maximumBytes) return { ok: false, error: apiErrorCodes.responseTooLarge };
  const text = new TextDecoder().decode(bytes).trim();
  const contentType = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase() ?? '';
  const jsonType = contentType === 'application/json' || contentType === 'text/json';
  const compatibleText = contentType === 'text/plain' || contentType === 'text/html';
  if (!jsonType && !(compatibleText && text.startsWith('{'))) {
    return { ok: false, error: apiErrorCodes.unexpectedContentType };
  }
  try {
    const value = JSON.parse(text);
    return value != null && typeof value === 'object' && !Array.isArray(value)
      ? { ok: true, value }
      : { ok: false, error: apiErrorCodes.invalidJsonBody };
  } catch {
    return { ok: false, error: apiErrorCodes.invalidJson };
  }
}

export class SevenTimerClient {
  constructor({ config, fetcher = fetch, sleep = delay, jitter = () => randomInt(0, 201) }) {
    this.config = config;
    this.fetcher = fetcher;
    this.sleep = sleep;
    this.jitter = jitter;
  }

  url({ latitude, longitude, product }) {
    const url = new URL('/bin/api.pl', this.config.baseUrl);
    url.searchParams.set('lon', longitude.toFixed(3));
    url.searchParams.set('lat', latitude.toFixed(3));
    url.searchParams.set('product', product);
    url.searchParams.set('output', 'json');
    return url;
  }

  async request(url) {
    return this.fetcher(url, {
      headers: { Accept: 'application/json, text/json, text/plain', 'User-Agent': this.config.userAgent },
      redirect: 'manual',
      signal: AbortSignal.timeout(this.config.timeoutMs),
    });
  }

  async fetch({ latitude, longitude, product }) {
    let lastError = 'upstream_error';
    for (let attempt = 1; attempt <= this.config.maxAttempts; attempt += 1) {
      const url = this.url({ latitude, longitude, product });
      try {
        let response = await this.request(url);
        if (redirectStatuses.has(response.status)) {
          const redirect = safeRedirect(response, url, product);
          if (redirect == null) {
            return { ok: false, error: apiErrorCodes.redirectRejected, attempts: attempt };
          }
          response = await this.request(redirect);
          if (redirectStatuses.has(response.status)) {
            return { ok: false, error: apiErrorCodes.redirectRejected, attempts: attempt };
          }
        }
        if (!response.ok) {
          lastError = response.status === 429 ? 'rate_limited' : 'upstream_error';
          if (attempt < this.config.maxAttempts && retryStatuses.has(response.status)) {
            await this.sleep(this.config.retryDelayMs + this.jitter());
            continue;
          }
          return { ok: false, error: lastError, httpStatus: response.status, attempts: attempt };
        }
        const parsed = await boundedJson(response, this.config.maximumResponseBytes);
        return parsed.ok
          ? { ok: true, body: parsed.value, attempts: attempt }
          : { ok: false, error: parsed.error, attempts: attempt };
      } catch (error) {
        lastError = error?.name === 'TimeoutError' ? 'timeout' : 'upstream_error';
        if (attempt < this.config.maxAttempts) {
          await this.sleep(this.config.retryDelayMs + this.jitter());
          continue;
        }
        return { ok: false, error: lastError, attempts: attempt };
      }
    }
    return { ok: false, error: lastError, attempts: this.config.maxAttempts };
  }
}
