import { createPrivateKey } from 'node:crypto';

import {
  defaultRuntimeSettings,
  pruneUnknownRuntimeSettings,
  validateRuntimeSettings,
} from './runtime-settings.mjs';
import { validateLLMProfile } from '../llm/profile.mjs';
import { defaultDiscoverySearchProfile, validateDiscoverySearchProfile } from '../discovery/search-profile.mjs';
import { providerSourceDefaults, validateProviderSources } from '../environment/provider-runtime-config.mjs';

const configurableFields = new Set([
  'qweatherPrivateKeyPem',
  'keyId',
  'projectId',
  'serviceToken',
  'amapWebKey',
  'llmProfiles',
  'llmRouting',
  'discoverySearchProfile',
  'providerSources',
  'settings',
]);

const requiredStringFields = new Set([
  'keyId',
  'projectId',
  'serviceToken',
  'amapWebKey',
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
    if (name === 'llmProfiles') {
      if (!Array.isArray(value) || value.length > 20) {
        throw new TypeError('llmProfiles must be an array with at most 20 profiles');
      }
      continue;
    }
    if (name === 'llmRouting') {
      if (value == null || typeof value !== 'object' || Array.isArray(value)) {
        throw new TypeError('llmRouting must be an object');
      }
      continue;
    }
    if (name === 'discoverySearchProfile') {
      if (value == null || typeof value !== 'object' || Array.isArray(value)) {
        throw new TypeError('discoverySearchProfile must be an object');
      }
      continue;
    }
    if (name === 'providerSources') {
      validateProviderSources(value, { partial: true });
      continue;
    }
    if (typeof value !== 'string') {
      throw new TypeError(`${name} must be a string or null`);
    }
    if (requiredStringFields.has(name) && value.trim().length === 0) {
      throw new TypeError(`${name} must not be empty`);
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
    } else if (name === 'llmProfiles') {
      const existingProfiles = new Map((result.llmProfiles ?? []).map((profile) => [profile.id, profile]));
      result.llmProfiles = value.map((profile) => {
        if (profile?.apiKey !== undefined) return profile;
        const existing = existingProfiles.get(profile?.id);
        return existing == null ? profile : { ...profile, apiKey: existing.apiKey };
      });
    } else if (name === 'llmRouting') {
      result.llmRouting = { ...(result.llmRouting ?? {}), ...value };
    } else if (name === 'discoverySearchProfile') {
      result.discoverySearchProfile = {
        ...(result.discoverySearchProfile ?? {}),
        ...value,
      };
      if (value.apiKey === undefined && result.discoverySearchProfile.apiKey === undefined &&
          current.discoverySearchProfile?.apiKey !== undefined) {
        result.discoverySearchProfile.apiKey = current.discoverySearchProfile.apiKey;
      }
    } else if (name === 'providerSources') {
      result.providerSources = {
        ...(result.providerSources ?? {}),
        ...value,
      };
    } else {
      result[name] = value;
    }
  }
  return result;
}

const defaultLLMRouting = Object.freeze({
  primaryProfileId: null,
  fallbackEnabled: false,
  fallbackProfileIds: Object.freeze([]),
  maximumAttempts: 3,
});

function normalizedProfiles(value) {
  if (!Array.isArray(value) || value.length > 20) {
    throw new TypeError('llmProfiles must be an array with at most 20 profiles');
  }
  const profiles = value.map((profile) => validateLLMProfile(profile));
  const ids = new Set();
  for (const profile of profiles) {
    if (ids.has(profile.id)) throw new TypeError(`Duplicate LLM profile: ${profile.id}`);
    ids.add(profile.id);
  }
  return Object.freeze(profiles);
}

function normalizedRouting(value, profiles) {
  const input = { ...defaultLLMRouting, ...(value ?? {}) };
  const allowed = new Set(Object.keys(defaultLLMRouting));
  for (const name of Object.keys(input)) {
    if (!allowed.has(name)) throw new TypeError(`Unknown LLM routing field: ${name}`);
  }
  if (input.primaryProfileId !== null && typeof input.primaryProfileId !== 'string') {
    throw new TypeError('primaryProfileId must be a profile ID or null');
  }
  if (typeof input.fallbackEnabled !== 'boolean') {
    throw new TypeError('fallbackEnabled must be a boolean');
  }
  if (!Array.isArray(input.fallbackProfileIds) ||
      input.fallbackProfileIds.some((id) => typeof id !== 'string')) {
    throw new TypeError('fallbackProfileIds must be an array of profile IDs');
  }
  if (!Number.isInteger(input.maximumAttempts) || input.maximumAttempts < 1 || input.maximumAttempts > 3) {
    throw new RangeError('maximumAttempts must be between 1 and 3');
  }
  const profilesById = new Map(profiles.map((profile) => [profile.id, profile]));
  if (input.primaryProfileId !== null) {
    const primary = profilesById.get(input.primaryProfileId);
    if (primary == null || !primary.enabled || primary.model.length === 0) {
      throw new TypeError('primaryProfileId must reference an enabled profile with a selected model');
    }
  }
  const fallbackIds = [...input.fallbackProfileIds];
  if (new Set(fallbackIds).size !== fallbackIds.length) {
    throw new TypeError('fallbackProfileIds must not contain duplicates');
  }
  for (const id of fallbackIds) {
    const fallback = profilesById.get(id);
    if (fallback == null || !fallback.enabled || fallback.model.length === 0 ||
        !fallback.allowFallback || id === input.primaryProfileId) {
      throw new TypeError('fallbackProfileIds must reference distinct enabled fallback profiles with selected models');
    }
  }
  return Object.freeze({
    primaryProfileId: input.primaryProfileId,
    fallbackEnabled: input.fallbackEnabled,
    fallbackProfileIds: Object.freeze(fallbackIds),
    maximumAttempts: input.maximumAttempts,
  });
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
  const llmProfiles = normalizedProfiles(overrides.llmProfiles ?? []);
  const llmRouting = normalizedRouting(overrides.llmRouting, llmProfiles);
  const discoverySearchProfile = validateDiscoverySearchProfile({
    ...defaultDiscoverySearchProfile(),
    ...(overrides.discoverySearchProfile ?? {}),
  });
  const providerSources = validateProviderSources({
    ...providerSourceDefaults(),
    ...(defaults.providerSources ?? {}),
    ...(overrides.providerSources ?? {}),
  });
  const effective = {
    privateKey: privateKeyFrom(defaults, overrides),
    keyId: overrides.keyId ?? defaults.keyId,
    projectId: overrides.projectId ?? defaults.projectId,
    serviceToken: overrides.serviceToken ?? defaults.serviceToken,
    amapWebKey: overrides.amapWebKey ?? defaults.amapWebKey,
    llmProfiles,
    llmRouting,
    discoverySearchProfile,
    providerSources,
    contextServiceUrl: defaults.contextServiceUrl ?? '',
    contextInternalToken: defaults.contextInternalToken ?? '',
    discoveryServiceUrl: defaults.discoveryServiceUrl ?? '',
    discoveryInternalToken: defaults.discoveryInternalToken ?? '',
    discoveryWorkerToken: defaults.discoveryWorkerToken ?? '',
    qweatherApiHost: defaults.qweatherApiHost ?? '',
    sunsetBotBaseUrl: defaults.sunsetBotBaseUrl ?? 'https://sunsetbot.top',
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
    const sanitized = Object.hasOwn(persisted, 'settings')
      ? { ...persisted, settings: pruneUnknownRuntimeSettings(persisted.settings) }
      : persisted;
    validatePatch(sanitized);
    const normalized = mergedOverrides({}, sanitized);
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
