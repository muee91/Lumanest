export function geminiRequest(profile, prompt) {
  const url = new URL(
    `models/${encodeURIComponent(profile.model)}:generateContent`,
    `${profile.baseUrl.replace(/\/+$/, '')}/`,
  );
  url.searchParams.set('key', profile.apiKey);
  return {
    url,
    options: {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: prompt.system }] },
        contents: [{ role: 'user', parts: [{ text: prompt.user }] }],
        generationConfig: {
          temperature: 0.4,
          responseMimeType: 'application/json',
          maxOutputTokens: 300,
        },
      }),
    },
  };
}

export function geminiText(body) {
  const text = body?.candidates?.[0]?.content?.parts?.find((part) =>
    typeof part?.text === 'string')?.text;
  return typeof text === 'string' && text.length > 0 ? text : null;
}
