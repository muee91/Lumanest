import { parseSunsetBotResponse } from './sunsetbot_parser.mjs';

export function mapEventCode(eventType, dayOffset) {
  if (!['sunrise', 'sunset'].includes(eventType) || ![0, 1].includes(dayOffset)) return null;
  if (eventType === 'sunrise') return dayOffset === 0 ? 'rise_1' : 'rise_2';
  return dayOffset === 0 ? 'set_1' : 'set_2';
}

export class SunsetBotProvider {
  constructor({ client, metrics, circuitBreaker, logger = () => {} }) {
    this.client = client;
    this.metrics = metrics;
    this.circuitBreaker = circuitBreaker;
    this.logger = logger;
  }

  async fetchModel({ city, eventType, dayOffset, model, now }) {
    const eventCode = mapEventCode(eventType, dayOffset);
    if (eventCode == null || !['GFS', 'EC'].includes(model)) {
      return { model, status: 'invalid', parseStatus: 'invalid_request' };
    }
    if (!this.circuitBreaker.allow(now)) {
      this.metrics.increment('sunsetbot_circuit_open_total');
      return { model, status: 'circuit_open', parseStatus: 'circuit_open' };
    }
    const result = await this.client.fetchCity({ city, eventCode, model });
    this.metrics.increment('sunsetbot_request_total', result.attempts ?? 1);
    if ((result.attempts ?? 1) > 1) {
      this.metrics.increment('sunsetbot_request_failure_total', (result.attempts ?? 1) - 1);
    }
    this.metrics.observeDuration(result.durationMs);
    if (!result.ok) {
      this.metrics.increment('sunsetbot_request_failure_total');
      const status = ['not_found', 'rate_limited', 'timeout'].includes(result.error)
        ? result.error
        : 'upstream_error';
      if (status === 'not_found') this.circuitBreaker.success(now);
      else this.circuitBreaker.failure(now);
      this.logger({
        event: 'sunsetbot.request', requestCity: city, resolvedCity: city,
        eventCode, model, httpStatus: result.httpStatus, responseDurationMs: result.durationMs,
        cacheStatus: 'miss', providerStatus: status, parseStatus: 'not_parsed',
        qualityScore: null, aod: null, staleCache: false,
        circuitState: this.circuitBreaker.state(now),
      });
      return { model, status, parseStatus: result.error };
    }
    const parsed = parseSunsetBotResponse(result.body, { model });
    if (parsed.status === 'ok') {
      this.metrics.increment('sunsetbot_request_success_total');
      this.circuitBreaker.success(now);
    } else {
      this.metrics.increment(parsed.status === 'parse_error'
        ? 'sunsetbot_parse_error_total'
        : parsed.status === 'not_found'
          ? 'sunsetbot_city_not_found_total'
          : 'sunsetbot_request_failure_total');
      if (parsed.status === 'not_found' || parsed.status === 'invalid') {
        this.circuitBreaker.success(now);
      } else {
        this.circuitBreaker.failure(now);
      }
    }
    this.logger({
      event: 'sunsetbot.request', requestCity: city, resolvedCity: city,
      eventCode, model, httpStatus: result.httpStatus, responseDurationMs: result.durationMs,
      cacheStatus: 'miss', providerStatus: parsed.status, parseStatus: parsed.parseStatus,
      qualityScore: parsed.score ?? null, aod: parsed.aod ?? null, staleCache: false,
      circuitState: this.circuitBreaker.state(now),
    });
    return parsed;
  }
}
