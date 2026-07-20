import {
  openAICompatibleRequest,
  openAICompatibleText,
} from './openai-compatible.mjs';
import { anthropicRequest, anthropicText } from './anthropic.mjs';
import { geminiRequest, geminiText } from './gemini.mjs';

const maximumResponseBytes = 64 * 1024;

const adapters = new Map([
  ['openai_compatible', { request: openAICompatibleRequest, text: openAICompatibleText }],
  ['anthropic_messages', { request: anthropicRequest, text: anthropicText }],
  ['google_generate_content', { request: geminiRequest, text: geminiText }],
]);

function responseError(status) {
  if (status === 401 || status === 403) return 'authentication_failed';
  if (status === 404) return 'model_not_found';
  if (status === 429) return 'rate_limited';
  if (status >= 400 && status < 500) return 'request_rejected';
  return 'upstream_unavailable';
}

function exceedsDeclaredLimit(response) {
  const declared = Number.parseInt(response.headers?.get?.('content-length') ?? '', 10);
  return Number.isFinite(declared) && declared > maximumResponseBytes;
}

function boundedBody(body) {
  try {
    return Buffer.byteLength(JSON.stringify(body), 'utf8') <= maximumResponseBytes;
  } catch {
    return false;
  }
}

export async function requestNarrative({ profile, prompt, fetcher = fetch }) {
  const adapter = adapters.get(profile.protocol);
  if (adapter == null) return { ok: false, error: 'request_rejected' };
  const { url, options } = adapter.request(profile, prompt);
  let response;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: 'error',
      signal: AbortSignal.timeout(profile.timeoutMs),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return { ok: false, error: timeout ? 'timeout' : 'upstream_unavailable' };
  }
  if (!response.ok) return { ok: false, error: responseError(response.status) };
  if (exceedsDeclaredLimit(response)) return { ok: false, error: 'invalid_response' };
  try {
    const body = await response.json();
    if (!boundedBody(body)) return { ok: false, error: 'invalid_response' };
    const text = adapter.text(body);
    return text == null || Buffer.byteLength(text, 'utf8') > 8 * 1024
      ? { ok: false, error: 'invalid_response' }
      : { ok: true, text };
  } catch {
    return { ok: false, error: 'invalid_response' };
  }
}
