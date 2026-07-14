import assert from 'node:assert/strict';
import test from 'node:test';

import {
  providerCatalog,
  publicProviderCatalog,
} from '../src/llm/provider-catalog.mjs';
import { validateLLMProfile } from '../src/llm/profile.mjs';

test('catalog exposes eleven provider templates without an active or default provider', () => {
  assert.deepEqual([...providerCatalog.keys()], [
    'openai', 'anthropic', 'gemini', 'qwen', 'deepseek', 'zhipu',
    'moonshot', 'volcengine', 'openrouter', 'ollama', 'custom_openai',
  ]);
  const serialized = JSON.stringify(publicProviderCatalog());
  assert.equal(/"(?:active|default|apiKey)"/.test(serialized), false);
  assert.equal(Object.isFrozen(publicProviderCatalog()), true);
});

test('catalog maps providers only to supported protocol adapters', () => {
  const protocols = new Set([...providerCatalog.values()].map((value) => value.protocol));
  assert.deepEqual(protocols, new Set([
    'openai_compatible', 'anthropic_messages', 'google_generate_content',
  ]));
  assert.equal(providerCatalog.get('anthropic').protocol, 'anthropic_messages');
  assert.equal(providerCatalog.get('gemini').protocol, 'google_generate_content');
  assert.equal(providerCatalog.get('deepseek').protocol, 'openai_compatible');
});

test('validates an explicitly created provider profile', () => {
  const profile = validateLLMProfile({
    id: 'deepseek-main',
    name: 'DeepSeek 主模型',
    providerId: 'deepseek',
    protocol: 'openai_compatible',
    apiKey: 'secret-key',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
    enabled: true,
    timeoutMs: 8_000,
    allowFallback: false,
  });
  assert.equal(profile.providerId, 'deepseek');
  assert.equal(Object.isFrozen(profile), true);
});

test('custom OpenAI-compatible profiles accept an explicit endpoint', () => {
  const profile = validateLLMProfile({
    id: 'studio-model', name: '工作室模型', providerId: 'custom_openai',
    protocol: 'openai_compatible', apiKey: 'local-secret',
    baseUrl: 'http://192.168.100.20:11434/v1', model: 'my-model',
    enabled: true, timeoutMs: 30_000, allowFallback: true,
  });
  assert.equal(profile.baseUrl, 'http://192.168.100.20:11434/v1');
});

test('Ollama profile may omit an API key', () => {
  const profile = validateLLMProfile({
    id: 'ollama-lan', name: 'NAS Ollama', providerId: 'ollama',
    protocol: 'openai_compatible', baseUrl: 'http://192.168.100.151:11434/v1',
    model: 'local-model', enabled: true, timeoutMs: 30_000, allowFallback: false,
  });
  assert.equal(profile.apiKey, '');
});

test('an update preserves an existing key when the key field is omitted', () => {
  const existing = validateLLMProfile({
    id: 'openai-main', name: 'OpenAI', providerId: 'openai',
    protocol: 'openai_compatible', apiKey: 'existing-secret',
    baseUrl: 'https://api.openai.com/v1', model: 'gpt-model',
    enabled: true, timeoutMs: 8_000, allowFallback: false,
  });
  const updated = validateLLMProfile({ ...existing, name: 'OpenAI 主模型', apiKey: undefined }, { existing });
  assert.equal(updated.apiKey, 'existing-secret');
});

test('rejects unknown fields, providers and protocol mismatches', () => {
  const base = {
    id: 'profile-id', name: 'Profile', providerId: 'openai',
    protocol: 'openai_compatible', apiKey: 'secret',
    baseUrl: 'https://api.openai.com/v1', model: 'model',
    enabled: true, timeoutMs: 8_000, allowFallback: false,
  };
  assert.throws(() => validateLLMProfile({ ...base, surprise: true }), /Unknown LLM profile field/);
  assert.throws(() => validateLLMProfile({ ...base, providerId: 'unknown' }), /Unknown LLM provider/);
  assert.throws(() => validateLLMProfile({ ...base, protocol: 'anthropic_messages' }), /protocol/);
});

test('accepts unselected draft models but rejects malformed IDs, URLs and timeouts', () => {
  const base = {
    id: 'profile-id', name: 'Profile', providerId: 'openai',
    protocol: 'openai_compatible', apiKey: 'secret',
    baseUrl: 'https://api.openai.com/v1', model: 'model',
    enabled: true, timeoutMs: 8_000, allowFallback: false,
  };
  assert.throws(() => validateLLMProfile({ ...base, id: '../bad' }), /id/);
  assert.throws(() => validateLLMProfile({ ...base, baseUrl: 'file:///tmp/model' }), /baseUrl/);
  assert.equal(validateLLMProfile({ ...base, model: '' }).model, '');
  assert.throws(() => validateLLMProfile({ ...base, timeoutMs: 31_000 }), /timeoutMs/);
});
