const sectionIds = Object.freeze([
  'identity', 'orientation', 'photoThemes', 'happeningNow',
  'places', 'localTaste', 'etiquette', 'practical',
]);

const sectionLabels = Object.freeze({
  identity: '区域身份',
  orientation: '方向认知',
  photoThemes: '摄影题材',
  happeningNow: '正在发生',
  places: '地点线索',
  localTaste: '地方味道与人文',
  etiquette: '礼仪',
  practical: '出发前确认',
});

const insightTypesBySection = Object.freeze({
  happeningNow: new Set(['performance', 'event', 'market', 'seasonalSignal']),
  places: new Set(['architecture', 'naturalFeature', 'routeStop']),
  localTaste: new Set(['history', 'localStory', 'culturalPractice', 'localFood', 'specialty']),
  etiquette: new Set(['etiquette']),
  practical: new Set(['supply', 'openingStatus', 'regulation']),
});

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function nonNegative(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;
}

function ratio(numerator, denominator) {
  return denominator > 0 ? Number((numerator / denominator).toFixed(4)) : 0;
}

function average(total, count) {
  return count > 0 ? Math.round(total / count) : 0;
}

function usableStatus(status) {
  return ['ready', 'partial', 'refreshing'].includes(status);
}

function sectionHasValue(section, body) {
  if (!object(body)) return false;
  if (section === 'identity') return typeof body.identity?.summary === 'string' && body.identity.summary.trim().length > 0;
  if (section === 'orientation') return typeof body.orientation?.summary === 'string' && body.orientation.summary.trim().length > 0;
  if (section === 'photoThemes') return Array.isArray(body.photoThemes) && body.photoThemes.length > 0;
  const types = insightTypesBySection[section];
  return types != null && Array.isArray(body.insights) && body.insights.some((item) => types.has(item?.type));
}

function freshProviderStatus(item) {
  if (!item?.configured) return 'unconfigured';
  if (!item?.enabled) return 'disabled';
  return item.lastStatus ?? 'unknown';
}

function fixedCounter(keys) {
  return Object.fromEntries(keys.map((key) => [key, 0]));
}

export class OperationalObservability {
  constructor({ now = () => new Date() } = {}) {
    this.now = now;
    this.regionBrief = {
      requests: 0,
      automaticRequests: 0,
      manualRequests: 0,
      usable: 0,
      pending: 0,
      unavailable: 0,
      failed: 0,
      expansionUsable: 0,
      expansionWithValue: 0,
      latencyTotalMs: 0,
      latencySamples: 0,
      latencyMaximumMs: 0,
      cacheHits: 0,
      cacheMisses: 0,
      sectionsRequested: fixedCounter(sectionIds),
      sectionsHit: fixedCounter(sectionIds),
      verification: fixedCounter([
        'authoritative', 'corroborated', 'singleSource', 'candidate', 'conflicting',
      ]),
      sourceQuality: fixedCounter(['s', 'a', 'b', 'c']),
    };
    this.routeCorridor = {
      requests: 0,
      ready: 0,
      partial: 0,
      unavailable: 0,
      requestedSegments: 0,
      availableSegments: 0,
      parkingReference: 0,
      supplyReference: 0,
      photographyReference: 0,
      restrictionsPresent: 0,
      restrictionsNoneObserved: 0,
      restrictionsUnavailable: 0,
      authoritativeRestrictions: 0,
      verifiedEvidence: 0,
      referenceEvidence: 0,
    };
    this.assistant = {
      builds: 0,
      ready: 0,
      empty: 0,
      verifiedEvidence: 0,
      sourceBacked: 0,
      factTotal: 0,
      factIdTotal: 0,
      sourceTotal: 0,
      characterTotal: 0,
      components: {
        snapshot: fixedCounter(['ready', 'empty', 'unavailable', 'notApplicable']),
        route: fixedCounter(['ready', 'empty', 'unavailable', 'notApplicable']),
        regionBrief: fixedCounter(['ready', 'empty', 'unavailable', 'notApplicable']),
        providers: fixedCounter(['ready', 'empty', 'unavailable', 'notApplicable']),
      },
      limits: fixedCounter([
        'precise_location_excluded',
        'candidate_evidence_excluded',
        'missing_data_not_inferred',
        'safety_chain_separate',
      ]),
    };
  }

