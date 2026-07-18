import assert from 'node:assert/strict';
import test from 'node:test';

import { MemorySkyOpportunityCache } from '../src/infrastructure/cache/sky_opportunity_cache.mjs';
import { SunsetBotCircuitBreaker } from '../src/infrastructure/circuit_breaker/sunsetbot_circuit_breaker.mjs';
import { SkyOpportunityService } from '../src/domain/sky_opportunity/sky_opportunity_service.mjs';

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function amap() {
  return json({
    status: '1',
    regeocode: { addressComponent: { province: '浙江省', city: '杭州市', district: '西湖区' } },
  });
}

function providerBody(score, eventCode = 'set_1') {
  const eventDay = eventCode.endsWith('_2') ? '2026-07-19' : '2026-07-18';
  return {
    status: 'ok',
    tb_event_time: `${eventDay} 18:59:55`,
    tb_quality: `${score}<br>（中烧）`,
    tb_aod: '0.244<br>（还不错）',
  };
}

test('daily requests both models, then 90 minute cache prevents provider calls', async () => {
  let providerCalls = 0;
  let amapCalls = 0;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') {
        amapCalls += 1;
        return amap();
      }
      providerCalls += 1;
      return json(providerBody(
        url.searchParams.get('model') === 'GFS' ? .291 : .429,
        url.searchParams.get('event'),
      ));
    },
    now: () => new Date('2026-07-18T09:10:00Z'),
    queryId: () => 8372145,
  });
  const query = {
    latitude: 30.2741,
    longitude: 120.1551,
    locale: 'zh-CN',
    focus: 'next',
  };
  const first = await service.daily(query);
  assert.equal(first.todaySunset.data.summary.level, 'moderate');
  assert.equal('score' in first.todaySunset.data.summary, false);
  assert.equal(first.tomorrowSunrise.status, 'ok');
  assert.equal(first.tomorrowSunset.status, 'unavailable');
  assert.equal(providerCalls, 4);
  await service.daily(query);
  assert.equal(providerCalls, 4);
  assert.equal(amapCalls, 1);
});

test('pre-sunrise focus keeps the bounded batch centred on today sunrise', async () => {
  let providerCalls = 0;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      providerCalls += 1;
      return json(providerBody(.4, url.searchParams.get('event')));
    },
    now: () => new Date('2026-07-18T09:10:00Z'),
  });

  const value = await service.daily({
    latitude: 30.2741,
    longitude: 120.1551,
    locale: 'zh-CN',
    focus: 'preSunrise',
  });

  assert.equal(value.todaySunrise.status, 'ok');
  assert.equal(value.todaySunset.status, 'ok');
  assert.equal(value.tomorrowSunrise.status, 'unavailable');
  assert.equal(providerCalls, 4);
});

test('an explicitly enabled tomorrow sunset performs its own bounded fetch', async () => {
  let providerCalls = 0;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    settings: () => ({ skyOpportunityTomorrowSunsetEnabled: true }),
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      providerCalls += 1;
      return json(providerBody(.4, url.searchParams.get('event')));
    },
    now: () => new Date('2026-07-18T09:10:00Z'),
  });

  const value = await service.daily({ latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN' });
  assert.equal(value.tomorrowSunset.status, 'ok');
  assert.equal(providerCalls, 6);
});

test('unsupported-city results are negatively cached without retaining exact coordinates', async () => {
  let amapCalls = 0;
  let providerCalls = 0;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    settings: () => ({ sunsetbotMaxAttempts: 1 }),
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') {
        amapCalls += 1;
        return amap();
      }
      providerCalls += 1;
      return json({ status: 'not_found' });
    },
    now: () => new Date('2026-07-18T09:10:00Z'),
  });
  const query = { latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN' };

  await service.daily(query);
  await service.daily(query);

  assert.equal(amapCalls, 1);
  assert.equal(providerCalls, 4);
});

test('same cache key coalesces concurrent provider requests', async () => {
  let providerCalls = 0;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      providerCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 20));
      return json(providerBody(.4));
    },
    now: () => new Date('2026-07-18T09:10:00Z'),
  });
  const config = service.config();
  const request = { city: '杭州', eventType: 'sunset', dayOffset: 0, model: 'GFS', config };
  const [left, right] = await Promise.all([service.model(request), service.model(request)]);
  assert.equal(providerCalls, 1);
  assert.equal(left.score, .4);
  assert.equal(right.score, .4);
});

