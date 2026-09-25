import { apiErrorCodes } from '../../api/error-codes.mjs';

export class SunsetBotCircuitBreaker {
  constructor({
    failureThreshold = 5,
    rollingWindowSeconds = 600,
    failureRateThreshold = .60,
    openSeconds = 900,
  } = {}) {
    this.failureThreshold = failureThreshold;
    this.rollingWindowMs = rollingWindowSeconds * 1_000;
    this.failureRateThreshold = failureRateThreshold;
    this.openMs = openSeconds * 1_000;
    this.events = [];
    this.consecutiveFailures = 0;
    this.openedUntil = 0;
    this.probeInFlight = false;
  }

  prune(now) {
    const cutoff = now.getTime() - this.rollingWindowMs;
    this.events = this.events.filter((entry) => entry.at >= cutoff).slice(-10);
  }

  state(now = new Date()) {
    if (this.openedUntil === 0) return 'closed';
    return now.getTime() < this.openedUntil ? 'open' : 'half_open';
  }

  allow(now = new Date()) {
    const state = this.state(now);
    if (state === 'closed') return true;
    if (state === 'open' || this.probeInFlight) return false;
    this.probeInFlight = true;
    return true;
  }

  success(now = new Date()) {
    this.prune(now);
    this.events.push({ at: now.getTime(), failed: false });
    this.consecutiveFailures = 0;
    if (this.state(now) === 'half_open' || this.probeInFlight) {
      this.openedUntil = 0;
      this.events = [];
    }
    this.probeInFlight = false;
  }

  failure(now = new Date()) {
    this.prune(now);
    this.events.push({ at: now.getTime(), failed: true });
    this.consecutiveFailures += 1;
    const recent = this.events.slice(-10);
    const rateOpens = recent.length === 10 &&
      recent.filter((entry) => entry.failed).length / recent.length >= this.failureRateThreshold;
    if (this.probeInFlight || this.consecutiveFailures >= this.failureThreshold || rateOpens) {
      this.openedUntil = now.getTime() + this.openMs;
    }
    this.probeInFlight = false;
  }
}
