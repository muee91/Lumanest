import { LLMCallBudget, routeNarrative } from '../llm/router.mjs';

function compactContext(snapshot) {
  const environment = snapshot.environment ?? {};
  return Object.freeze({
    scene: environment.sceneContext?.primaryScene ?? environment.scene ?? 'unknown',
    dayPhase: environment.sunMoon?.dayPhase ?? 'unknown',
    weather: environment.weather?.type ?? environment.weather ?? 'unknown',
    activeRoute: environment.route?.active === true,
    activeOpportunityIds: (snapshot.facts?.events ?? [])
      .filter((event) => event.channel === 'opportunity')
      .map((event) => event.id)
      .slice(0, 3),
  });
}

export function creativeSelectionPrompt({ snapshot, candidates, maximum }) {
  return Object.freeze({
    system: '你是栖光的摄影灵感筛选器。只能从 candidates 中选择与当前场景更匹配、彼此不重复且能实际执行的创作提示；不得生成新提示、改写提示、添加地点或事实。优先题材和技法多样性。只输出 JSON：{"selectedIds":["候选ID"]}，选择3到6项且不超过 maximum。',
    user: JSON.stringify({
      questionType: 'inspiration_selection',
      question: `为 ${snapshot.contextId} 筛选当前摄影灵感`,
      context: compactContext(snapshot),
      maximum,
      candidates,
    }),
  });
}

export function parseCreativeSelection(text, candidates, maximum) {
  try {
    const value = JSON.parse(text);
    if (value == null || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).length !== 1 || !Array.isArray(value.selectedIds)) return [];
    if (value.selectedIds.length < 3 || value.selectedIds.length > maximum) return [];
    const allowed = new Set(candidates.map((candidate) => candidate.id));
    const unique = [...new Set(value.selectedIds)];
    if (unique.length !== value.selectedIds.length ||
        unique.some((id) => typeof id !== 'string' || !allowed.has(id))) return [];
    return unique;
  } catch {
    return [];
  }
}

export async function selectCreativeWithModel({
  snapshot,
  candidates,
  maximum,
  profiles,
  routing,
  aiEnabled,
  fetcher = fetch,
  router = routeNarrative,
}) {
  if (!aiEnabled || routing.primaryProfileId == null || candidates.length < 3) return [];
  const result = await router({
    profiles,
    routing,
    prompt: creativeSelectionPrompt({ snapshot, candidates, maximum }),
    fetcher,
    callBudget: new LLMCallBudget({ limit: 1 }),
  });
  if (!result.ok) return [];
  return parseCreativeSelection(result.text, candidates, maximum);
}
