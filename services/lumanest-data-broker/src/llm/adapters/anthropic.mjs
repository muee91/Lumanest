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
        messages: [{ role: 'user', content: prompt.user }],
      }),
    },
  };
}

export function anthropicText(body) {
  const text = body?.content?.find((part) => part?.type === 'text')?.text;
  return typeof text === 'string' && text.length > 0 ? text : null;
}