test('three hour cache returns stale data when refresh fails and lowers confidence', async () => {
  let instant = new Date('2026-07-18T09:10:00Z');
  let available = true;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    cache: new MemorySkyOpportunityCache(),
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      return available ? json(providerBody(.5)) : json({ error: 'down' }, 503);
    },
    now: () => instant,
    settings: () => ({ sunsetbotMaxAttempts: 1 }),
  });
  const query = {
    latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN', eventType: 'sunset', dayOffset: 0,
  };
  const fresh = await service.forecast(query);
  assert.equal(fresh.data.freshness.isStale, false);
  instant = new Date(instant.getTime() + 3 * 60 * 60 * 1_000);
  available = false;
  const stale = await service.forecast(query);
  assert.equal(stale.status, 'ok');
  assert.equal(stale.data.freshness.isStale, true);
  assert.equal(stale.data.summary.confidence, 'medium');
});

test('cache older than six hours is never returned', async () => {
  let instant = new Date('2026-07-18T09:10:00Z');
  let available = true;
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      return available ? json(providerBody(.5)) : json({ error: 'down' }, 503);
    },
    now: () => instant,
    settings: () => ({ sunsetbotMaxAttempts: 1 }),
  });
  const query = {
    latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN', eventType: 'sunset', dayOffset: 0,
  };
  await service.forecast(query);
  instant = new Date(instant.getTime() + 7 * 60 * 60 * 1_000);
  available = false;
  assert.equal((await service.forecast(query)).status, 'unavailable');
});

test('circuit opens after five consecutive failures and permits one half-open probe', () => {
  const breaker = new SunsetBotCircuitBreaker({ failureThreshold: 5, openSeconds: 900 });
  const now = new Date('2026-07-18T09:10:00Z');
  for (let index = 0; index < 5; index += 1) breaker.failure(now);
  assert.equal(breaker.state(now), 'open');
  assert.equal(breaker.allow(now), false);
  const later = new Date(now.getTime() + 901 * 1_000);
  assert.equal(breaker.allow(later), true);
  assert.equal(breaker.allow(later), false);
  breaker.success(later);
  assert.equal(breaker.state(later), 'closed');
});

test('unsupported city stays silent and never fabricates a score', async () => {
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => url.hostname === 'restapi.amap.com'
      ? amap()
      : json({ status: 'not_found' }),
    now: () => new Date('2026-07-18T09:10:00Z'),
    settings: () => ({ sunsetbotMaxAttempts: 1 }),
  });
  const value = await service.forecast({
    latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN', eventType: 'sunset', dayOffset: 0,
  });
  assert.equal(value.status, 'unavailable');
  assert.equal(value.data, null);
  assert.equal(value.locationUnsupported, true);
});

test('a provider result for the wrong local date never becomes a next-day opportunity', async () => {
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => url.hostname === 'restapi.amap.com'
      ? amap()
      : json(providerBody(.8, 'set_1')),
    now: () => new Date('2026-07-18T09:10:00Z'),
  });
  const value = await service.forecast({
    latitude: 30.2741,
    longitude: 120.1551,
    locale: 'zh-CN',
    eventType: 'sunset',
    dayOffset: 1,
  });
  assert.equal(value.status, 'unavailable');
});

test('a relative event cache never crosses the Shanghai day boundary', async () => {
  let instant = new Date('2026-07-18T15:30:00Z'); // 23:30 in Shanghai
  let providerCalls = 0;
  const eventDate = () => new Date(instant.getTime() + 32 * 60 * 60 * 1_000)
    .toISOString()
    .slice(0, 10);
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => {
      if (url.hostname === 'restapi.amap.com') return amap();
      providerCalls += 1;
      return json({
        ...providerBody(.6, 'set_2'),
        tb_event_time: `${eventDate()} 18:59:55`,
      });
    },
    now: () => instant,
  });
  const query = {
    latitude: 30.2741,
    longitude: 120.1551,
    locale: 'zh-CN',
    eventType: 'sunset',
    dayOffset: 1,
  };

  assert.equal((await service.forecast(query)).status, 'ok');
  instant = new Date('2026-07-18T16:15:00Z'); // 00:15 in Shanghai
  assert.equal((await service.forecast(query)).status, 'ok');
  assert.equal(providerCalls, 4);
});

test('missed event and remote feature flag never reserve a proactive card', async () => {
  const service = new SkyOpportunityService({
    amapWebKey: () => 'amap-key',
    fetcher: async (url) => url.hostname === 'restapi.amap.com'
      ? amap()
      : json(providerBody(.8)),
    now: () => new Date('2026-07-18T13:00:00Z'),
  });
  const query = {
    latitude: 30.2741, longitude: 120.1551, locale: 'zh-CN', eventType: 'sunset', dayOffset: 0,
  };
  const missed = await service.forecast(query);
  assert.equal(missed.data.presentation.proactiveEligible, false);

  let calls = 0;
  const disabled = new SkyOpportunityService({
    settings: () => ({ sunsetbotProviderEnabled: false }),
    fetcher: async () => { calls += 1; throw new Error('must not call'); },
  });
  assert.equal((await disabled.forecast(query)).status, 'unavailable');
  assert.equal(calls, 0);
});
