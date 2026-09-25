import { apiErrorCodes } from '../api/error-codes.mjs';

// Assistant tool-calling support. V1 exposes a single `web_search` tool that
// delegates to the existing Tavily adapter (discovery/ingestion.mjs), so the
// assistant can answer questions the local snapshot cannot cover (opening
// hours, recent events, …). Source authority is preserved by reusing the
// reviewed `sourcePolicies` allow-list: every returned snippet comes from a
// whitelisted domain and carries its attribution.
//
// The tool is described in the OpenAI function-calling shape because that is
// the only protocol the agent router currently drives; the adapter layer is
// responsible for translating to other protocols when they gain tool support.

import { searchTavily } from '../discovery/ingestion.mjs';

// Cap the total text we feed back into the model from a single search so the
// fact card + search excerpts never blow the prompt budget. Mirrors the
// contextFacts budget on the assistant side.
const searchExcerptMaxChars = 600;

export const assistantTools = [
  {
    type: 'function',
    function: {
      name: 'web_search',
      description: '当本地环境数据（天气、天空机会、野生动物、地点）无法回答用户问题时，联网搜索最新公开信息，例如景点开放时间、近期活动、门票政策。仅在确实需要外部信息时调用。',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: '搜索关键词，用中文，聚焦一个具体问题。' },
        },
        required: ['query'],
        additionalProperties: false,
      },
    },
  },
];

// Executes one web_search call and returns both a compact textual excerpt (to
// append to the conversation as the tool result message) and the structured
// results (so the grounding guard can admit facts that originate from the
// search snippets). Any failure is reported as `{ ok: false }`; the agent
// router treats that as “no results” and lets the model fall back to the
// template/contextFacts answer rather than surfacing an error.
export async function executeWebSearch({ query, profile, fetcher, signal }) {
  if (typeof query !== 'string' || query.trim().length === 0) {
    return { ok: false, error: apiErrorCodes.emptyQuery };
  }
  if (profile?.enabled !== true) {
    return { ok: false, error: apiErrorCodes.searchUnconfigured };
  }
  // Domains default to the full reviewed allow-list, matching the discovery
  // worker behaviour when no explicit domains are supplied. This keeps every
  // cited fact inside the whitelisted sources.
  const domains = profile.sourcePolicies
    .filter((policy) => policy.enabled)
    .map((policy) => policy.domain);
  const result = await searchTavily({
    request: {
      query: query.trim().slice(0, 180),
      locale: 'zh-CN',
      freshnessDays: 31,
      domains,
    },
    profile,
    fetcher,
    signal,
  });
  if (!result.ok) return { ok: false, error: result.error };
  const items = result.results.slice(0, 4);
  if (items.length === 0) return { ok: true, excerpt: '', results: [] };

  const lines = [];
  const structured = [];
  let used = 0;
  for (const item of items) {
    const publisher = typeof item.publisher === 'string' ? item.publisher : '';
    const line = `${item.title}（${publisher}）：${item.snippet}`;
    const chars = [...line].length;
    if (used + chars + 1 > searchExcerptMaxChars) break;
    used += chars + 1;
    lines.push(line);
    structured.push({
      title: item.title,
      snippet: item.snippet,
      publisher,
      url: item.url,
    });
  }
  return { ok: true, excerpt: lines.join('\n'), results: structured };
}
