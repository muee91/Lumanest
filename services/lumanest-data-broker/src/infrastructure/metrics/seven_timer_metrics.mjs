const productNames = Object.freeze(['astro', 'meteo', 'two']);
const counterNames = Object.freeze([
  'requestTotal', 'requestSuccess', 'requestFailure', 'cacheHit', 'staleFallback',
  'circuitOpen', 'manualTestTotal', 'manualTestRejected', 'diagnosticsPersistFailure',
]);

function emptyCounters() {
  return Object.fromEntries(counterNames.map((name) => [name, 0]));
}

export class SevenTimerMetrics {
  constructor() {
    this.products = Object.fromEntries(productNames.map((product) => [product, {
      counters: emptyCounters(), durations: [], inFlight: 0,
    }]));
  }

  increment(product, name, amount = 1) {
    const entry = this.products[product];
    if (entry != null && Object.hasOwn(entry.counters, name)) entry.counters[name] += amount;
  }

  begin(product) {
    const entry = this.products[product];
    if (entry != null) entry.inFlight += 1;
  }

  end(product, milliseconds) {
    const entry = this.products[product];
    if (entry == null) return;
    entry.inFlight = Math.max(0, entry.inFlight - 1);
    if (!Number.isFinite(milliseconds)) return;
    entry.durations.push(Math.max(0, Math.round(milliseconds)));
    if (entry.durations.length > 1_000) entry.durations.shift();
  }

  percentile95(product) {
    const values = this.products[product]?.durations ?? [];
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * .95) - 1)];
  }

  snapshot() {
    return {
      inFlight: productNames.reduce((sum, product) => sum + this.products[product].inFlight, 0),
      products: productNames.map((product) => ({
        product,
        ...this.products[product].counters,
        inFlight: this.products[product].inFlight,
        p95LatencyMs: this.percentile95(product),
      })),
    };
  }

  toPrometheus() {
    const metricNames = {
      requestTotal: 'seven_timer_request_total', requestSuccess: 'seven_timer_request_success_total',
      requestFailure: 'seven_timer_request_failure_total', cacheHit: 'seven_timer_cache_hit_total',
      staleFallback: 'seven_timer_stale_fallback_total', circuitOpen: 'seven_timer_circuit_open_total',
      manualTestTotal: 'seven_timer_manual_test_total', manualTestRejected: 'seven_timer_manual_test_rejected_total',
      diagnosticsPersistFailure: 'seven_timer_diagnostics_persist_failure_total',
    };
    const lines = [];
    for (const [counter, metric] of Object.entries(metricNames)) {
      lines.push(`# TYPE ${metric} counter`);
      for (const product of productNames) lines.push(`${metric}{product="${product}"} ${this.products[product].counters[counter]}`);
    }
    lines.push('# TYPE seven_timer_request_in_flight gauge');
    lines.push('# TYPE seven_timer_request_duration_p95_ms gauge');
    for (const product of productNames) {
      lines.push(`seven_timer_request_in_flight{product="${product}"} ${this.products[product].inFlight}`);
      lines.push(`seven_timer_request_duration_p95_ms{product="${product}"} ${this.percentile95(product)}`);
    }
    return `${lines.join('\n')}\n`;
  }
}
