const fields = new Set(['baseUrl', 'apiKey', 'enabled', 'timeoutMs', 'sourcePolicies']);
const sourcePolicyFields = new Set(['id', 'domain', 'attribution', 'license', 'version', 'qualityTier', 'enabled']);

function boundedString(value, name, { minimum = 1, maximum }) {
  if (typeof value !== 'string') throw new TypeError(`${name} must be a string`);
  const normalized = value.trim();
  const length = [...normalized].length;
  if (length < minimum || length > maximum) {
    throw new TypeError(`${name} must contain ${minimum} to ${maximum} characters`);
  }
  return normalized;
}

function validatedSourcePolicies(value) {
  if (!Array.isArray(value) || value.length > 16) {
    throw new TypeError('sourcePolicies must contain at most 16 reviewed sources');
  }
  const ids = new Set();
  const domains = new Set();
  return Object.freeze(value.map((policy) => {
    if (policy == null || typeof policy !== 'object' || Array.isArray(policy)) {
      throw new TypeError('source policy must be an object');
    }
    if (Object.keys(policy).some((field) => !sourcePolicyFields.has(field))) {
      throw new TypeError('Unknown source policy field');
    }
    const id = boundedString(policy.id, 'source policy id', { maximum: 64 });
    if (!/^[a-z0-9][a-z0-9_-]*$/.test(id) || ids.has(id)) {
      throw new TypeError('source policy id must be unique and URL-safe');
    }
    const domain = boundedString(policy.domain, 'source policy domain', { maximum: 253 }).toLowerCase();
    if (!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain) || domains.has(domain)) {
      throw new TypeError('source policy domain must be a unique hostname');
    }
    // This label is persisted into the existing evidence.provider column.
    const attribution = boundedString(policy.attribution, 'source policy attribution', { maximum: 80 });
    const license = boundedString(policy.license, 'source policy license', { maximum: 120 });
    const version = boundedString(policy.version, 'source policy version', { maximum: 80 });
    // Existing reviewed policies predate explicit tiers. Treating them as B is
    // conservative: they can enrich a brief but cannot alone trigger a strong
    // action until an administrator classifies them as A or S.
    const qualityTier = policy.qualityTier ?? 'B';
    if (!['S', 'A', 'B', 'C'].includes(qualityTier)) {
      throw new TypeError('source policy qualityTier must be S, A, B or C');
    }
    if (typeof policy.enabled !== 'boolean') throw new TypeError('source policy enabled must be a boolean');
    ids.add(id);
    domains.add(domain);
    return Object.freeze({ id, domain, attribution, license, version, qualityTier, enabled: policy.enabled });
  }));
}

// This lives in the encrypted runtime document, alongside model profiles. It
// deliberately has no provider name or arbitrary headers: V1 is a narrowly
// scoped Tavily adapter, not a general-purpose outbound HTTP proxy.
export function validateDiscoverySearchProfile(input, { existing = null } = {}) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new TypeError('Discovery search profile must be an object');
  }
  for (const field of Object.keys(input)) {
    if (!fields.has(field)) throw new TypeError(`Unknown discovery search profile field: ${field}`);
  }

  const baseUrl = boundedString(input.baseUrl ?? existing?.baseUrl ?? '', 'baseUrl', {
    maximum: 500,
  });
  let url;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new TypeError('baseUrl must be a valid HTTP or HTTPS URL');
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.search || url.hash) {
    throw new TypeError('baseUrl must be a plain HTTP or HTTPS URL');
  }

  let apiKey = input.apiKey;
  if (apiKey === undefined && existing != null) apiKey = existing.apiKey;
  apiKey = boundedString(apiKey ?? '', 'apiKey', { minimum: 0, maximum: 2_000 });
  const sourcePolicies = validatedSourcePolicies(input.sourcePolicies ?? existing?.sourcePolicies ?? []);
  if (typeof input.enabled !== 'boolean') throw new TypeError('enabled must be a boolean');
  if (input.enabled && apiKey.length === 0) throw new TypeError('apiKey is required when search is enabled');
  if (input.enabled && !sourcePolicies.some((policy) => policy.enabled)) {
    throw new TypeError('enabled search requires at least one enabled reviewed source policy');
  }
  if (!Number.isInteger(input.timeoutMs) || input.timeoutMs < 2_000 || input.timeoutMs > 30_000) {
    throw new RangeError('timeoutMs must be an integer between 2000 and 30000');
  }

  return Object.freeze({
    baseUrl: url.toString().replace(/\/$/, ''),
    apiKey,
    enabled: input.enabled,
    timeoutMs: input.timeoutMs,
    sourcePolicies,
  });
}

export function defaultDiscoverySearchProfile() {
  return Object.freeze({
    baseUrl: 'https://api.tavily.com',
    apiKey: '',
    enabled: false,
    timeoutMs: 8_000,
    sourcePolicies: Object.freeze([]),
  });
}