  recordRegionBrief({
    activationType = 'unknown',
    requestedSections = [],
    status = 'failed',
    body = null,
    latencyMs = 0,
    cacheStatus = null,
  } = {}) {
    const metrics = this.regionBrief;
    metrics.requests += 1;
    const manual = activationType === 'user_manual';
    if (manual) metrics.manualRequests += 1;
    else metrics.automaticRequests += 1;
    if (usableStatus(status)) metrics.usable += 1;
    else if (status === 'pending') metrics.pending += 1;
    else if (status === 'unavailable') metrics.unavailable += 1;
    else metrics.failed += 1;
    const boundedLatency = Math.min(120_000, Math.round(nonNegative(latencyMs)));
    metrics.latencyTotalMs += boundedLatency;
    metrics.latencySamples += 1;
    metrics.latencyMaximumMs = Math.max(metrics.latencyMaximumMs, boundedLatency);
    if (cacheStatus === 'hit' || cacheStatus === 'stale') metrics.cacheHits += 1;
    else if (cacheStatus === 'miss') metrics.cacheMisses += 1;
    const requested = [...new Set(
      Array.isArray(requestedSections)
        ? requestedSections.filter((section) => sectionIds.includes(section))
        : [],
    )];
    for (const section of requested) {
      metrics.sectionsRequested[section] += 1;
      if (sectionHasValue(section, body)) metrics.sectionsHit[section] += 1;
    }
    const insights = Array.isArray(body?.insights) ? body.insights : [];
    for (const insight of insights) {
      if (Object.hasOwn(metrics.verification, insight?.verification)) {
        metrics.verification[insight.verification] += 1;
      }
    }
    const sources = Array.isArray(body?.sources) ? body.sources : [];
    for (const source of sources) {
      const tier = typeof source?.qualityTier === 'string' ? source.qualityTier.toLowerCase() : '';
      if (Object.hasOwn(metrics.sourceQuality, tier)) metrics.sourceQuality[tier] += 1;
    }
    if (manual && usableStatus(status)) {
      metrics.expansionUsable += 1;
      const extended = requested.filter((section) =>
        !['identity', 'orientation', 'photoThemes', 'practical'].includes(section));
      if (extended.some((section) => sectionHasValue(section, body))) {
        metrics.expansionWithValue += 1;
      }
    }
  }

  recordAssistantContext(coverage) {
    if (!object(coverage)) return;
    const metrics = this.assistant;
    metrics.builds += 1;
    if (coverage.status === 'ready') metrics.ready += 1;
    else metrics.empty += 1;
    if (coverage.verifiedEvidence === true) metrics.verifiedEvidence += 1;
    if (nonNegative(coverage.sourceCount) > 0) metrics.sourceBacked += 1;
    metrics.factTotal += nonNegative(coverage.factCount);
    metrics.factIdTotal += nonNegative(coverage.factIdCount);
    metrics.sourceTotal += nonNegative(coverage.sourceCount);
    metrics.characterTotal += nonNegative(coverage.characterCount);
    for (const component of Object.keys(metrics.components)) {
      const status = coverage.components?.[component]?.status;
      const key = Object.hasOwn(metrics.components[component], status) ? status : 'unavailable';
      metrics.components[component][key] += 1;
    }
    for (const limit of Array.isArray(coverage.limits) ? coverage.limits : []) {
      if (Object.hasOwn(metrics.limits, limit)) metrics.limits[limit] += 1;
    }
  }

  recordRouteCorridor(corridor) {
    if (!object(corridor)) return;
    const metrics = this.routeCorridor;
    metrics.requests += 1;
    const status = ['full', 'partial', 'unavailable'].includes(corridor.coverage)
      ? corridor.coverage : 'unavailable';
    if (status === 'full') metrics.ready += 1;
    else if (status === 'partial') metrics.partial += 1;
    else metrics.unavailable += 1;
    metrics.requestedSegments += nonNegative(corridor.requestedSegments);
    metrics.availableSegments += nonNegative(corridor.availableSegments);
    for (const segment of Array.isArray(corridor.segments) ? corridor.segments : []) {
      if (segment?.facilities?.status === 'reference' && nonNegative(segment.facilities.parking) > 0) metrics.parkingReference += 1;
      const supply = ['fuel', 'food', 'water', 'toilets', 'shelter', 'restArea']
        .reduce((total, key) => total + nonNegative(segment?.facilities?.[key]), 0);
      if (segment?.facilities?.status === 'reference' && supply > 0) metrics.supplyReference += 1;
      if (segment?.photography?.status === 'reference') metrics.photographyReference += 1;
      if (segment?.restrictions?.status === 'present') {
        metrics.restrictionsPresent += 1;
        metrics.authoritativeRestrictions += 1;
      } else if (segment?.restrictions?.status === 'noneObserved') metrics.restrictionsNoneObserved += 1;
      else metrics.restrictionsUnavailable += 1;
      if (segment?.evidence?.status === 'verified') metrics.verifiedEvidence += 1;
      else if (segment?.evidence?.status === 'reference') metrics.referenceEvidence += 1;
    }
  }

