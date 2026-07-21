function responseError(status) {
  if (status === 401 || status === 403) return 'authentication_failed';
  if (status === 429) return 'rate_limited';
  if (status >= 400 && status < 500) return 'request_rejected';
  return 'upstream_unavailable';
}

function requestFor(profile) {
  const baseUrl = `${profile.baseUrl.replace(/\/+$/, '')}/`;
  if (profile.protocol === 'openai_compatible') {
    const headers = {};
    if (profile.apiKey) headers.Authorization = `Bearer ${profile.apiKey}`;
    return { url: new URL('models', baseUrl), options: { headers } };
  }
  if (profile.protocol === 'anthropic_messages') {
    return {
      url: new URL('models', baseUrl),
      options: { headers: { 'x-api-key': profile.apiKey, 'anthropic-version': '2023-06-01' } },
    };
  }
  if (profile.protocol === 'google_generate_content') {
    const url = new URL('models', baseUrl);
    return { url, options: { headers: { 'x-goog-api-key': profile.apiKey } } };
  }
  return null;
}

function normalizeModelId(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().replace(/^models\//, '');
  return normalized.length > 0 && normalized.length <= 160 ? normalized : null;
}

function modelsFrom(profile, body) {
  const records = profile.protocol === 'google_generate_content' ? body?.models : body?.data;
  if (!Array.isArray(records)) return null;
  const models = [];
  const seen = new Set();
  for (const record of records) {
    const model = normalizeModelId(record?.id ?? record?.name);
    if (model != null && !seen.has(model)) {
      seen.add(model);
      models.push(model);
    }
    if (models.length === 200) break;
  }
  return models;
}

export async function listModels({ profile, fetcher = fetch }) {
  const request = requestFor(profile);
  if (request == null) return { ok: false, error: 'request_rejected' };
  let response;
  try {
    response = await fetcher(request.url, {
      ...request.options,
      signal: AbortSignal.timeout(profile.timeoutMs),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return { ok: false, error: timeout ? 'timeout' : 'upstream_unavailable' };
  }
  if (!response.ok) return { ok: false, error: responseError(response.status) };
  try {
    const models = modelsFrom(profile, await response.json());
    return models == null ? { ok: false, error: 'invalid_response' } : { ok: true, models };
  } catch {
    return { ok: false, error: 'invalid_response' };
  }
}
