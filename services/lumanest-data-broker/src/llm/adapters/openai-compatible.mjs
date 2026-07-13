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
        temperature: 0.4,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: prompt.system },
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
