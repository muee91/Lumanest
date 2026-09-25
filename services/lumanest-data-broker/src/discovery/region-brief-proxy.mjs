import { apiErrorCodes } from '../api/error-codes.mjs';

import {
  validRegionBriefResponse,
} from './region-brief-contract.mjs';

export async function forwardRegionBrief({
  body,
  serviceUrl,
  internalToken,
  sourcePolicies = [],
  fetcher = fetch,
  timeoutMs = 8_000,
}) {
  if (!serviceUrl || !internalToken) return { ok: false, error: apiErrorCodes.notConfigured };
  try {
    const upstream = await fetcher(new URL('/internal/v1/explore/brief', serviceUrl), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': internalToken,
      },
      body: JSON.stringify({
        ...body,
        sourcePolicies: sourcePolicies.filter((policy) => policy?.enabled).map((policy) => ({
          id: policy.id,
          version: policy.version,
          qualityTier: policy.qualityTier ?? 'B',
        })),
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const responseBody = await upstream.json();
    if (![200, 202].includes(upstream.status) || !validRegionBriefResponse(responseBody)) {
      return { ok: false, error: apiErrorCodes.upstreamUnavailable };
    }
    return { ok: true, status: upstream.status, body: responseBody };
  } catch {
    return { ok: false, error: apiErrorCodes.upstreamUnavailable };
  }
}
