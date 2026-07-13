import { providerCatalog } from './provider-catalog.mjs';

const fields = new Set([
  'id', 'name', 'providerId', 'protocol', 'apiKey', 'baseUrl', 'model',
  'enabled', 'timeoutMs', 'allowFallback',
]);

function boundedString(value, name, { minimum = 1, maximum }) {
  if (typeof value !== 'string') throw new TypeError(`${name} must be a string`);
  const normalized = value.trim();
  if ([...normalized].length < minimum || [...normalized].length > maximum) {
    throw new TypeError(`${name} must contain ${minimum} to ${maximum} characters`);
  }
  return normalized;
}

export function validateLLMProfile(input, { existing = null } = {}) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new TypeError('LLM profile must be an object');
  }
  for (const field of Object.keys(input)) {
    if (!fields.has(field)) throw new TypeError(`Unknown LLM profile field: ${field}`);
  }

  const id = boundedString(input.id, 'id', { minimum: 3, maximum: 64 });
  if (!/^[a-z0-9][a-z0-9_-]*$/.test(id)) {
    throw new TypeError('id must contain lowercase letters, numbers, underscores or hyphens');
  }
  const providerId = boundedString(input.providerId, 'providerId', { maximum: 64 });
  const provider = providerCatalog.get(providerId);
  if (provider == null) throw new TypeError(`Unknown LLM provider: ${providerId}`);
  if (input.protocol !== provider.protocol) {
    throw new TypeError(`protocol must be ${provider.protocol} for ${providerId}`);
  }

  const name = boundedString(input.name, 'name', { maximum: 80 });
  const model = boundedString(input.model, 'model', { maximum: 160 });
  const baseUrl = boundedString(input.baseUrl, 'baseUrl', { maximum: 500 });
  let parsedUrl;
  try {
    parsedUrl = new URL(baseUrl);
  } catch {
    throw new TypeError('baseUrl must be a valid HTTP or HTTPS URL');
  }
  if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
    throw new TypeError('baseUrl must use HTTP or HTTPS');
  }

  let apiKey = input.apiKey;
  if (apiKey === undefined && existing != null) apiKey = existing.apiKey;
  if (apiKey === undefined && !provider.requiresApiKey) apiKey = '';
  if (typeof apiKey !== 'string') throw new TypeError('apiKey must be a string');
  apiKey = apiKey.trim();
  if (provider.requiresApiKey && apiKey.length === 0) {
    throw new TypeError(`apiKey is required for ${providerId}`);
  }
  if (apiKey.length > 2_000) throw new TypeError('apiKey is too long');

  if (typeof input.enabled !== 'boolean') throw new TypeError('enabled must be a boolean');
  if (typeof input.allowFallback !== 'boolean') {
    throw new TypeError('allowFallback must be a boolean');
  }
  if (!Number.isInteger(input.timeoutMs) || input.timeoutMs < 2_000 || input.timeoutMs > 30_000) {
    throw new RangeError('timeoutMs must be an integer between 2000 and 30000');
  }

  return Object.freeze({
    id,
    name,
    providerId,
    protocol: provider.protocol,
    apiKey,
    baseUrl: baseUrl.replace(/\/+$/, ''),
    model,
    enabled: input.enabled,
    timeoutMs: input.timeoutMs,
    allowFallback: input.allowFallback,
  });
}
