const counterNames = Object.freeze([
  'sunsetbot_request_total',
  'sunsetbot_request_success_total',
  'sunsetbot_request_failure_total',
  'sunsetbot_cache_hit_total',
  'sunsetbot_negative_cache_hit_total',
  'sunsetbot_stale_cache_total',
  'sunsetbot_city_cache_hit_total',
  'sunsetbot_request_budget_exhausted_total',
  'sunsetbot_parse_error_total',
  'sunsetbot_event_date_mismatch_total',
  'sunsetbot_city_not_found_total',
  'sunsetbot_circuit_open_total',
]);

export class SkyOpportunityMetrics {
  constructor() {
    this.counters = Object.fromEntries(counterNames.map((name) => [name, 0]));
    this.durations = [];
    this.lastDisagreement = 0;
  }

  increment(name, amount = 1) {
    if (Object.hasOwn(this.counters, name)) this.counters[name] += amount;
  }

  observeDuration(milliseconds) {
    if (!Number.isFinite(milliseconds)) return;
    this.durations.push(Math.max(0, milliseconds));
    if (this.durations.length > 1_000) this.durations.shift();
  }

  observeDisagreement(value) {
    if (Number.isFinite(value)) this.lastDisagreement = Math.max(0, value);
  }

  percentile95() {
    if (this.durations.length === 0) return 0;
    const sorted = [...this.durations].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * .95) - 1)];
  }

  alerts() {
    const total = this.counters.sunsetbot_request_total;
    const successRate = total === 0 ? 1 : this.counters.sunsetbot_request_success_total / total;
    const parseRate = total === 0 ? 0 : this.counters.sunsetbot_parse_error_total / total;
    return {
      successRateLow: total >= 10 && successRate < .80,
      p95Slow: this.percentile95() > 8_000,
      parseFailureHigh: total >= 10 && parseRate > .05,
    };
  }

  toPrometheus() {
    const lines = counterNames.map((name) => `# TYPE ${name} counter\n${name} ${this.counters[name]}`);
    lines.push('# TYPE sunsetbot_request_duration_ms gauge');
    lines.push(`sunsetbot_request_duration_ms ${this.percentile95()}`);
    lines.push('# TYPE sunsetbot_model_disagreement gauge');
    lines.push(`sunsetbot_model_disagreement ${this.lastDisagreement}`);
    return `${lines.join('\n')}\n`;
  }
}
