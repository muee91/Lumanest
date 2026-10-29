// Reasoning models (DeepSeek V4 Flash, OpenAI o-series, …) bill their private
// reasoning against the same completion ceiling as the visible answer. Measured
// against deepseek-v4-flash: a long extraction prompt spends ~3.7k reasoning
// tokens before emitting ~2k characters of JSON. A 2048 ceiling therefore ended
// with `finish_reason: "length"`, empty `content`, and an `invalid_response`
// failure for every call; 4096 was still consumed entirely by reasoning. 8192
// is the smallest ceiling observed to let reasoning finish and leave the visible
// JSON intact. This is an upper bound, not a reservation — cost follows actual
// token usage, so a ceiling large enough to finish is cheaper than a ceiling that
// burns tokens and produces nothing.
const completionTokenCeiling = 8192;

export function openAICompatibleRequest(profile, prompt) {
  const headers = { 'Content-Type': 'application/json' };
  if (profile.apiKey) headers.Authorization = `Bearer ${profile.apiKey}`;
  if (profile.providerId === 'openrouter') headers['X-Title'] = 'LumaNest';
  return {
    url: new URL('chat/completions', `${profile.baseUrl.replace(/\/+$/, '')}/`),
    options: {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: profile.model,
        temperature: 0.3,
        max_tokens: completionTokenCeiling,
        stream: false,
        messages: [
          { role: 'system', content: prompt.system },
          ...(prompt.history ?? []),
          { role: 'user', content: prompt.user },
        ],
      }),
    },
  };
}

export function openAICompatibleText(body) {
  const text = body?.choices?.[0]?.message?.content;
  return typeof text === 'string' && text.length > 0 ? text : null;
}

// Tool-calling variant of openAICompatibleRequest. Two deliberate differences
// from the plain request:
//   1. `response_format: { type: 'json_object' }` is dropped. OpenAI rejects
//      requests that combine JSON mode with `tools`, and even where it is
//      accepted it forces the model to emit JSON only — which suppresses
//      tool_calls. The agent loop instead asks the model (via the system
//      prompt) for JSON in its final answer.
//   2. `tools` and `tool_choice: 'auto'` are added so the model may decide
//      whether a web search is needed.
// `max_tokens` is raised slightly because a tool-call turn carries the tool
// arguments in addition to (or instead of) the answer. `extraMessages`, when
// supplied by the agent loop, carries the prior assistant tool_call and the
// tool result so the model can ground its final answer on the search excerpt.
export function openAICompatibleWithTools(profile, prompt, tools, extraMessages) {
  const { url, options } = openAICompatibleRequest(profile, prompt);
  const body = JSON.parse(options.body);
  delete body.response_format;
  body.max_tokens = 500;
  body.tools = tools;
  body.tool_choice = 'auto';
  if (Array.isArray(extraMessages) && extraMessages.length > 0) {
    body.messages = [...body.messages, ...extraMessages];
  }
  return { url, options: { ...options, body: JSON.stringify(body) } };
}

// Normalises OpenAI-compatible tool_calls into a protocol-agnostic shape used
// by the agent router: [{ id, name, arguments }]. `arguments` is parsed to an
// object when possible (providers send a JSON string), otherwise kept as the
// raw string so the executor can decide how to handle it. `id` is preserved
// because the follow-up `tool` message must reference it via `tool_call_id`.
// Returns null when the turn carried no tool call.
export function openAICompatibleExtractToolCalls(body) {
  const raw = body?.choices?.[0]?.message?.tool_calls;
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const calls = [];
  for (const entry of raw) {
    const name = entry?.function?.name;
    if (typeof name !== 'string' || name.length === 0) continue;
    const argsRaw = entry?.function?.arguments;
    let args = argsRaw;
    if (typeof argsRaw === 'string' && argsRaw.length > 0) {
      try { args = JSON.parse(argsRaw); } catch { args = argsRaw; }
    }
    calls.push({ id: typeof entry.id === 'string' ? entry.id : undefined, name, arguments: args ?? {} });
  }
  return calls.length === 0 ? null : calls;
}

export function openAICompatibleStreamRequest(profile, prompt) {
  const { url, options } = openAICompatibleRequest(profile, prompt);
  const body = JSON.parse(options.body);
  body.stream = true;
  return { url, options: { ...options, body: JSON.stringify(body) } };
}

// Parses one SSE `data:` payload. OpenAI-compatible providers terminate the
// stream with the literal `data: [DONE]` sentinel.
export function openAICompatibleStreamChunk(data) {
  if (data === '[DONE]') return { done: true };
  try {
    const parsed = JSON.parse(data);
    const text = parsed?.choices?.[0]?.delta?.content;
    return typeof text === 'string' && text.length > 0 ? { text } : {};
  } catch {
    return {};
  }
}
