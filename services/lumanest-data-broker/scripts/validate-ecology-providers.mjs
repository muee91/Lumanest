#!/usr/bin/env node
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
