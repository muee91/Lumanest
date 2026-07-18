const validModes = new Set(['direct', 'mihomo']);

function timeoutSignal(timeoutMs) {
  return AbortSignal.timeout(timeoutMs);
}

function controllerError(error) {
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return 'controller_timeout';
  return 'controller_unavailable';
}

export function createOutboundNetworkControllerClient({
  baseUrl = '',
  token = '',
  fetchImpl = fetch,
  timeoutMs = 8_000,
} = {}) {
  const configured = baseUrl.length > 0 && token.length >= 24;

  async function request(path, { method = 'GET', body } = {}) {
    if (!configured) return { status: 'unavailable', error: 'controller_not_configured' };
    try {
      const response = await fetchImpl(`${baseUrl}${path}`, {
        method,
        headers: {
          'X-LumaNest-Network-Token': token,
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: timeoutSignal(timeoutMs),
      });
      const value = await response.json().catch(() => ({}));
      if (!response.ok) return { status: 'unavailable', error: value.error ?? 'controller_rejected' };
      return value;
    } catch (error) {
      return { status: 'unavailable', error: controllerError(error) };
    }
  }

  return Object.freeze({
    status: () => request('/v1/outbound-network'),
    apply: (mode) => validModes.has(mode)
      ? request('/v1/outbound-network', { method: 'PUT', body: { mode } })
      : Promise.resolve({ status: 'invalid', error: 'invalid_mode' }),
  });
}
