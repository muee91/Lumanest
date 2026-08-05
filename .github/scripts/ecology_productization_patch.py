from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:120]!r}')
    target.write_text(text.replace(old, new), encoding='utf-8')


providers_js = 'services/lumanest-data-broker/src/admin/public/providers.js'
replace_once(
    providers_js,
    "    'gbifBaseUrl',\n    'ebirdBaseUrl',",
    "    'gbifBaseUrl',\n    'inaturalistBaseUrl',\n    'ebirdBaseUrl',",
)
replace_once(
    providers_js,
    "        detail.textContent = `${success} · 最近 ${latency} · 信号 ${item.lastSignalCount ?? 0}`;",
    "        const runs = item.requestTotal ?? 0;\n        const ready = item.readyTotal ?? 0;\n        const noData = item.noDataTotal ?? 0;\n        const unavailable = item.unavailableTotal ?? 0;\n        const unconfigured = item.unconfiguredTotal ?? 0;\n        const outcomes = runs === 0\n          ? '尚未运行'\n          : `运行 ${runs} · 就绪 ${ready} · 无数据 ${noData} · 不可用 ${unavailable} · 未配置 ${unconfigured}`;\n        detail.textContent = `${success} · 最近 ${latency} · ${outcomes} · 信号 ${item.lastSignalCount ?? 0}`;",
)

index_html = 'services/lumanest-data-broker/src/admin/public/index.html'
replace_once(
    index_html,
    "                  <label>GBIF<input name=\"gbifBaseUrl\" type=\"url\" maxlength=\"2048\" required></label>\n                  <label>eBird<input name=\"ebirdBaseUrl\" type=\"url\" maxlength=\"2048\" required></label>\n                  <label>eBird Token<input name=\"ebirdToken\" type=\"password\" autocomplete=\"new-password\" placeholder=\"留空表示不修改\"><small data-provider-mask=\"ebirdToken\"></small></label>",
    "                  <label>GBIF 历史生态记录<input name=\"gbifBaseUrl\" type=\"url\" maxlength=\"2048\" required><small>默认启用，用于多年公开物种记录的区域基线。</small></label>\n                  <label>iNaturalist 近期自然观察<input name=\"inaturalistBaseUrl\" type=\"url\" maxlength=\"2048\" required><small>默认启用，只输出近九十日研究级鸟类观察的聚合信号。</small></label>\n                  <label>eBird（可选）<input name=\"ebirdBaseUrl\" type=\"url\" maxlength=\"2048\" required><small>默认关闭；只有显式启用并配置 Token 后才参与增强。</small></label>\n                  <label>eBird Token（可选）<input name=\"ebirdToken\" type=\"password\" autocomplete=\"new-password\" placeholder=\"留空表示不修改\"><small data-provider-mask=\"ebirdToken\"></small><small>缺失不会影响默认 Provider Hub 健康度。</small></label>",
)

provider_service = 'services/lumanest-data-broker/src/environment/provider-facts-service.mjs'
replace_once(
    provider_service,
    "      lines.push(`lumanest_provider_ready_total{provider=\"${id}\"} ${metric.readyTotal}`);\n      lines.push(`lumanest_provider_unavailable_total{provider=\"${id}\"} ${metric.unavailableTotal}`);\n      lines.push(`lumanest_provider_last_latency_ms{provider=\"${id}\"} ${metric.lastLatencyMs ?? 0}`);",
    "      lines.push(`lumanest_provider_ready_total{provider=\"${id}\"} ${metric.readyTotal}`);\n      lines.push(`lumanest_provider_no_data_total{provider=\"${id}\"} ${metric.noDataTotal}`);\n      lines.push(`lumanest_provider_unavailable_total{provider=\"${id}\"} ${metric.unavailableTotal}`);\n      lines.push(`lumanest_provider_unconfigured_total{provider=\"${id}\"} ${metric.unconfiguredTotal}`);\n      lines.push(`lumanest_provider_last_latency_ms{provider=\"${id}\"} ${metric.lastLatencyMs ?? 0}`);\n      lines.push(`lumanest_provider_last_signal_count{provider=\"${id}\"} ${metric.lastSignalCount}`);",
)
replace_once(
    provider_service,
    "    lines.push(`lumanest_provider_cache_hits_total ${this.cacheMetrics.hits}`);\n    lines.push(`lumanest_provider_cache_misses_total ${this.cacheMetrics.misses}`);",
    "    lines.push(`lumanest_provider_cache_hits_total ${this.cacheMetrics.hits}`);\n    lines.push(`lumanest_provider_cache_misses_total ${this.cacheMetrics.misses}`);\n    lines.push(`lumanest_provider_cache_coalesced_total ${this.cacheMetrics.coalesced}`);",
)

