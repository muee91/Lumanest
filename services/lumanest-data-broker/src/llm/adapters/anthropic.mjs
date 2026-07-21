export function anthropicRequest(profile, prompt) {
  return {
    url: new URL('messages', `${profile.baseUrl.replace(/\/+$/, '')}/`),
    options: {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': profile.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: profile.model,
        max_tokens: 300,
        temperature: 0.4,
        system: prompt.system,
        messages: [
          ...(prompt.history ?? []),
          { role: 'user', content: prompt.user },
        ],
      }),
    },
  };
}

export function anthropicText(body) {
  const text = body?.content?.find((part) => part?.type === 'text')?.text;
  return typeof text === 'string' && text.length > 0 ? text : null;
}

export function anthropicStreamRequest(profile, prompt) {
  const { url, options } = anthropicRequest(profile, prompt);
  const body = JSON.parse(options.body);
  body.stream = true;
  return { url, options: { ...options, body: JSON.stringify(body) } };
}

// Anthropic streams typed events; only content_block_delta with a text_delta
// carries output text. message_stop marks the end of the stream.
export function anthropicStreamChunk(data) {
  try {
    const parsed = JSON.parse(data);
    if (parsed?.type === 'message_stop') return { done: true };
    if (parsed?.type === 'content_block_delta' && parsed?.delta?.type === 'text_delta') {
      const text = parsed.delta.text;
      return typeof text === 'string' && text.length > 0 ? { text } : {};
    }
    return {};
  } catch {
    return {};
  }
}
