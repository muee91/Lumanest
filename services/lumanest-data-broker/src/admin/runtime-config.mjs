import { createPrivateKey } from 'node:crypto';

import { defaultRuntimeSettings, validateRuntimeSettings } from './runtime-settings.mjs';

const configurableFields = new Set([
  'qweatherPrivateKeyPem',
  'keyId',
  'projectId',
  'serviceToken',
  'amapWebKey',
  'aiApiKey',
  'aiBaseUrl',
  'aiModel',
  'settings',
]);

const requiredStringFields = new Set([
  'keyId',
  'projectId',
  'serviceToken',
  'amapWebKey',
  'aiBaseUrl',
  'aiModel',
]);

function cloneConfiguration(value) {
  return structuredClone(value ?? {});
}

function validatePatch(patch) {
  if (patch == null || typeof patch !== 'object' || Array.isArray(patch)) {
    throw new TypeError('Runtime configuration patch must be an object');
  }
  for (const [name, value] of Object.entries(patch)) {
    if (!configurableFields.has(name)) {
      throw new TypeError(`Unknown runtime configuration field: ${name}`);
    }
    if (value === null) continue;
    if (name === 'settings') {
      validateRuntimeSettings(value, { partial: true });
      continue;
    }
    if (typeof value !== 'string') {
      throw new TypeError(`${name} must be a string or null`);
    }
    if (requiredStringFields.has(name) && value.trim().length === 0) {
      throw new TypeError(`${name} must not be empty`);
    }
    if (name === 'aiBaseUrl') {
      const url = new URL(value);
      if (url.protocol !== 'https:' && url.protocol !== 'http:') {
        throw new TypeError('aiBaseUrl must use HTTP or HTTPS');
      }
    }
  }
  return patch;
}

function mergedOverrides(current, patch) {
  const result = cloneConfiguration(current);
  for (const [name, value] of Object.entries(patch)) {
    if (value === null) {
      delete result[name];
    } else if (name === 'settings') {
      result.settings = { ...(result.settings ?? {}), ...value };
    } else {
      result[name] = value;
    }
  }
  return result;
}

function privateKeyFrom(defaults, overrides) {
  if (!Object.hasOwn(overrides, 'qweatherPrivateKeyPem')) return defaults.privateKey;
  try {
    return createPrivateKey(overrides.qweatherPrivateKeyPem);
  } catch (error) {
    throw new TypeError('QWeather private key PEM is invalid', { cause: error });
  }
}

function buildSnapshot(defaults, overrides, revision) {
  const effective = {
    privateKey: privateKeyFrom(defaults, overrides),
    keyId: overrides.keyId ?? defaults.keyId,
    projectId: overrides.projectId ?? defaults.projectId,
    serviceToken: overrides.serviceToken ?? defaults.serviceToken,
    amapWebKey: overrides.amapWebKey ?? defaults.amapWebKey,
    aiApiKey: overrides.aiApiKey ?? defaults.aiApiKey ?? '',
    aiBaseUrl: overrides.aiBaseUrl ?? defaults.aiBaseUrl,
    aiModel: overrides.aiModel ?? defaults.aiModel,
    port: defaults.port,
    settings: validateRuntimeSettings({
      ...defaultRuntimeSettings,
      ...(overrides.settings ?? {}),
    }),
    revision,
  };
  for (const name of requiredStringFields) {
    if (typeof effective[name] !== 'string' || effective[name].trim().length === 0) {
      throw new TypeError(`${name} must not be empty`);
    }
  }
  if (effective.privateKey == null) throw new TypeError('QWeather private key is required');
  return Object.freeze(effective);
}

export class RuntimeConfigService {
  #defaults;
  #store;
  #overrides = {};
  #snapshot = null;
  #revision = 0;
  #replaceQueue = Promise.resolve();

  constructor({ defaults, store }) {
    if (defaults == null || typeof defaults !== 'object') {
      throw new TypeError('Runtime configuration defaults are required');
    }
    if (store == null || typeof store.read !== 'function' || typeof store.write !== 'function') {
      throw new TypeError('Runtime configuration store is required');
    }
    this.#defaults = defaults;
    this.#store = store;
  }

  async initialize() {
    const persisted = await this.#store.read() ?? {};
    validatePatch(persisted);
    const normalized = mergedOverrides({}, persisted);
    this.#snapshot = buildSnapshot(this.#defaults, normalized, ++this.#revision);
    this.#overrides = normalized;
    return this.#snapshot;
  }

  snapshot() {
    if (this.#snapshot == null) throw new Error('Runtime configuration is not initialized');
    return this.#snapshot;
  }

  replace(patch) {
    const input = cloneConfiguration(patch);
    const operation = this.#replaceQueue.then(async () => {
      validatePatch(input);
      const candidateOverrides = mergedOverrides(this.#overrides, input);
      const candidate = buildSnapshot(this.#defaults, candidateOverrides, this.#revision + 1);
      await this.#store.write(candidateOverrides);
      this.#overrides = candidateOverrides;
      this.#revision += 1;
      this.#snapshot = candidate;
      return candidate;
    });
    this.#replaceQueue = operation.catch(() => {});
    return operation;
  }

  persistedOverrides() {
    return cloneConfiguration(this.#overrides);
  }
}
