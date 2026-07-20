import { createHash } from 'node:crypto';

import { requestNarrative } from './adapters/index.mjs';
import { guardGroundedOutput } from './grounding-guard.mjs';

const fallbackErrors = new Set(['timeout', 'rate_limited', 'upstream_unavailable']);

export class LLMRouteMetrics {
  #values = new Map();

  record(name) {
    this.#values.set(name, (this.#values.get(name) ?? 0) + 1);
  }

  snapshot() {
    return Object.freeze(Object.fromEntries(this.#values));
  }

  reset() {
    this.#values.clear();
  }
}

/// Process-level safety fuse, not a per-user quota. Authentication/IP rate
/// limiting remains at the Broker boundary. The generous default prevents one
/// repeated prompt shape from consuming unbounded provider capacity without
/// blocking normal users who happen to ask the same photography question.
export class LLMPromptBudget {
  #buckets = new Map();

  constructor({ now = () => new Date(), assistantLimit = 300, assistantWindowMs = 60_000 } = {}) {
    this.now = now;
    this.assistantLimit = assistantLimit;
    this.assistantWindowMs = assistantWindowMs;
  }

  consume(prompt) {
    let user;
    try {
      user = JSON.parse(prompt?.user ?? '');
    } catch {
      return { allowed: true, reason: null };
    }
    if (typeof user?.templateAnswer !== 'string') {
      return { allowed: true, reason: null };
    }
    if (user.questionType === 'safety' || user.questionType === 'nearby') {
      return { allowed: false, reason: 'deterministic_only' };
    }

    const key = createHash('sha256')
      .update(`${user.questionType ?? 'unknown'}|${user.templateAnswer}`)
      .digest('hex')
      .slice(0, 24);
    const timestamp = this.now().getTime();
    const current = this.#buckets.get(key);
    const bucket = current != null && current.resetAt > timestamp
      ? current
      : { count: 0, resetAt: timestamp + this.assistantWindowMs };
    bucket.count += 1;
    this.#buckets.set(key, bucket);
    if (this.#buckets.size > 512) {
      for (const [id, value] of this.#buckets) {
        if (value.resetAt <= timestamp) this.#buckets.delete(id);
      }
    }
    return {
      allowed: bucket.count <= this.assistantLimit,
      reason: bucket.count <= this.assistantLimit ? null : 'prompt_rate_limited',
    };
  }
}

export const llmRouteMetrics = new LLMRouteMetrics();
export const llmPromptBudget = new LLMPromptBudget();

export async function routeNarrative({
  profiles,
  routing,
  prompt,
  fetcher = fetch,
  requester = requestNarrative,
  metrics = llmRouteMetrics,
  budget = llmPromptBudget,
}) {
  metrics.record('requests');
  const budgetResult = budget.consume(prompt);
  if (!budgetResult.allowed) {
    metrics.record(`budget_${budgetResult.reason}`);
    return {
      ok: false,
      error: budgetResult.reason === 'deterministic_only'
        ? 'deterministic_only'
        : 'rate_limited',
      attempts: [],
    };
  }

  const profilesById = new Map(profiles.map((profile) => [profile.id, profile]));
  const primary = routing.primaryProfileId == null
    ? null : profilesById.get(routing.primaryProfileId);
  if (primary == null || !primary.enabled || primary.model.length === 0) {
    metrics.record('unconfigured');
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
    if (result.ok) {
      const guarded = guardGroundedOutput({ prompt, text: result.text });
      if (guarded.ok) {
        metrics.record(attempts.length > 1 ? 'fallback_success' : 'primary_success');
        return { ok: true, text: guarded.text, profileId: id, attempts };
      }
      metrics.record(`guard_${guarded.reason ?? 'invalid_response'}`);
      lastError = 'invalid_response';
      break;
    }
    lastError = result.error;
    metrics.record(`upstream_${result.error}`);
    if (!routing.fallbackEnabled || !fallbackErrors.has(result.error)) break;
  }
  metrics.record('failed');
  return { ok: false, error: lastError, attempts };
}
