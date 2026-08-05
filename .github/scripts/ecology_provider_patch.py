from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:160]!r}')
    target.write_text(text.replace(old, new), encoding='utf-8')


runtime = 'services/lumanest-data-broker/src/environment/provider-runtime-config.mjs'
replace_once(runtime, "  'gbif',\n  'ebird',", "  'gbif',\n  'inaturalist',\n  'ebird',")
replace_once(runtime, "  'gbifBaseUrl',\n  'ebirdBaseUrl',", "  'gbifBaseUrl',\n  'inaturalistBaseUrl',\n  'ebirdBaseUrl',")
replace_once(runtime, "    enabledProviders: [...supportedProviderSourceIds],", "    enabledProviders: supportedProviderSourceIds.filter((id) => id !== 'ebird'),")
replace_once(
    runtime,
    "    gbifBaseUrl: environmentValue(environment, 'LUMANEST_GBIF_BASE_URL', 'https://api.gbif.org'),\n    ebirdBaseUrl:",
    "    gbifBaseUrl: environmentValue(environment, 'LUMANEST_GBIF_BASE_URL', 'https://api.gbif.org'),\n    inaturalistBaseUrl: environmentValue(\n      environment,\n      'LUMANEST_INATURALIST_BASE_URL',\n      'https://api.inaturalist.org',\n    ),\n    ebirdBaseUrl:",
)
replace_once(runtime, "    case 'gbif':\n      return Boolean(configuration.gbifBaseUrl);\n    case 'ebird':", "    case 'gbif':\n      return Boolean(configuration.gbifBaseUrl);\n    case 'inaturalist':\n      return Boolean(configuration.inaturalistBaseUrl);\n    case 'ebird':")
replace_once(runtime, "    gbif: 'GBIF',\n    ebird: 'eBird',", "    gbif: 'GBIF',\n    inaturalist: 'iNaturalist',\n    ebird: 'eBird（可选）',")

facts = 'services/lumanest-data-broker/src/environment/provider-facts-service.mjs'
replace_once(facts, "  'gbif',\n  'ebird',", "  'gbif',\n  'inaturalist',\n  'ebird',")
replace_once(
    facts,
    "const providerIdSet = new Set(providerIds);\nconst defaultRadiusKm = 25;",
    "const providerIdSet = new Set(providerIds);\nconst defaultProviderIds = Object.freeze(providerIds.filter((id) => id !== 'ebird'));\nconst defaultRadiusKm = 25;",
)
replace_once(facts, "    ? [...providerIds]\n    :", "    ? [...defaultProviderIds]\n    :")

