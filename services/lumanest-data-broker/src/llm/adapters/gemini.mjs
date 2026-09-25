import { apiErrorCodes } from '../../api/error-codes.mjs';

// Gemini uses `user`/`model` roles (not `assistant`), so prior turns are
// remapped here. History always alternates user→model and ends before the
// current user turn, which keeps the contents sequence valid.
function geminiContents(prompt) {
  return [
    ...(prompt.history ?? []).map((turn) => ({
      role: turn.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: turn.content }],
    })),
    { role: 'user', parts: [{ text: prompt.user }] },
  ];
}

export function geminiRequest(profile, prompt) {
  const url = new URL(
    `models/${encodeURIComponent(profile.model)}:generateContent`,
    `${profile.baseUrl.replace(/\/+$/, '')}/`,
  );
  return {
    url,
    options: {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': profile.apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: prompt.system }] },
        contents: geminiContents(prompt),
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

export function geminiStreamRequest(profile, prompt) {
  const url = new URL(
    `models/${encodeURIComponent(profile.model)}:streamGenerateContent`,
    `${profile.baseUrl.replace(/\/+$/, '')}/`,
  );
  url.searchParams.set('alt', 'sse');
  return {
    url,
    options: {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': profile.apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: prompt.system }] },
        contents: geminiContents(prompt),
        generationConfig: {
          temperature: 0.4,
          responseMimeType: 'application/json',
          maxOutputTokens: 300,
        },
      }),
    },
  };
}

export function geminiStreamChunk(data) {
  try {
    const parsed = JSON.parse(data);
    const text = parsed?.candidates?.[0]?.content?.parts?.find((part) =>
      typeof part?.text === 'string')?.text;
    return typeof text === 'string' && text.length > 0 ? { text } : {};
  } catch {
    return {};
  }
}
