import assert from 'node:assert/strict';
import test from 'node:test';

import { OperationalObservability } from '../src/infrastructure/metrics/operational_observability.mjs';

test('operational observability aggregates only bounded coverage metadata', () => {
  const metrics = new OperationalObservability({
    now: () => new Date('2026-08-05T04:00:00Z'),
  });
  metrics.recordRegionBrief({
    activationType: 'user_manual',
    requestedSections: ['identity', 'happeningNow', 'localTaste'],
    status: 'ready',
    latencyMs: 1250,
    cacheStatus: 'miss',
    body: {
      identity: { summary: 'A region' },
      insights: [
        { type: 'event', verification: 'corroborated' },
        { type: 'localFood', verification: 'singleSource' },
      ],
      sources: [{ qualityTier: 's' }, { qualityTier: 'a' }],
    },
  });
  metrics.recordAssistantContext({
    status: 'ready',
    verifiedEvidence: true,
    factCount: 5,
    factIdCount: 3,
    sourceCount: 2,
    characterCount: 480,
    components: {
      snapshot: { status: 'ready' },
      route: { status: 'notApplicable' },
      regionBrief: { status: 'ready' },
      providers: { status: 'unavailable' },
    },
    limits: [
      'precise_location_excluded',
      'candidate_evidence_excluded',
      'missing_data_not_inferred',
    ],
  });
  const value = metrics.snapshot({
    providerHealth: {
      enabled: true,
      cache: { hits: 3, misses: 1 },
      providers: [{
        id: 'cams', label: 'CAMS', enabled: true, configured: true,
        requestTotal: 2, readyTotal: 1, noDataTotal: 0,
        unavailableTotal: 1, lastStatus: 'ready', lastLatencyMs: 210,
        lastSignalCount: 2, lastSuccessAt: '2026-08-05T03:59:00Z',
      }],
    },
  });
  assert.equal(value.regionBrief.manualExpansionValueRate, 1);
  assert.equal(value.regionBrief.sections.find((item) => item.id === 'happeningNow').hitRate, 1);
  assert.equal(value.assistantContext.verifiedEvidenceRate, 1);
  assert.equal(value.providers.cacheHitRate, 0.75);
  assert.equal(value.privacy.preciseCoordinatesStored, false);
  assert.equal(value.privacy.promptsStored, false);
  assert.doesNotMatch(JSON.stringify(value), /A region|30\.2|120\.1|where should I go/i);
  assert.match(metrics.toPrometheus(), /lumanest_assistant_context_ready_total 1/);
});