inat_function = r'''
async function inaturalistProvider({ query, fetcher, timeoutMs, now, baseUrl }) {
  const id = 'inaturalist';
  const category = 'wildlife';
  const sourceInfo = source({
    id: 'inaturalist-observations-api',
    title: 'iNaturalist Observations API',
    publisher: 'iNaturalist community',
    url: 'https://www.inaturalist.org/pages/api+reference',
    license: 'Observation-specific licences; aggregate metadata only',
    version: 'v1',
  });
  const box = pointBox(query.latitude, query.longitude, Math.min(query.radiusKm, 50));
  const start = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1_000);
  const url = new URL('/v1/observations', baseUrl);
  const parameters = {
    taxon_id: 3,
    quality_grade: 'research',
    captive: 'false',
    geo: 'true',
    d1: dateOnly(start),
    nelat: box.north.toFixed(5),
    nelng: box.east.toFixed(5),
    swlat: box.south.toFixed(5),
    swlng: box.west.toFixed(5),
    per_page: 30,
    order_by: 'observed_on',
    order: 'desc',
  };
  Object.entries(parameters).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  try {
    const body = await fetchJson(fetcher, url, {
      timeoutMs,
      headers: { 'User-Agent': 'LumaNest/1.0 ecology-context' },
    });
    const total = Number(body?.total_results);
    const observations = Array.isArray(body?.results) ? body.results : [];
    if (!Number.isInteger(total) || total <= 0 || observations.length === 0) {
      return noData(id, category, now, sourceInfo, '近九十日没有可用的研究级公开鸟类观察摘要');
    }
    const taxa = new Set(observations.map((item) => Number(item?.taxon?.id)).filter(Number.isInteger));
    const latest = observations
      .map((item) => iso(item?.time_observed_at ?? item?.observed_on))
      .filter(Boolean)
      .sort()
      .at(-1) ?? now.toISOString();
    return providerResult({
      id,
      category,
      status: 'ready',
      now,
      ttlMs: readyTtlMs,
      sourceInfo,
      signals: [signal({
        providerId: id,
        kind: 'recentCommunityBirdSummary',
        category,
        title: '近期公开社区观察',
        summary: `近九十日当前粗略范围有 ${total.toLocaleString('en-US')} 条研究级公开鸟类观察；最近返回样本涉及 ${taxa.size} 个分类单元。社区记录不代表动物当前仍在现场，也不用于推算出现概率或生成精确物种导航。`,
        verification: 'candidate',
        observedAt: latest,
        expiresAt: new Date(now.getTime() + 6 * 60 * 60 * 1_000),
        sourceUrl: sourceInfo.url,
        attributes: {
          observationCount: Math.min(total, 1_000),
          sampledTaxaCount: Math.min(taxa.size, 1_000),
          lookbackDays: 90,
        },
      })],
    });
  } catch {
    return unavailable(id, category, now);
  }
}
'''
replace_once(facts, "\nasync function ebirdProvider({ query, fetcher, timeoutMs, now, baseUrl, token }) {", f"\n{inat_function}\nasync function ebirdProvider({{ query, fetcher, timeoutMs, now, baseUrl, token }}) {{")
replace_once(
    facts,
    "    gbifBaseUrl = configuredUrl(process.env.LUMANEST_GBIF_BASE_URL) || 'https://api.gbif.org',\n    ebirdBaseUrl =",
    "    gbifBaseUrl = configuredUrl(process.env.LUMANEST_GBIF_BASE_URL) || 'https://api.gbif.org',\n    inaturalistBaseUrl = configuredUrl(process.env.LUMANEST_INATURALIST_BASE_URL) || 'https://api.inaturalist.org',\n    ebirdBaseUrl =",
)
replace_once(facts, "      gbifBaseUrl,\n      ebirdBaseUrl,", "      gbifBaseUrl,\n      inaturalistBaseUrl,\n      ebirdBaseUrl,")
replace_once(
    facts,
    "      gbif: () => gbifProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.gbifBaseUrl }),\n      ebird:",
    "      gbif: () => gbifProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.gbifBaseUrl }),\n      inaturalist: () => inaturalistProvider({ query, fetcher: this.fetcher, timeoutMs, now, baseUrl: configuration.inaturalistBaseUrl }),\n      ebird:",
)

runtime_test = 'services/lumanest-data-broker/test/provider-runtime-config.test.mjs'
replace_once(
    runtime_test,
    "  assert.equal(providerConfigured('ebird', configuration), true);",
    "  assert.equal(configuration.enabledProviders.includes('inaturalist'), true);\n  assert.equal(configuration.enabledProviders.includes('ebird'), false);\n  assert.equal(providerConfigured('inaturalist', configuration), true);\n  assert.equal(providerConfigured('ebird', configuration), false);\n\n  const explicitlyEnabled = validateProviderSources({\n    ...configuration,\n    enabledProviders: [...configuration.enabledProviders, 'ebird'],\n  });\n  assert.equal(providerConfigured('ebird', explicitlyEnabled), true);",
)

facts_test = 'services/lumanest-data-broker/test/provider-facts-service.test.mjs'
replace_once(
    facts_test,
    "test('provider query is bounded and rejects unknown sources', () => {",
    "test('default provider query keeps eBird optional and includes iNaturalist', () => {\n  const params = new URLSearchParams({ lat: '30.25', lon: '120.15' });\n  const parsed = validProviderFactsQuery(params, instant);\n  assert.equal(parsed.providerIds.includes('inaturalist'), true);\n  assert.equal(parsed.providerIds.includes('ebird'), false);\n});\n\ntest('provider query is bounded and rejects unknown sources', () => {",
)
replace_once(
    facts_test,
    "    if (url.hostname === 'gbif.test') return json({ count: 421 });\n    if (url.hostname === 'ebird.test')",
    "    if (url.hostname === 'gbif.test') return json({ count: 421 });\n    if (url.hostname === 'inaturalist.test') {\n      assert.equal(url.searchParams.get('taxon_id'), '3');\n      assert.equal(url.searchParams.get('quality_grade'), 'research');\n      assert.equal(url.searchParams.get('captive'), 'false');\n      assert.equal(url.searchParams.get('d1'), '2026-05-05');\n      return json({\n        total_results: 48,\n        results: [\n          { taxon: { id: 101 }, observed_on: '2026-08-02', user: { login: 'private' }, geojson: { coordinates: [120.1, 30.2] } },\n          { taxon: { id: 102 }, time_observed_at: '2026-08-03T06:30:00Z', photos: [{ url: 'https://example.invalid/photo.jpg' }] },\n        ],\n      });\n    }\n    if (url.hostname === 'ebird.test')",
)
replace_once(
    facts_test,
    "    gbifBaseUrl: 'https://gbif.test',\n    ebirdBaseUrl:",
    "    gbifBaseUrl: 'https://gbif.test',\n    inaturalistBaseUrl: 'https://inaturalist.test',\n    ebirdBaseUrl:",
)
replace_once(
    facts_test,
    "    commonsApiUrl: 'https://commons.dynamic', gbifBaseUrl: 'https://gbif.dynamic',\n    ebirdBaseUrl:",
    "    commonsApiUrl: 'https://commons.dynamic', gbifBaseUrl: 'https://gbif.dynamic',\n    inaturalistBaseUrl: 'https://inaturalist.dynamic',\n    ebirdBaseUrl:",
)