sheet = 'lib/src/presentation_v2/explore/v2_provider_facts_sheet.dart'
text = Path(sheet).read_text(encoding='utf-8')
text = text.replace('查看环境与地区数据', '查看环境与地区线索')
text = text.replace("'环境与地区数据'", "'环境与地区线索'")
if text.count('_displaySignalTitle(signal)') != 0:
    raise SystemExit('provider facts sheet already productized')
if text.count('signal.title') != 2 or text.count('signal.summary') != 2:
    raise SystemExit('provider facts sheet signal anchors changed')
text = text.replace('signal.title', '_displaySignalTitle(signal)')
text = text.replace('signal.summary', '_displaySignalSummary(signal)')
text = text.replace(
    "  'gbif' => 'GBIF 生态记录',\n  'ebird' => 'eBird 近期观测',",
    "  'gbif' => 'GBIF 历史生态记录',\n  'inaturalist' => 'iNaturalist 近期观察',\n  'ebird' => 'eBird 近期观测（可选）',",
)
helper_anchor = "String _time(DateTime value) {"
helpers = """bool _isEcologySignal(ProviderSignal signal) => const {
  'historicalOccurrenceInventory',
  'recentCommunityBirdSummary',
}.contains(signal.kind);

String _displaySignalTitle(ProviderSignal signal) => switch (signal.kind) {
  'historicalOccurrenceInventory' => '历史生态记录',
  'recentCommunityBirdSummary' => '近期自然观察',
  _ => signal.title,
};

String _displaySignalSummary(ProviderSignal signal) {
  if (!_isEcologySignal(signal)) return signal.summary;
  if (signal.kind == 'recentCommunityBirdSummary') {
    return '${signal.summary} 适合作为自然题材与环境理解参考。';
  }
  return '${signal.summary} 适合作为季节与区域题材参考。';
}

"""
if text.count(helper_anchor) != 1:
    raise SystemExit('provider facts helper anchor changed')
Path(sheet).write_text(text.replace(helper_anchor, helpers + helper_anchor), encoding='utf-8')

sheet_test = 'test/presentation_v2/explore/v2_provider_facts_sheet_test.dart'
test_text = Path(sheet_test).read_text(encoding='utf-8')
insert_anchor = "}\n\nMap<String, Object?> _body"
new_test = r'''

  testWidgets('ecology signals use photography-oriented wording without reserving another module', (
    tester,
  ) async {
    final bundle = ProviderFactsBundle.fromJson(
      _body(providers: [_ecologyProvider()]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: V2ProviderFactsSummaryCard(
              bundle: bundle,
              onTap: () => showV2ProviderFactsSheet(context, bundle),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('近期自然观察'), findsOneWidget);
    expect(find.textContaining('自然题材与环境理解参考'), findsOneWidget);
    expect(find.textContaining('近期公开社区观察'), findsNothing);

    await tester.tap(find.byKey(const Key('v2-provider-facts-summary')));
    await tester.pumpAndSettle();

    expect(find.text('iNaturalist 近期观察'), findsOneWidget);
    expect(find.textContaining('不代表动物当前仍在现场'), findsOneWidget);
    expect(find.byKey(const Key('v2-provider-state-inaturalist')), findsOneWidget);
  });
'''
if test_text.count(insert_anchor) != 1:
    raise SystemExit('provider facts widget test anchor changed')
