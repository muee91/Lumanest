import { requestNarrative } from './adapters/index.mjs';

const fallbackErrors = new Set(['timeout', 'rate_limited', 'upstream_unavailable']);

export async function routeNarrative({
  profiles,
  routing,
  prompt,
  fetcher = fetch,
  requester = requestNarrative,
}) {
  const profilesById = new Map(profiles.map((profile) => [profile.id, profile]));
  const primary = routing.primaryProfileId == null
    ? null : profilesById.get(routing.primaryProfileId);
  if (primary == null || !primary.enabled || primary.model.length === 0) {
    return { ok: false, error: 'ai_unconfigured', attempts: [] };
  }

  const profileIds = [primary.id];
  if (routing.fallbackEnabled) profileIds.push(...routing.fallbackProfileIds);
  const maximumAttempts = Math.min(3, Math.max(1, routing.maximumAttempts));
  const attempts = [];
  let lastError = 'upstream_unavailable';
  for (const id of profileIds.slice(0, maximumAttempts)) {
    const profile = profilesById.get(id);
    if (profile == null || !profile.enabled || profile.model.length === 0) continue;
    attempts.push(id);
    const result = await requester({ profile, prompt, fetcher });
    if (result.ok) return { ok: true, text: result.text, profileId: id, attempts };
    lastError = result.error;
    if (!routing.fallbackEnabled || !fallbackErrors.has(result.error)) break;
  }
  return { ok: false, error: lastError, attempts };
}
