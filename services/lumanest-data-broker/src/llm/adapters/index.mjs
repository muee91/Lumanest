import {
  openAICompatibleRequest,
  openAICompatibleText,
  openAICompatibleStreamRequest,
  openAICompatibleStreamChunk,
  openAICompatibleWithTools,
  openAICompatibleExtractToolCalls,
} from './openai-compatible.mjs';
import {
  anthropicRequest,
  anthropicText,
  anthropicStreamRequest,
  anthropicStreamChunk,
} from './anthropic.mjs';
import {
  geminiRequest,
  geminiText,
  geminiStreamRequest,
  geminiStreamChunk,
} from './gemini.mjs';

const maximumResponseBytes = 64 * 1024;

const adapters = new Map([
  ['openai_compatible', {
    request: openAICompatibleRequest,
    text: openAICompatibleText,
    streamRequest: openAICompatibleStreamRequest,
    streamChunk: openAICompatibleStreamChunk,
    withTools: openAICompatibleWithTools,
    extractToolCalls: openAICompatibleExtractToolCalls,
  }],
  ['anthropic_messages', {
    request: anthropicRequest,
    text: anthropicText,
    streamRequest: anthropicStreamRequest,
    streamChunk: anthropicStreamChunk,
  }],
  ['google_generate_content', {
    request: geminiRequest,
    text: geminiText,
    streamRequest: geminiStreamRequest,
    streamChunk: geminiStreamChunk,
  }],
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

function requestSignal(timeoutMs, signal) {
  const timeout = AbortSignal.timeout(timeoutMs);
  return signal == null ? timeout : AbortSignal.any([signal, timeout]);
}

export async function requestNarrative({ profile, prompt, fetcher = fetch, tools, extraMessages, signal } = {}) {
  const adapter = adapters.get(profile.protocol);
  if (adapter == null) return { ok: false, error: 'request_rejected' };
  // Tools are optional and protocol-opt-in: an adapter that does not expose
  // withTools/extractToolCalls simply cannot run the agent loop, and the
  // caller degrades to a plain chat completion. This keeps the legacy path
  // (no tools) byte-identical to before.
  const usingTools = Array.isArray(tools) && tools.length > 0
    && typeof adapter.withTools === 'function'
    && typeof adapter.extractToolCalls === 'function';
  const { url, options } = usingTools
    ? adapter.withTools(profile, prompt, tools, extraMessages)
    : adapter.request(profile, prompt);
  let response;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: 'error',
      signal: requestSignal(profile.timeoutMs, signal),
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
    // In tool mode the model may legitimately emit only a tool call and no
    // textual content; a null/empty text is then acceptable as long as a
    // tool call is present. Without tools the legacy contract stands: a
    // missing text is an invalid response.
    const hasText = typeof text === 'string' && Buffer.byteLength(text, 'utf8') <= 8 * 1024 && text.length > 0;
    if (!usingTools && !hasText) return { ok: false, error: 'invalid_response' };
    if (!usingTools) return { ok: true, text };
    const toolCalls = adapter.extractToolCalls(body);
    if (!hasText && !(toolCalls && toolCalls.length > 0)) {
      return { ok: false, error: 'invalid_response' };
    }
    return { ok: true, text: hasText ? text : '', toolCalls: toolCalls ?? null };
  } catch {
    return { ok: false, error: 'invalid_response' };
  }
}

// Streams one provider response as a sequence of events:
//   { type: 'token', text }   an output fragment (first one signals generation)
//   { type: 'done' }          the provider finished the stream
//   { type: 'error', error }  a bounded failure reason
// The caller accumulates tokens and is responsible for grounding validation
// before any text is surfaced to a client.
export async function* streamNarrative({ profile, prompt, fetcher = fetch, signal }) {
  const adapter = adapters.get(profile.protocol);
  if (adapter?.streamRequest == null) {
    yield { type: 'error', error: 'request_rejected' };
    return;
  }
  const { url, options } = adapter.streamRequest(profile, prompt);
  let response;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: 'error',
      signal: requestSignal(profile.timeoutMs, signal),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    yield { type: 'error', error: timeout ? 'timeout' : 'upstream_unavailable' };
    return;
  }
  if (!response.ok) {
    yield { type: 'error', error: responseError(response.status) };
    return;
  }
  if (response.body == null) {
    yield { type: 'error', error: 'invalid_response' };
    return;
  }

  let accumulatedBytes = 0;
  let buffer = '';
  const decoder = new TextDecoder();
  const handleLine = (rawLine) => {
    const line = rawLine.trim();
    if (!line.startsWith('data:')) return null;
    const data = line.slice(5).trim();
    if (data === '') return null;
    return adapter.streamChunk(data);
  };

  try {
    for await (const rawChunk of response.body) {
      buffer += decoder.decode(rawChunk, { stream: true });
      let newlineIndex;
      while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);
        const result = handleLine(line);
        if (result == null) continue;
        if (result.done) return;
        if (result.text) {
          accumulatedBytes += Buffer.byteLength(result.text, 'utf8');
          if (accumulatedBytes > 8 * 1024) {
            yield { type: 'error', error: 'invalid_response' };
            return;
          }
          yield { type: 'token', text: result.text };
        }
      }
    }
    const trailing = handleLine(decoder.decode());
    if (trailing?.done) return;
    yield { type: 'done' };
  } catch {
    yield { type: 'error', error: 'upstream_unavailable' };
  }
}