test_text = test_text.replace(insert_anchor, new_test + insert_anchor)
test_text += r'''

Map<String, Object?> _ecologyProvider() {
  final now = DateTime.now().toUtc();
  return {
    'id': 'inaturalist',
    'category': 'wildlife',
    'status': 'ready',
    'observedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    'expiresAt': now.add(const Duration(hours: 4)).toIso8601String(),
    'source': {
      'id': 'inaturalist-observations-api',
      'title': 'iNaturalist Observations API',
      'publisher': 'iNaturalist community',
      'url': 'https://www.inaturalist.org/pages/api+reference',
      'license': 'Observation-specific licences; aggregate metadata only',
      'version': 'v1',
    },
    'signals': [
      {
        'id': 'signal_222222222222222222222222',
        'kind': 'recentCommunityBirdSummary',
        'category': 'wildlife',
        'title': '近期公开社区观察',
        'summary': '近九十日当前粗略范围有 48 条研究级公开鸟类观察；社区记录不代表动物当前仍在现场。',
        'verification': 'candidate',
        'observedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'expiresAt': now.add(const Duration(hours: 4)).toIso8601String(),
        'sourceUrl': 'https://www.inaturalist.org/pages/api+reference',
      },
    ],
    'message': null,
  };
}
'''
Path(sheet_test).write_text(test_text, encoding='utf-8')

package = 'services/lumanest-data-broker/package.json'
replace_once(
    package,
    '    "test": "node --test",\n    "build:sky-calibration":',
    '    "test": "node --test",\n    "validate:ecology": "node scripts/validate-ecology-providers.mjs",\n    "build:sky-calibration":',
)