  snapshot({ providerHealth = null } = {}) {
    const region = this.regionBrief;
    const assistant = this.assistant;
    const providers = Array.isArray(providerHealth?.providers) ? providerHealth.providers : [];
    const cacheHits = nonNegative(providerHealth?.cache?.hits);
    const cacheMisses = nonNegative(providerHealth?.cache?.misses);
    return Object.freeze({
      contractVersion: 1,
      checkedAt: this.now().toISOString(),
      privacy: Object.freeze({
        preciseCoordinatesStored: false,
        promptsStored: false,
        rawFactsStored: false,
        labels: 'fixed_enumerations_only',
        retention: 'process_lifetime',
      }),
      regionBrief: Object.freeze({
        requests: region.requests,
        usable: region.usable,
        usableRate: ratio(region.usable, region.requests),
        automaticRequests: region.automaticRequests,
        manualRequests: region.manualRequests,
        manualExpansionUsableRate: ratio(region.expansionUsable, region.manualRequests),
        manualExpansionValueRate: ratio(region.expansionWithValue, region.manualRequests),
        pending: region.pending,
        unavailable: region.unavailable,
        failed: region.failed,
        averageLatencyMs: average(region.latencyTotalMs, region.latencySamples),
        maximumLatencyMs: region.latencyMaximumMs,
        cacheHitRate: ratio(region.cacheHits, region.cacheHits + region.cacheMisses),
        verification: Object.freeze({ ...region.verification }),
        sourceQuality: Object.freeze({ ...region.sourceQuality }),
        sections: Object.freeze(sectionIds.map((id) => Object.freeze({
          id,
          label: sectionLabels[id],
          requested: region.sectionsRequested[id],
          hit: region.sectionsHit[id],
          hitRate: ratio(region.sectionsHit[id], region.sectionsRequested[id]),
        }))),
      }),
      routeCorridor: Object.freeze({
        requests: this.routeCorridor.requests,
        ready: this.routeCorridor.ready,
        partial: this.routeCorridor.partial,
        unavailable: this.routeCorridor.unavailable,
        usableRate: ratio(this.routeCorridor.ready + this.routeCorridor.partial, this.routeCorridor.requests),
        segmentCoverageRate: ratio(this.routeCorridor.availableSegments, this.routeCorridor.requestedSegments),
        parkingReferenceSegments: this.routeCorridor.parkingReference,
        supplyReferenceSegments: this.routeCorridor.supplyReference,
        photographyReferenceSegments: this.routeCorridor.photographyReference,
        restrictionsPresent: this.routeCorridor.restrictionsPresent,
        restrictionsNoneObserved: this.routeCorridor.restrictionsNoneObserved,
        restrictionsUnavailable: this.routeCorridor.restrictionsUnavailable,
        authoritativeRestrictions: this.routeCorridor.authoritativeRestrictions,
        verifiedEvidenceSegments: this.routeCorridor.verifiedEvidence,
        referenceEvidenceSegments: this.routeCorridor.referenceEvidence,
      }),
      assistantContext: Object.freeze({
        builds: assistant.builds,
        ready: assistant.ready,
        empty: assistant.empty,
        readyRate: ratio(assistant.ready, assistant.builds),
        verifiedEvidenceRate: ratio(assistant.verifiedEvidence, assistant.builds),
        sourceBackedRate: ratio(assistant.sourceBacked, assistant.builds),
        averageFactCount: Number((assistant.builds > 0 ? assistant.factTotal / assistant.builds : 0).toFixed(2)),
        averageFactIdCount: Number((assistant.builds > 0 ? assistant.factIdTotal / assistant.builds : 0).toFixed(2)),
        averageSourceCount: Number((assistant.builds > 0 ? assistant.sourceTotal / assistant.builds : 0).toFixed(2)),
        averageCharacterCount: Math.round(assistant.builds > 0 ? assistant.characterTotal / assistant.builds : 0),
        components: Object.freeze(Object.entries(assistant.components).map(([id, statuses]) => Object.freeze({
          id,
          ...statuses,
          readyRate: ratio(statuses.ready, assistant.builds),
        }))),
        limits: Object.freeze({ ...assistant.limits }),
      }),
      providers: Object.freeze({
        enabled: providerHealth?.enabled === true,
        total: providers.length,
        configured: providers.filter((item) => item.configured).length,
        enabledCount: providers.filter((item) => item.enabled).length,
        recentlyReady: providers.filter((item) => ['ready', 'noData'].includes(item.lastStatus)).length,
        recentlyUnavailable: providers.filter((item) => item.lastStatus === 'unavailable').length,
        neverChecked: providers.filter((item) => nonNegative(item.requestTotal) === 0).length,
        cacheHitRate: ratio(cacheHits, cacheHits + cacheMisses),
        rows: Object.freeze(providers.map((item) => Object.freeze({
          id: item.id,
          label: item.label ?? item.id,
          enabled: item.enabled === true,
          configured: item.configured === true,
          status: freshProviderStatus(item),
          requestTotal: nonNegative(item.requestTotal),
          readyTotal: nonNegative(item.readyTotal) + nonNegative(item.noDataTotal),
          unavailableTotal: nonNegative(item.unavailableTotal),
          lastLatencyMs: item.lastLatencyMs == null ? null : nonNegative(item.lastLatencyMs),
          lastSignalCount: nonNegative(item.lastSignalCount),
          lastSuccessAt: typeof item.lastSuccessAt === 'string' ? item.lastSuccessAt : null,
          lastFailureAt: typeof item.lastFailureAt === 'string' ? item.lastFailureAt : null,
          lastErrorCode: typeof item.lastErrorCode === 'string' ? item.lastErrorCode : null,
        }))),
      }),
    });
  }

