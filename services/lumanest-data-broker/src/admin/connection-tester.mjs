const severity = new Map([
  ['ok', 0], ['unconfigured', 0], ['local_signing_ready', 0],
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

    let ai = 'unconfigured';
    if (snapshot.settings.aiEnabled && snapshot.aiApiKey) {
      const aiUrl = new URL('models', `${snapshot.aiBaseUrl.replace(/\/+$/, '')}/`);
      ai = await requestJson(
        fetcher,
        aiUrl,
        { headers: { Authorization: `Bearer ${snapshot.aiApiKey}` }, signal: AbortSignal.timeout(timeout) },
        (value) => value != null && typeof value === 'object',
      );
    }
    const services = {
      qweather: snapshot.privateKey && snapshot.keyId && snapshot.projectId
        ? 'local_signing_ready' : 'unconfigured',
      amap,
      ai,
    };
    const status = Object.values(services).reduce((worst, value) =>
      (severity.get(value) ?? 0) > (severity.get(worst) ?? 0) ? value : worst, 'ok');
    return { status, services };
  };
}