Path('services/lumanest-data-broker/scripts/validate-ecology-providers.mjs').write_text(r'''#!/usr/bin/env node
import { pathToFileURL } from 'node:url';

import { ProviderFactsService } from '../src/environment/provider-facts-service.mjs';

export const ecologyValidationScenarios = Object.freeze([
  Object.freeze({ id: 'hangzhou-west-lake', label: '杭州西湖', latitude: 30.2500, longitude: 120.1450, radiusKm: 20 }),
  Object.freeze({ id: 'hangzhou-xixi', label: '杭州西溪湿地', latitude: 30.2740, longitude: 120.0610, radiusKm: 20 }),
  Object.freeze({ id: 'delingha', label: '德令哈', latitude: 37.3700, longitude: 97.3600, radiusKm: 30 }),
  Object.freeze({ id: 'qinghai-lake', label: '青海湖', latitude: 36.9000, longitude: 100.1800, radiusKm: 35 }),
  Object.freeze({ id: 'ili-valley', label: '伊犁河谷', latitude: 43.9000, longitude: 81.3200, radiusKm: 30 }),
  Object.freeze({ id: 'lhasa-valley', label: '拉萨河谷', latitude: 29.6500, longitude: 91.1200, radiusKm: 25 }),
]);

const ecologyProviders = Object.freeze(['gbif', 'inaturalist']);
const validStatuses = new Set(['ready', 'noData', 'unavailable', 'unconfigured']);
const allowedKinds = new Map([
  ['gbif', new Set(['historicalOccurrenceInventory'])],
  ['inaturalist', new Set(['recentCommunityBirdSummary'])],
]);
const forbiddenSignalKeys = new Set([
  'user', 'login', 'observer', 'geojson', 'coordinates', 'photos', 'photo',
  'media', 'description', 'place_guess', 'private_location', 'results', 'observations',
]);

function finiteNumber(value, fallback, minimum, maximum) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum ? parsed : fallback;
}

function assertNoForbiddenKeys(value, path = 'signal') {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoForbiddenKeys(item, `${path}[${index}]`));
    return;
  }
  if (value == null || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (forbiddenSignalKeys.has(key.toLowerCase())) {
      throw new Error(`privacy_violation:${path}.${key}`);
    }
    assertNoForbiddenKeys(child, `${path}.${key}`);
  }
}

export function assertEcologyResponse(result) {
  if (result == null || result.contractVersion !== 1 || !Array.isArray(result.providers)) {
    throw new Error('invalid_ecology_contract');
  }
  const ids = result.providers.map((provider) => provider?.id);
  if (ids.includes('ebird') || ids.length !== ecologyProviders.length ||
      !ecologyProviders.every((id) => ids.includes(id))) {
    throw new Error('unexpected_ecology_provider_set');
  }
  for (const provider of result.providers) {
    if (!validStatuses.has(provider.status) || !Array.isArray(provider.signals)) {
      throw new Error(`invalid_provider_state:${provider.id ?? 'unknown'}`);
    }
    if (provider.status !== 'ready' && provider.signals.length > 0) {
      throw new Error(`inactive_provider_exposes_signals:${provider.id}`);
    }
    for (const signal of provider.signals) {
      if (!allowedKinds.get(provider.id)?.has(signal.kind)) {
        throw new Error(`unexpected_ecology_signal:${provider.id}:${signal.kind ?? 'unknown'}`);
      }
      assertNoForbiddenKeys(signal);
      const sourceUrl = new URL(signal.sourceUrl);
      if (sourceUrl.search.length > 0 || sourceUrl.hash.length > 0) {
        throw new Error(`location_bearing_source_url:${provider.id}`);
      }
    }
  }
  return result;
}

export function evaluateEcologyReachability(results, minimumReachableRatio = 0.5) {
  const summary = Object.fromEntries(ecologyProviders.map((id) => [id, {
    ready: 0,
    noData: 0,
    unavailable: 0,
    unconfigured: 0,
    reachable: 0,
    total: results.length,
  }]));
  for (const result of results) {
    for (const provider of result.providers) {
      const item = summary[provider.id];
      item[provider.status] += 1;
      if (provider.status === 'ready' || provider.status === 'noData') item.reachable += 1;
    }
  }
  const failures = ecologyProviders.filter((id) => {
    const item = summary[id];
    return item.total === 0 || item.reachable / item.total < minimumReachableRatio;
  });
  return { ok: failures.length === 0, failures, providers: summary };
}

export async function runEcologyValidation({
  service = new ProviderFactsService({
    timeoutMs: finiteNumber(process.env.ECOLOGY_VALIDATION_TIMEOUT_MS, 10_000, 2_000, 30_000),
  }),
  scenarios = ecologyValidationScenarios,
  minimumReachableRatio = finiteNumber(process.env.ECOLOGY_MIN_REACHABLE_RATIO, 0.5, 0, 1),
  now = () => new Date(),
} = {}) {
  const results = [];
  const scenariosReport = [];
  for (const scenario of scenarios) {
    const observedAt = now().toISOString();
    const result = assertEcologyResponse(await service.facts({
      latitude: scenario.latitude,
      longitude: scenario.longitude,
      radiusKm: scenario.radiusKm,
      locale: 'zh-CN',
      observedAt,
      providerIds: [...ecologyProviders],
    }));
    results.push(result);
    scenariosReport.push({
      id: scenario.id,
      label: scenario.label,
      status: result.status,
      cacheStatus: result.cacheStatus,
      providers: Object.fromEntries(result.providers.map((provider) => [provider.id, {
        status: provider.status,
        signalCount: provider.signals.length,
      }])),
    });
  }
  const reachability = evaluateEcologyReachability(results, minimumReachableRatio);
  return {
    contractVersion: 1,
    generatedAt: now().toISOString(),
    scenarioCount: scenarios.length,
    minimumReachableRatio,
    ok: reachability.ok,
    failures: reachability.failures,
    providers: reachability.providers,
    scenarios: scenariosReport,
    privacy: {
      coordinatesPrinted: false,
      observerDataPrinted: false,
      mediaPrinted: false,
    },
  };
}

async function main() {
  const report = await runEcologyValidation();
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.ok) process.exitCode = 2;
}

const invokedDirectly = process.argv[1] != null &&
  import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
  main().catch((error) => {
    process.stderr.write(`生态场景验收失败：${error.message}\n`);
    process.exitCode = 1;
  });
}
''', encoding='utf-8')

