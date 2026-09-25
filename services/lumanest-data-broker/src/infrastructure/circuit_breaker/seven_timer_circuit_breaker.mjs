import { apiErrorCodes } from '../../api/error-codes.mjs';

export class SevenTimerCircuitBreaker {
  constructor({ failureThreshold = 3, openSeconds = 1_800 } = {}) {
    this.failureThreshold = failureThreshold;
    this.openMilliseconds = openSeconds * 1_000;
    this.consecutiveFailures = 0;
    this.openedUntil = 0;
    this.probeInFlight = false;
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

  success() {
    this.consecutiveFailures = 0;
    this.openedUntil = 0;
    this.probeInFlight = false;
  }

  failure(now = new Date()) {
    this.consecutiveFailures += 1;
    if (this.probeInFlight || this.consecutiveFailures >= this.failureThreshold) {
      this.openedUntil = now.getTime() + this.openMilliseconds;
    }
    this.probeInFlight = false;
  }
}