append_test = r'''

test('iNaturalist exposes bounded aggregate evidence without raw observation data', async () => {
  let requestedUrl;
  const service = new ProviderFactsService({
    now: () => instant,
    inaturalistBaseUrl: 'https://inaturalist.privacy',
    fetcher: async (input) => {
      requestedUrl = new URL(input);
      return json({
        total_results: 2750,
        results: [
          {
            id: 999,
            taxon: { id: 3, name: 'Aves' },
            observed_on: '2026-08-02',
            user: { login: 'observer-name' },
            geojson: { coordinates: [120.12345, 30.23456] },
            photos: [{ url: 'https://example.invalid/private-media.jpg' }],
            description: 'raw observer note',
          },
        ],
      });
    },
  });
  const result = await service.facts(query('inaturalist'));
  const provider = result.providers[0];
  const serialized = JSON.stringify(provider);
  assert.equal(provider.status, 'ready');
  assert.equal(provider.signals[0].verification, 'candidate');
  assert.deepEqual(provider.signals[0].attributes, {
    observationCount: 1000,
    sampledTaxaCount: 1,
    lookbackDays: 90,
  });
  assert.equal(serialized.includes('observer-name'), false);
  assert.equal(serialized.includes('120.12345'), false);
  assert.equal(serialized.includes('private-media'), false);
  assert.equal(serialized.includes('raw observer note'), false);
  assert.equal(provider.signals[0].sourceUrl.includes('lat='), false);
  assert.equal(requestedUrl.searchParams.get('taxon_id'), '3');
  assert.equal(requestedUrl.searchParams.get('quality_grade'), 'research');
});
'''
Path(facts_test).write_text(Path(facts_test).read_text(encoding='utf-8') + append_test, encoding='utf-8')

Path('docs/ecology-data-sources.md').write_text(r'''# 生态数据源与产品边界

栖光的生态信息服务于摄影与区域理解，不建设独立观鸟产品，也不把历史记录或社区投稿包装成实时出现概率。

## 数据源角色

- **GBIF**：默认启用，提供多年公开物种记录的历史基线；输出必须明确“历史记录不代表当前出现”。
- **iNaturalist**：默认启用，提供近九十日研究级公开鸟类观察的聚合信号；只保留观察数量、返回样本分类单元数量和证据时间。
- **eBird**：可选增强，默认关闭。只有后台显式启用且配置 API Token 后才调用；缺少 Token 不降低默认 Provider Hub 健康度。

## 隐私与安全

- 不向客户端或 AI 返回观察者身份、原始备注、媒体地址或单条观察坐标；
- 不尝试还原 iNaturalist 已模糊或隐藏的位置；
- 不把稀有或敏感物种记录转换成导航点、路线节点或打卡目标；
- 生态事实只进入现有自然特征、季节信号和摄影题材链；无可靠事实时整块隐藏；
- 所有措辞使用“历史记录”“近期公开社区观察”“观察条件参考”，禁止使用“出现概率”或保证现场可见。

## 运行与缓存

GBIF 使用长周期参考缓存；iNaturalist 使用较短缓存并限制为粗略范围、近九十日、研究级鸟类观察。两者失败均独立降级，不影响 Today、路线、地图和安全链。
''', encoding='utf-8')