Path('services/lumanest-data-broker/test/ecology-scenario-validator.test.mjs').write_text(r'''import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertEcologyResponse,
  evaluateEcologyReachability,
  runEcologyValidation,
} from '../scripts/validate-ecology-providers.mjs';

const instant = new Date('2026-08-06T00:00:00.000Z');

function response({ gbif = 'ready', inaturalist = 'noData', leak = null } = {}) {
  const provider = (id, status, kind) => ({
    id,
    category: 'wildlife',
    status,
    observedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
    source: status === 'ready' ? {
      id: `${id}-source`, title: id, publisher: id,
      url: `https://${id}.example/reference`, license: 'open', version: 'v1',
    } : null,
    signals: status === 'ready' ? [{
      id: `${id}-signal`, kind, category: 'wildlife', title: id,
      summary: 'bounded aggregate only', verification: 'reference',
      observedAt: instant.toISOString(),
      expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
      sourceUrl: `https://${id}.example/reference`,
      ...(leak == null ? {} : leak),
    }] : [],
    message: status === 'ready' ? null : 'bounded state',
  });
  return {
    contractVersion: 1,
    requestedCoordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    radiusKm: 20,
    generatedAt: instant.toISOString(),
    expiresAt: new Date(instant.getTime() + 60_000).toISOString(),
    status: gbif === 'ready' || inaturalist === 'ready' ? 'partial' : 'unavailable',
    cacheStatus: 'miss',
    providers: [
      provider('gbif', gbif, 'historicalOccurrenceInventory'),
      provider('inaturalist', inaturalist, 'recentCommunityBirdSummary'),
    ],
  };
}

test('scenario validator reports only aggregate provider outcomes', async () => {
  const queries = [];
  const service = {
    facts: async (query) => {
      queries.push(query);
      return response();
    },
  };
  const report = await runEcologyValidation({
    service,
    scenarios: [
      { id: 'a', label: '场景 A', latitude: 30.1, longitude: 120.1, radiusKm: 20 },
      { id: 'b', label: '场景 B', latitude: 37.3, longitude: 97.3, radiusKm: 30 },
    ],
    now: () => instant,
  });
  assert.equal(report.ok, true);
  assert.deepEqual(queries.map((item) => item.providerIds), [
    ['gbif', 'inaturalist'],
    ['gbif', 'inaturalist'],
  ]);
  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('latitude'), false);
  assert.equal(serialized.includes('longitude'), false);
  assert.equal(serialized.includes('30.1'), false);
  assert.equal(report.privacy.coordinatesPrinted, false);
});

test('scenario validator rejects leaked observation payloads', () => {
  assert.throws(
    () => assertEcologyResponse(response({ leak: { geojson: { coordinates: [120.1, 30.2] } } })),
    /privacy_violation/,
  );
});

test('reachability gate distinguishes no-data from upstream failure', () => {
  const healthy = evaluateEcologyReachability([
    response({ gbif: 'ready', inaturalist: 'noData' }),
    response({ gbif: 'noData', inaturalist: 'ready' }),
  ], 0.5);
  assert.equal(healthy.ok, true);

  const failed = evaluateEcologyReachability([
    response({ gbif: 'unavailable', inaturalist: 'ready' }),
    response({ gbif: 'unavailable', inaturalist: 'noData' }),
  ], 0.5);
  assert.equal(failed.ok, false);
  assert.deepEqual(failed.failures, ['gbif']);
});
''', encoding='utf-8')