  toPrometheus() {
    const region = this.regionBrief;
    const assistant = this.assistant;
    const route = this.routeCorridor;
    const lines = [
      `lumanest_route_corridor_requests_total ${route.requests}`,
      `lumanest_route_corridor_ready_total ${route.ready}`,
      `lumanest_route_corridor_partial_total ${route.partial}`,
      `lumanest_route_corridor_unavailable_total ${route.unavailable}`,
      `lumanest_route_corridor_requested_segments_total ${route.requestedSegments}`,
      `lumanest_route_corridor_available_segments_total ${route.availableSegments}`,
      `lumanest_route_corridor_authoritative_restrictions_total ${route.authoritativeRestrictions}`,
      `lumanest_region_brief_requests_total ${region.requests}`,
      `lumanest_region_brief_usable_total ${region.usable}`,
      `lumanest_region_brief_manual_requests_total ${region.manualRequests}`,
      `lumanest_region_brief_manual_value_total ${region.expansionWithValue}`,
      `lumanest_region_brief_latency_ms_sum ${region.latencyTotalMs}`,
      `lumanest_region_brief_latency_ms_max ${region.latencyMaximumMs}`,
      `lumanest_assistant_context_builds_total ${assistant.builds}`,
      `lumanest_assistant_context_ready_total ${assistant.ready}`,
      `lumanest_assistant_context_empty_total ${assistant.empty}`,
      `lumanest_assistant_context_verified_total ${assistant.verifiedEvidence}`,
    ];
    for (const section of sectionIds) {
      lines.push(`lumanest_region_brief_section_requested_total{section="${section}"} ${region.sectionsRequested[section]}`);
      lines.push(`lumanest_region_brief_section_hit_total{section="${section}"} ${region.sectionsHit[section]}`);
    }
    for (const [component, statuses] of Object.entries(assistant.components)) {
      lines.push(`lumanest_assistant_context_component_ready_total{component="${component}"} ${statuses.ready}`);
      lines.push(`lumanest_assistant_context_component_unavailable_total{component="${component}"} ${statuses.unavailable}`);
    }
    return `${lines.join('\n')}\n`;
  }
}

export const operationalSectionIds = sectionIds;
