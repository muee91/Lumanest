const templates = [
  ['openai', 'OpenAI', 'openai_compatible', 'https://api.openai.com/v1', ['gpt-4.1-mini']],
  ['anthropic', 'Anthropic Claude', 'anthropic_messages', 'https://api.anthropic.com/v1', []],
  ['gemini', 'Google Gemini', 'google_generate_content', 'https://generativelanguage.googleapis.com/v1beta', []],
  ['qwen', '通义千问', 'openai_compatible', 'https://dashscope.aliyuncs.com/compatible-mode/v1', ['qwen-plus']],
  ['deepseek', 'DeepSeek', 'openai_compatible', 'https://api.deepseek.com', ['deepseek-chat']],
  ['zhipu', '智谱 GLM', 'openai_compatible', 'https://open.bigmodel.cn/api/paas/v4', []],
  ['moonshot', 'Moonshot / Kimi', 'openai_compatible', 'https://api.moonshot.cn/v1', []],
  ['volcengine', '火山方舟', 'openai_compatible', 'https://ark.cn-beijing.volces.com/api/v3', []],
  ['openrouter', 'OpenRouter', 'openai_compatible', 'https://openrouter.ai/api/v1', []],
  ['ollama', 'Ollama', 'openai_compatible', '', []],
  ['custom_openai', '自定义 OpenAI 兼容服务', 'openai_compatible', '', []],
];

export const providerCatalog = new Map(templates.map(([
  id, name, protocol, baseUrl, suggestedModels,
]) => [id, Object.freeze({
  id,
  name,
  protocol,
  baseUrl,
  suggestedModels: Object.freeze([...suggestedModels]),
  requiresApiKey: id !== 'ollama',
  endpointOverrideAllowed: true,
})]));

const publicCatalog = Object.freeze([...providerCatalog.values()].map((template) =>
  Object.freeze({ ...template, suggestedModels: template.suggestedModels })));

export function publicProviderCatalog() {
  return publicCatalog;
}