Path('services/lumanest-data-broker/test/provider-observability.test.mjs').write_text(r'''import assert from 'node:assert/strict';
import test from 'node:test';

import { ProviderFactsService } from '../src/environment/provider-facts-service.mjs';

const instant = new Date('2026-08-06T00:00:00.000Z');
const json = (body) => new Response(JSON.stringify(body), {
  status: 200,
  headers: { 'Content-Type': 'application/json' },
});
const query = (providerId, latitude) => ({
  latitude,
  longitude: 120.15,
  radiusKm: 20,
  locale: 'zh-CN',
  observedAt: instant.toISOString(),
  providerIds: [providerId],
});

test('provider health and Prometheus distinguish ready, no-data and unavailable outcomes', async () => {
  let inaturalistCalls = 0;
  const service = new ProviderFactsService({
    now: () => instant,
    gbifBaseUrl: 'https://gbif.test',
    inaturalistBaseUrl: 'https://inaturalist.test',
    fetcher: async (input) => {
      const url = new URL(input);
      if (url.hostname === 'gbif.test') return json({ count: 7 });
      if (url.hostname === 'inaturalist.test') {
        inaturalistCalls += 1;
        if (inaturalistCalls === 1) return json({ total_results: 0, results: [] });
        throw new Error('upstream down');
      }
      throw new Error(`unexpected host ${url.hostname}`);
    },
  });

  await service.facts(query('gbif', 30.25));
  await service.facts(query('inaturalist', 30.25));
  await service.facts(query('inaturalist', 30.35));

  const health = service.healthSnapshot();
  const gbif = health.providers.find((item) => item.id === 'gbif');
  const inaturalist = health.providers.find((item) => item.id === 'inaturalist');
  assert.equal(gbif.readyTotal, 1);
  assert.equal(inaturalist.noDataTotal, 1);
  assert.equal(inaturalist.unavailableTotal, 1);
  assert.equal(inaturalist.requestTotal, 2);

  const metrics = service.toPrometheus();
  assert.match(metrics, /lumanest_provider_ready_total\{provider="gbif"\} 1/);
  assert.match(metrics, /lumanest_provider_no_data_total\{provider="inaturalist"\} 1/);
  assert.match(metrics, /lumanest_provider_unavailable_total\{provider="inaturalist"\} 1/);
  assert.match(metrics, /lumanest_provider_unconfigured_total\{provider="inaturalist"\} 0/);
  assert.match(metrics, /lumanest_provider_cache_coalesced_total 0/);
});
''', encoding='utf-8')

Path('services/lumanest-data-broker/test/admin-provider-ecology-console.test.mjs').write_text(r'''import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const publicRoot = new URL('../src/admin/public/', import.meta.url);

test('provider console exposes ecology roles and outcome counters', async () => {
  const [html, script] = await Promise.all([
    readFile(new URL('index.html', publicRoot), 'utf8'),
    readFile(new URL('providers.js', publicRoot), 'utf8'),
  ]);
  assert.match(html, /name="inaturalistBaseUrl"/);
  assert.match(html, /iNaturalist 近期自然观察/);
  assert.match(html, /eBird（可选）/);
  assert.match(html, /缺失不会影响默认 Provider Hub 健康度/);
  assert.match(script, /'inaturalistBaseUrl'/);
  assert.match(script, /item\.readyTotal/);
  assert.match(script, /item\.noDataTotal/);
  assert.match(script, /item\.unavailableTotal/);
  assert.match(script, /item\.unconfiguredTotal/);
});
''', encoding='utf-8')
