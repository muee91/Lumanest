import { requestNarrative } from '../llm/adapters/index.mjs';
import { listModels } from '../llm/model-lister.mjs';

const severity = new Map([
  ['ok', 0], ['unconfigured', 0], ['model_required', 0], ['local_signing_ready', 0],
  ['invalid_response', 1], ['upstream_unavailable', 2], ['timeout', 3], ['authentication_failed', 4],
]);

async function requestJson(fetcher, url, options, validate) {
  let response;
  try {
    response = await fetcher(url, options);
  } catch (error) {
    return error?.name === 'TimeoutError' || error?.name === 'AbortError' ? 'timeout' : 'upstream_unavailable';
  }
  if (response.status === 401 || response.status === 403) return 'authentication_failed';
  if (!response.ok) return 'upstream_unavailable';
  try {
    const value = await response.json();
    return validate(value) ? 'ok' : 'invalid_response';
  } catch {
    return 'invalid_response';
  }
}

export function createConnectionTester({ runtimeConfig, fetcher = fetch }) {
  return async function testConnections() {
    const snapshot = runtimeConfig.snapshot();
    const timeout = snapshot.settings.upstreamTimeoutMs;
    const amapUrl = new URL('/v3/config/district', 'https://restapi.amap.com');
    amapUrl.searchParams.set('keywords', '中国');
    amapUrl.searchParams.set('subdistrict', '0');
    amapUrl.searchParams.set('key', snapshot.amapWebKey);
    const amap = await requestJson(
      fetcher,
      amapUrl,
      { signal: AbortSignal.timeout(timeout) },
      (value) => value?.status === '1',
    );

    const services = {
      qweather: snapshot.privateKey && snapshot.keyId && snapshot.projectId
        ? 'local_signing_ready' : 'unconfigured',
      amap,
      llm: snapshot.llmProfiles?.some((profile) => profile.enabled && profile.model.length > 0)
        ? 'configured' : 'unconfigured',
    };
    const status = Object.values(services).reduce((worst, value) =>
      (severity.get(value) ?? 0) > (severity.get(worst) ?? 0) ? value : worst, 'ok');
    return { status, services };
  };
}

export function createLLMProfileTester({ runtimeConfig, fetcher = fetch, requester = requestNarrative }) {
  return async function testLLMProfile(profileId) {
    const profile = runtimeConfig.snapshot().llmProfiles?.find((candidate) => candidate.id === profileId);
    if (profile == null) return { status: 'profile_not_found', profileId };
    if (profile.model.length === 0) return { status: 'model_required', profileId };
    const result = await requester({
      profile,
      fetcher,
      prompt: {
        system: '只输出 JSON 对象。',
        user: '输出 {"status":"ok"}。',
      },
    });
    if (!result.ok) return { status: result.error, profileId };
    try {
      const value = JSON.parse(result.text);
      return value?.status === 'ok'
        ? { status: 'ok', profileId }
        : { status: 'invalid_response', profileId };
    } catch {
      return { status: 'invalid_response', profileId };
    }
  };
}

export function createLLMModelLister({ fetcher = fetch, lister = listModels } = {}) {
  return async function listLLMModels(profile) {
    return lister({ profile, fetcher });
  };
}
