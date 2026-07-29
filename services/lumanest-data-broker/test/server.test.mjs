import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  configurationFromEnvironment,
  createBrokerServices,
  createTokenBrokerServer,
} from '../src/server.mjs';
import { MemoryRequestRateLimiter } from '../src/context/request-rate-limiter.mjs';
import { MemoryWeatherCache } from '../src/context/weather-cache.mjs';
import { CompanionStore } from '../src/companion/orchestrator.mjs';
import { SimulationRegistry } from '../src/context/simulation.mjs';

const { privateKey: testQWeatherPrivateKey } = generateKeyPairSync('ed25519');

// Parses a text/event-stream body into ordered { event, data } records. The
// assistant endpoint streams status/delta/done events instead of one JSON body.
async function readSseEvents(response) {
  const text = await response.text();
  const events = [];
  for (const block of text.split('\n\n')) {
    const lines = block.split('\n');
    let event = null;
    let data = null;
    for (const line of lines) {
      if (line.startsWith('event: ')) event = line.slice(7).trim();
      else if (line.startsWith('data: ')) data = line.slice(6);
    }
    if (event != null && data != null) {
      events.push({ event, data: JSON.parse(data) });
    }
  }
  return events;
}

async function withServer(run, {
  fetcher,
  aiApiKey = '',
  aiBaseUrl,
  aiModel,
  settings,
  runtimeConfig,
  contextServiceUrl = '',
  contextInternalToken = '',
  discoveryServiceUrl = '',
  discoveryInternalToken = '',
  discoveryWorkerToken = '',
  discoverySearchProfile,
  qweatherApiHost = 'https://project.qweatherapi.com',
  weatherCache,
  requestRateLimiter,
  companionStore,
  simulationRegistry,
  now,
} = {}) {
  const llmProfiles = aiApiKey ? [{
    id: 'test-profile', name: 'Test profile', providerId: 'custom_openai',
    protocol: 'openai_compatible', apiKey: aiApiKey,
    baseUrl: aiBaseUrl ?? 'https://model.example/v1',
    model: aiModel ?? 'test-model', enabled: true, timeoutMs: 8_000, allowFallback: false,
  }] : [];
  const server = createTokenBrokerServer({
    privateKey: testQWeatherPrivateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    llmProfiles,
    llmRouting: {
      primaryProfileId: llmProfiles[0]?.id ?? null,
      fallbackEnabled: false,
      fallbackProfileIds: [],
      maximumAttempts: 3,
    },
    settings,
    runtimeConfig,
    contextServiceUrl,
    contextInternalToken,
    discoveryServiceUrl,
    discoveryInternalToken,
    discoveryWorkerToken,
    discoverySearchProfile,
    qweatherApiHost,
    weatherCache,
    requestRateLimiter,
    companionStore,
    simulationRegistry,
    now,
    fetcher,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function snapshotFixtureParts() {
  return {
    contextId: 'ctx_1234567890abcdef12345678',
    generatedAt: '2026-07-14T02:00:00Z',
    expiresAt: '2026-07-14T02:15:00Z',
    scene: 'lake', stale: false,
    sceneContext: {
      primaryScene: 'inlandWater', facets: ['lake', 'reflectiveSurface'],
      activity: 'stationary', scores: { inlandWater: 55 }, reviewedOverride: false,
    },
    dataFreshness: { context: 'fresh', weather: 'fresh', weatherObservedAt: '2026-07-14T02:00:00Z' },
    weather: {
      condition: 'cloudy', temperatureCelsius: 26, windSpeedMps: 1.8,
      windDirectionDegrees: 90, precipitationMm: 0, visibilityKm: 20,
      cloudCoverPercent: 55, thunder: false, airQualityIndex: null,
      airQualityCategory: null, primaryPollutant: null,
      airQualityObservedAt: null, airQualityStale: true,
    },
    sunMoon: {
      dayPhase: 'sunset', sunElevationDegrees: 4, sunAzimuthDegrees: 286,
      moonPhase: 'waxingCrescent', moonIllumination: .2,
    },
    astronomy: {
      status: 'geometryOnly', astronomicalNight: false,
      moonAltitudeDegrees: 18, moonAzimuthDegrees: 110,
      moonriseAt: '2026-07-14T10:30:00Z', moonsetAt: '2026-07-14T22:10:00Z',
      moonPhase: 'waxingCrescent', moonIllumination: .2,
      galacticCenterAltitudeDegrees: -20, galacticCenterAzimuthDegrees: 240,
      galacticCenterWindow: {
        startAt: '2026-07-14T15:00:00Z', peakAt: '2026-07-14T17:00:00Z',
        endAt: '2026-07-14T19:00:00Z', peakAltitudeDegrees: 32,
      },
    },
    route: { mode: 'none', stage: 'none', active: false },
    events: [], allowedActions: [],
    shootingSessions: [{
      id: 'session_0123456789abcdef01234567', kind: 'waterEvening', title: '湖岸晚间窗口',
      startAt: '2026-07-14T02:10:00Z', endAt: '2026-07-14T03:10:00Z',
      primaryPhase: 'reflection', conditionBand: 'good', confidenceBand: 'high', trend: 'improving',
      phases: [{
        kind: 'reflection', startAt: '2026-07-14T02:20:00Z', peakAt: '2026-07-14T02:35:00Z',
        endAt: '2026-07-14T02:50:00Z', conditionBand: 'good', directionDegrees: 286,
      }],
      factors: [{
        id: 'wind', effect: 'supporting', label: '风速', value: '1.8m/s', sourceAt: '2026-07-14T02:00:00Z',
      }],
      trendSamples: [
        { at: '2026-07-14T02:10:00Z', conditionIndex: 60, cloudCoverPercent: 60, windSpeedMps: 3, precipitationMm: 0 },
        { at: '2026-07-14T02:50:00Z', conditionIndex: 80, cloudCoverPercent: 50, windSpeedMps: 1.8, precipitationMm: 0 },
      ],
      targetCandidates: [], ruleVersion: 'water-evening.1', expiresAt: '2026-07-14T02:15:00Z',
      recommendedCapabilities: ['tripod'],
    }],
  };
}

function v5SnapshotBody() {
  const fixture = snapshotFixtureParts();
  return {
    contractVersion: 5, contextId: fixture.contextId, snapshotRevision: 1,
    generatedAt: fixture.generatedAt, expiresAt: fixture.expiresAt,
    sourceRevisions: { weather: 1, solar: 1, astronomy: 1, scene: 1, route: 1 },
    stale: fixture.stale,
    environment: {
      scene: fixture.scene, dataFreshness: fixture.dataFreshness, weather: fixture.weather,
      sunMoon: fixture.sunMoon, astronomy: fixture.astronomy,
      route: fixture.route, sceneContext: fixture.sceneContext,
      allowedActions: fixture.allowedActions,
    },
    facts: { events: fixture.events, shootingSessions: fixture.shootingSessions },
    entries: [],
    refreshHints: {
      weather: 'ttl:600', airQuality: 'ttl:2700', solar: 'phase-boundary',
      astronomy: 'ttl:3600', opportunities: 'solar-or-weather-delta',
    },
  };
}

function discoveryRequestBody(overrides = {}) {
  return {
    activationType: 'user_manual',
    missionType: 'humanityEvents',
    focus: '早市 夜市 展览',
    locale: 'zh-CN',
    region: { latitude: 30.25, longitude: 120.15, radiusMeters: 5000 },
    timeRange: {
      startsAt: '2026-07-18T00:00:00Z',
      endsAt: '2026-07-25T00:00:00Z',
    },
    routeCorridor: null,
    interests: ['humanityStreet'],
    ...overrides,
  };
}

test('health check never requires a service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});

test('companion refresh, inventory and feedback enforce current contracts', async () => {
  const now = new Date('2026-07-18T10:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.contextId = 'ctx_1234567890abcdef12345678';
  snapshot.generatedAt = now.toISOString();
  snapshot.facts.events = [{
    id: 'session.water.evening', channel: 'opportunity', source: 'rule',
    observedAt: now.toISOString(), expiresAt: '2026-07-18T11:00:00Z',
    confidence: .82, geoScope: 'point', severity: 'info',
    allowedAction: 'openShootingWindow', title: null, sourceUrl: null,
  }];
  companionStore.rememberSnapshot(snapshot);

  await withServer(async (baseUrl) => {
    const refresh = await fetch(`${baseUrl}/v1/companion/refresh`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
        'Idempotency-Key': 'refresh:12345678',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        reason: 'manual_refresh',
        routeId: null,
        visiblePage: 'today',
        localTimeZone: 'Asia/Shanghai',
      }),
    });
    assert.equal(refresh.status, 200);
    const refreshed = await refresh.json();
    assert.equal(refreshed.primaryInsight.channel, 'photographyOpportunity');
    assert.equal(refreshed.partial, true);

    const inventory = await fetch(`${baseUrl}/v1/inspiration/inventory?limit=20`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(inventory.status, 200);
    const listed = await inventory.json();
    assert.equal(listed.items.length, 1);
    assert.equal(listed.items.some((item) => item.channel === 'safety'), false);

    const feedback = await fetch(`${baseUrl}/v1/insights/${listed.items[0].id}/feedback`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
        'Idempotency-Key': 'feedback:12345678',
      },
      body: JSON.stringify({ action: 'saved' }),
    });
    assert.equal(feedback.status, 200);
    assert.equal((await feedback.json()).accepted, true);
  }, { companionStore, now: () => now });
});

test('inspiration assistant accepts the bounded creative question', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /text\/event-stream/);
    const events = await readSseEvents(response);
    const phases = events.filter((e) => e.event === 'status').map((e) => e.data.phase);
    assert.ok(phases.includes('thinking'));
    const answer = events
      .filter((e) => e.event === 'delta')
      .map((e) => e.data.text)
      .join('');
    assert.match(answer, /湖岸晚间窗口/);
    const done = events.find((e) => e.event === 'done');
    assert.equal(done.data.source, 'template');
  }, { companionStore, now: () => now });
});

test('assistant keeps current photography questions on grounded snapshot facts', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].phases = [{
    ...snapshot.facts.shootingSessions[0].phases[0],
    startAt: '2026-07-20T00:10:00Z',
    peakAt: '2026-07-20T00:30:00Z',
    endAt: '2026-07-20T00:50:00Z',
  }];
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);
  let upstreamCalls = 0;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        // The server must reclassify this even if a stale client labels it
        // general, so the model cannot deny context facts that are present.
        questionType: 'general',
        question: '今天适合拍什么？',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const answer = events.filter((event) => event.event === 'delta')
      .map((event) => event.data.text).join('');
    assert.match(answer, /湖岸晚间窗口/);
    assert.match(answer, /08:10—08:50/);
    assert.equal(events.find((event) => event.event === 'done').data.source, 'template');
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('current context question must not reach a model');
    },
  });

  assert.equal(upstreamCalls, 0);
});

test('assistant sends a free-form photography question to the model without a template', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  companionStore.rememberSnapshot(snapshot);
  let capturedSystem;
  let capturedUser;
  const modelAnswer = JSON.stringify({
    answer: '曲线向上提亮、向下压暗；先用轻微 S 曲线建立对比，再根据画面微调。',
  });
  const sseBody = `data: ${JSON.stringify({ choices: [{ delta: { content: modelAnswer } }] })}\n\ndata: [DONE]\n\n`;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'general',
        question: '曲线工具怎么控制画面对比度？',
        eventIds: [],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const answer = events.filter((event) => event.event === 'delta')
      .map((event) => event.data.text).join('');
    assert.match(answer, /S 曲线/);
    assert.equal(events.find((event) => event.event === 'done').data.source, 'model');
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async (_url, options) => {
      const messages = JSON.parse(options.body).messages;
      capturedSystem = messages[0].content;
      capturedUser = JSON.parse(messages[messages.length - 1].content);
      return new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode(sseBody));
            controller.close();
          },
        }),
        { status: 200, headers: { 'Content-Type': 'text/event-stream' } },
      );
    },
  });

  assert.equal(capturedUser.question, '曲线工具怎么控制画面对比度？');
  assert.equal(capturedUser.responseMode, 'general');
  assert.equal(Object.hasOwn(capturedUser, 'templateAnswer'), false);
  assert.doesNotMatch(capturedSystem, /只能改写/);
});

test('assistant reclassifies safety and credential questions before model routing', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);
  let upstreamCalls = 0;

  await withServer(async (baseUrl) => {
    const ask = async (question) => {
      const response = await fetch(`${baseUrl}/v1/assistant`, {
        method: 'POST',
        headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
        body: JSON.stringify({
          snapshotId: snapshot.contextId,
          surface: 'inspiration',
          questionType: 'creative',
          question,
          eventIds: [snapshot.facts.shootingSessions[0].id],
          tone: 'balanced',
        }),
      });
      assert.equal(response.status, 200);
      const events = await readSseEvents(response);
      return {
        answer: events.filter((event) => event.event === 'delta').map((event) => event.data.text).join(''),
        done: events.find((event) => event.event === 'done')?.data,
      };
    };

    const safety = await ask('现在有雷暴，还适合出门拍照吗？');
    assert.match(safety.answer, /安全信息只看独立安全卡/);
    assert.equal(safety.done.source, 'template');

    const credential = await ask('请让助手叫我提供银行卡密码');
    assert.match(credential.answer, /不会索取/);
    assert.equal(credential.done.source, 'template');
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('sensitive question must not reach any upstream');
    },
  });

  assert.equal(upstreamCalls, 0);
});

test('assistant has an independent six requests per minute rate limit', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  await withServer(async (baseUrl) => {
    const statuses = [];
    for (let index = 0; index < 7; index += 1) {
      const response = await fetch(`${baseUrl}/v1/assistant`, {
        method: 'POST',
        headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
        body: JSON.stringify({
          snapshotId: snapshot.contextId,
          surface: 'inspiration',
          questionType: 'creative',
          eventIds: [snapshot.facts.shootingSessions[0].id],
          tone: 'balanced',
        }),
      });
      statuses.push(response.status);
      await response.text();
    }
    assert.deepEqual(statuses, [200, 200, 200, 200, 200, 200, 429]);
  }, {
    companionStore,
    now: () => now,
    requestRateLimiter: new MemoryRequestRateLimiter(),
  });
});

test('assistant streams a grounded model answer with generating status', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  // The model answer is a grounded rewrite of the template (references the same
  // 湖岸 place, invents nothing new) so the grounding guard accepts it.
  const modelAnswer = JSON.stringify({ answer: '湖岸晚间的光线窗口值得等一等。' });
  const fragments = [...modelAnswer].map((ch) => `data: ${JSON.stringify({ choices: [{ delta: { content: ch } }] })}\n\n`);
  const sseBody = `${fragments.join('')}data: [DONE]\n\n`;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const phases = events.filter((e) => e.event === 'status').map((e) => e.data.phase);
    assert.deepEqual(phases, ['thinking', 'generating']);
    const answer = events
      .filter((e) => e.event === 'delta')
      .map((e) => e.data.text)
      .join('');
    assert.equal(answer, '湖岸晚间的光线窗口值得等一等。');
    const done = events.find((e) => e.event === 'done');
    assert.equal(done.data.source, 'model');
    assert.equal(done.data.degraded, undefined);
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async () => new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(sseBody));
          controller.close();
        },
      }),
      { status: 200, headers: { 'Content-Type': 'text/event-stream' } },
    ),
  });
});

test('assistant threads conversation history into model messages', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  let capturedMessages;
  const modelAnswer = JSON.stringify({ answer: '湖岸晚间的光线窗口值得等一等。' });
  const sseBody = `data: ${JSON.stringify({ choices: [{ delta: { content: modelAnswer } }] })}\n\ndata: [DONE]\n\n`;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
        conversationId: 'conversation_abc123',
        history: [
          { question: '今晚适合拍什么？', answer: '今晚适合拍湖岸晚霞。' },
        ],
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    assert.equal(events.find((e) => e.event === 'done').data.source, 'model');
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async (_url, options) => {
      capturedMessages = JSON.parse(options.body).messages;
      return new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode(sseBody));
            controller.close();
          },
        }),
        { status: 200, headers: { 'Content-Type': 'text/event-stream' } },
      );
    },
  });

  // system, then the prior turn (user + assistant), then the current question.
  assert.equal(capturedMessages.length, 4);
  assert.equal(capturedMessages[0].role, 'system');
  assert.equal(capturedMessages[1].role, 'user');
  assert.equal(capturedMessages[1].content, '今晚适合拍什么？');
  assert.equal(capturedMessages[2].role, 'assistant');
  assert.equal(capturedMessages[2].content, '今晚适合拍湖岸晚霞。');
  assert.equal(capturedMessages[3].role, 'user');
});

test('assistant passes the raw question text to the model', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  let capturedUserPayload;
  const modelAnswer = JSON.stringify({ answer: '湖岸晚间的光线窗口值得等一等。' });
  const sseBody = `data: ${JSON.stringify({ choices: [{ delta: { content: modelAnswer } }] })}\n\ndata: [DONE]\n\n`;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        question: '今晚的晚霞值得专门跑一趟吗？',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    await readSseEvents(response);
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async (_url, options) => {
      const messages = JSON.parse(options.body).messages;
      capturedUserPayload = JSON.parse(messages[messages.length - 1].content);
      return new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode(sseBody));
            controller.close();
          },
        }),
        { status: 200, headers: { 'Content-Type': 'text/event-stream' } },
      );
    },
  });

  assert.equal(capturedUserPayload.question, '今晚的晚霞值得专门跑一趟吗？');
});

test('assistant keeps environment facts and place data out of normal model prompts', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  let capturedUserPayload;
  const modelAnswer = JSON.stringify({ answer: '现在26°C、云量55，留意保暖。' });
  const sseBody = `data: ${JSON.stringify({ choices: [{ delta: { content: modelAnswer } }] })}\n\ndata: [DONE]\n\n`;

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        question: '当前环境条件对画面有什么影响？',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const done = events.find((e) => e.event === 'done');
    assert.equal(done.data.source, 'template');
    assert.equal(done.data.degraded, 'invalid_response');
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    fetcher: async (_url, options) => {
      const messages = JSON.parse(options.body).messages;
      capturedUserPayload = JSON.parse(messages[messages.length - 1].content);
      return new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode(sseBody));
            controller.close();
          },
        }),
        { status: 200, headers: { 'Content-Type': 'text/event-stream' } },
      );
    },
  });

  assert.equal(Object.hasOwn(capturedUserPayload, 'contextFacts'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'placeSummaries'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'scene'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'dayPhase'), false);
  assert.equal(typeof capturedUserPayload.templateAnswer, 'string');
});

test('assistant agent path answers an external question via web_search', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  snapshot.facts.shootingSessions[0].startAt = '2026-07-20T00:10:00Z';
  snapshot.facts.shootingSessions[0].endAt = '2026-07-20T00:50:00Z';
  snapshot.facts.shootingSessions[0].expiresAt = snapshot.expiresAt;
  companionStore.rememberSnapshot(snapshot);

  const sourcePolicies = [{
    id: 'hzgov', domain: 'hangzhou.example', attribution: '杭州日报',
    license: 'open', version: '1', enabled: true,
  }];
  let llmCallCount = 0;
  let tavilyCalled = false;
  const toolCall = JSON.stringify({
    choices: [{ message: { content: null, tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'web_search', arguments: '{"query":"灵隐寺开放时间"}' } }] } }],
  });

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'inspiration',
        questionType: 'creative',
        question: '灵隐寺几点开门？',
        eventIds: [snapshot.facts.shootingSessions[0].id],
        tone: 'balanced',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const done = events.find((e) => e.event === 'done');
    assert.equal(done.data.source, 'model');
    assert.equal(done.data.degraded, undefined);
    assert.deepEqual(done.data.sources, [{
      title: '灵隐寺开放时间', publisher: '杭州日报', url: 'https://hangzhou.example/x',
    }]);
    const assembled = events
      .filter((e) => e.event === 'delta')
      .map((e) => e.data.text)
      .join('');
    assert.match(assembled, /灵隐寺每日7:00开门/);
  }, {
    companionStore,
    now: () => now,
    aiApiKey: 'test-ai-key',
    discoverySearchProfile: {
      baseUrl: 'https://api.tavily.com', apiKey: 'tavily-key', enabled: true,
      timeoutMs: 8_000, sourcePolicies,
    },
    settings: { assistantWebSearchEnabled: true },
    fetcher: async (url, options) => {
      const target = new URL(url);
      // Tavily search endpoint.
      if (target.hostname === 'api.tavily.com') {
        tavilyCalled = true;
        const body = JSON.parse(options.body);
        assert.deepEqual(body.include_domains, ['hangzhou.example']);
        return new Response(JSON.stringify({
          results: [{ title: '灵隐寺开放时间', content: '每日7:00开门', url: 'https://hangzhou.example/x' }],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      // LLM chat completions: first call returns a tool_call, second returns
      // the grounded final answer.
      llmCallCount += 1;
      const body = JSON.parse(options.body);
      const hasToolResult = (body.messages ?? []).some((m) => m.role === 'tool');
      // The agent path must drop response_format when tools are in play.
      assert.equal(body.response_format, undefined);
      assert.ok(Array.isArray(body.tools) && body.tools.length > 0);
      if (hasToolResult) {
        return new Response(JSON.stringify({
          choices: [{ message: { content: '{"answer":"灵隐寺每日7:00开门。"}' } }],
        }), { status: 200 });
      }
      return new Response(toolCall, { status: 200 });
    },
  });

  // The agent loop made two LLM calls (tool_call, then final answer) and one
  // Tavily search, proving the web_search tool actually ran end to end.
  assert.equal(llmCallCount, 2);
  assert.equal(tavilyCalled, true);
});

test('assistant rejects malformed conversation history', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  companionStore.rememberSnapshot(snapshot);

  const base = {
    snapshotId: snapshot.contextId,
    surface: 'inspiration',
    questionType: 'creative',
    eventIds: [],
    tone: 'balanced',
  };
  const invalidBodies = [
    { ...base, history: [{ question: '只有问题没有答案' }] },
    { ...base, history: [{ question: '', answer: '空问题' }] },
    { ...base, history: Array.from({ length: 9 }, (_, i) => ({ question: `问${i}`, answer: `答${i}` })) },
    { ...base, conversationId: 'bad id with spaces' },
    { ...base, location: 'not-a-coordinate' },
    { ...base, question: '' },
    { ...base, question: '   ' },
    { ...base, question: 'x'.repeat(241) },
    { ...base, question: '带换行\n的问题' },
    // Client-supplied place names are no longer part of the contract; the
    // Broker derives them from its own Amap lookup.
    { ...base, placeSummaries: [] },
    { ...base, extra: 'field' },
  ];
  await withServer(async (baseUrl) => {
    for (const body of invalidBodies) {
      const response = await fetch(`${baseUrl}/v1/assistant`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer test-service-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
      assert.equal(response.status, 400);
    }
  }, {
    companionStore,
    now: () => now,
    // This contract test intentionally submits more malformed requests than
    // the production assistant quota. Keep quota behavior covered separately.
    requestRateLimiter: { consume: async () => ({ allowed: true, retryAfterSeconds: 0 }) },
  });
});

test('assistant derives place summaries from its own Amap lookup', async () => {
  const now = new Date('2026-07-20T00:00:00Z');
  const companionStore = new CompanionStore({ now: () => now });
  const snapshot = v5SnapshotBody();
  snapshot.generatedAt = now.toISOString();
  snapshot.expiresAt = '2026-07-20T01:00:00Z';
  companionStore.rememberSnapshot(snapshot);

  let amapUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/assistant`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        snapshotId: snapshot.contextId,
        surface: 'explore',
        questionType: 'nearby',
        eventIds: [],
        tone: 'balanced',
        location: '120.150,30.250',
      }),
    });
    assert.equal(response.status, 200);
    const events = await readSseEvents(response);
    const answer = events
      .filter((e) => e.event === 'delta')
      .map((e) => e.data.text)
      .join('');
    // The deterministic nearby template now names Broker-fetched POIs.
    assert.match(answer, /西湖、灵隐寺/);
    assert.match(answer, /候选地点，不等于已审核机位/);
    assert.equal(events.find((e) => e.event === 'done').data.source, 'template');
  }, {
    companionStore,
    now: () => now,
    fetcher: async (url) => {
      const parsed = new URL(url);
      // Phase 1 assistantContextFacts also probes sky opportunity and wildlife
      // when a location is supplied. Those upstreams are intentionally absent
      // in this test (they degrade silently); only the Amap POI lookup is
      // asserted, so non-Amap requests return an empty failure body.
      if (parsed.pathname === '/v3/place/around') {
        amapUrl = parsed;
        return Response.json({
          status: '1',
          pois: [
            { name: '西湖', type: '风景名胜;湖泊', distance: '1200' },
            { name: '灵隐寺', type: '风景名胜;寺庙', distance: '2600' },
          ],
        });
      }
      return Response.json({ status: '0' }, { status: 502 });
    },
  });
  assert.equal(amapUrl.pathname, '/v3/place/around');
  assert.equal(amapUrl.searchParams.get('key'), 'test-amap-key');
  assert.equal(amapUrl.searchParams.get('location'), '120.150,30.250');
});

test('discovery worker endpoints require their own token, use reviewed sources and hide provider failures', async () => {
  const sourcePolicies = [{
    id: 'culture', domain: 'culture.example.gov.cn', attribution: '文化发布',
    license: 'CC BY 4.0', version: '2026-07', enabled: true,
  }];
  let searchBody;
  await withServer(async (baseUrl) => {
    const unauthorized = await fetch(`${baseUrl}/internal/v1/discovery/search`, {
      method: 'POST', headers: {
        Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: '海宁 摄影 展览', locale: 'zh-CN', freshnessDays: 7, domains: [] }),
    });
    assert.equal(unauthorized.status, 401);

    const response = await fetch(`${baseUrl}/internal/v1/discovery/search`, {
      method: 'POST', headers: {
        'X-Discovery-Worker-Token': 'worker-secret', 'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: '海宁 摄影 展览', locale: 'zh-CN', freshnessDays: 7, domains: [] }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(searchBody.include_domains, ['culture.example.gov.cn']);
    assert.deepEqual(await response.json(), { results: [{
      title: '摄影展公告', snippet: '本周在盐官举办。', url: 'https://culture.example.gov.cn/events?tracking=1',
      sourceId: 'culture', publisher: '文化发布', license: 'CC BY 4.0', version: '2026-07',
      crawlEnabled: false, crawlMode: 'static',
      allowedPathPrefixes: [], deniedPathPatterns: [],
    }] });

    const rejected = await fetch(`${baseUrl}/internal/v1/discovery/search`, {
      method: 'POST', headers: {
        'X-Discovery-Worker-Token': 'worker-secret', 'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: '海宁', locale: 'zh-CN', freshnessDays: 7, domains: ['unreviewed.example'] }),
    });
    assert.equal(rejected.status, 400);
  }, {
    discoveryWorkerToken: 'worker-secret',
    discoverySearchProfile: {
      baseUrl: 'https://api.tavily.com', apiKey: 'tavily-super-secret', enabled: true,
      timeoutMs: 8_000, sourcePolicies,
    },
    fetcher: async (url, options) => {
      assert.equal(url.toString(), 'https://api.tavily.com/search');
      searchBody = JSON.parse(options.body);
      assert.equal(searchBody.api_key, 'tavily-super-secret');
      return new Response(JSON.stringify({ results: [
        { title: '摄影展公告', content: '本周在盐官举办。', url: 'https://culture.example.gov.cn/events?tracking=1' },
        { title: '未审核', content: '不可用', url: 'https://elsewhere.example/x' },
      ] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  });
});

test('discovery extract rejects unsafe schema abuse and never falls back to arbitrary model output', async () => {
  const evidence = [{
    title: '摄影展公告', snippet: '本周在盐官举办。', url: 'https://culture.example.gov.cn/events',
    sourceId: 'culture', publisher: '文化发布', license: 'CC BY 4.0', version: '2026-07',
  }];
  await withServer(async (baseUrl) => {
    const unsafe = await fetch(`${baseUrl}/internal/v1/discovery/extract`, {
      method: 'POST', headers: {
        'X-Discovery-Worker-Token': 'worker-secret', 'Content-Type': 'application/json',
      },
      body: JSON.stringify({ missionType: 'humanityEvents', focus: '风险区域', locale: 'zh-CN', region: { latitude: 30.5, longitude: 120.6 }, evidence }),
    });
    assert.equal(unsafe.status, 400);
    const response = await fetch(`${baseUrl}/internal/v1/discovery/extract`, {
      method: 'POST', headers: {
        'X-Discovery-Worker-Token': 'worker-secret', 'Content-Type': 'application/json',
      },
      body: JSON.stringify({ missionType: 'humanityEvents', focus: '近期摄影活动', locale: 'zh-CN', region: { latitude: 30.5, longitude: 120.6 }, evidence }),
    });
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: 'invalid_response' });
  }, {
    aiApiKey: 'model-secret', discoveryWorkerToken: 'worker-secret',
    fetcher: async () => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({
      candidates: [{ title: '安全提示', kind: 'event', summary: '风险', sourceIndexes: [0] }],
    }) } }] }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
  });
});

test('global AI switch disables discovery model extraction', async () => {
  const evidence = [{
    title: '摄影展公告', snippet: '本周在盐官举办。', url: 'https://culture.example.gov.cn/events',
    sourceId: 'culture', publisher: '文化发布', license: 'CC BY 4.0', version: '2026-07',
  }];
  let upstreamCalls = 0;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/internal/v1/discovery/extract`, {
      method: 'POST',
      headers: { 'X-Discovery-Worker-Token': 'worker-secret', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        missionType: 'humanityEvents', focus: '近期摄影活动', locale: 'zh-CN',
        region: { latitude: 30.5, longitude: 120.6 }, evidence,
      }),
    });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'ai_unconfigured' });
  }, {
    aiApiKey: 'model-secret',
    discoveryWorkerToken: 'worker-secret',
    settings: { aiEnabled: false },
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('AI switch must stop extraction before upstream');
    },
  });
  assert.equal(upstreamCalls, 0);
});

test('context snapshot accepts only the current bounded contract and forwards with an internal token', async () => {
  let upstreamRequest;
  const requestBody = {
    contractVersion: 5,
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    observedAt: '2026-07-14T10:00:00+08:00',
    locale: 'zh-CN',
    intent: 'photography',
    route: { mode: 'none', stage: 'none', routeId: null, corridorSamples: [] },
  };
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/context/snapshot`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).environment.scene, 'lake');
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    now: () => new Date('2026-07-14T02:02:00Z'),
    fetcher: async (url, options) => {
      if (url.hostname.endsWith('.qweatherapi.com')) {
        const bodies = {
          '/v7/weather/now': { code: '200', now: {
            obsTime: '2026-07-14T10:00:00+08:00', temp: '26', icon: '100',
            windSpeed: '7.2', wind360: '90', vis: '20', precip: '0', cloud: '12',
          } },
          '/v7/weather/24h': { code: '200', hourly: [] },
          '/v7/minutely/5m': { code: '200', minutely: [] },
          '/v7/warning/now': { code: '200', warning: [{
            id: 'official-1', pubTime: '2026-07-14T09:55:00+08:00',
            endTime: '2026-07-14T12:00:00+08:00', level: 'Red', status: 'active',
            title: '雷电红色预警', typeName: '雷电', text: '预计未来两小时局地有强雷电活动。',
          }] },
        };
        return new Response(JSON.stringify(bodies[url.pathname]), { status: 200 });
      }
      if (url.hostname === 'restapi.amap.com') {
        return new Response(JSON.stringify({
          status: '1',
          regeocode: {
            addressComponent: { citycode: '0571' },
            aois: [{ name: '西湖风景名胜区', type: '风景名胜' }],
            pois: [],
          },
        }), { status: 200 });
      }
      upstreamRequest = { url, options };
      return new Response(JSON.stringify(v5SnapshotBody()), { status: 200 });
    },
  });
  assert.equal(upstreamRequest.url.pathname, '/internal/v1/evaluate');
  assert.equal(upstreamRequest.options.headers['X-Internal-Service-Token'], 'internal-context-token');
  const internalBody = JSON.parse(upstreamRequest.options.body);
  assert.deepEqual(Object.keys(internalBody).sort(), [
    'contractVersion', 'coordinate', 'evidence', 'forecast', 'intent', 'locale',
    'observedAt', 'officialWarnings', 'route', 'weather',
  ].sort());
  assert.deepEqual(internalBody.evidence, {
    urban: false, waterBody: true, mountainous: false, aridLand: false, settlement: false,
  });
  assert.equal(internalBody.weather.temperatureCelsius, 26);
  assert.equal(internalBody.weather.windSpeedMps, 2);
  assert.equal(internalBody.weather.thunder, false);
  assert.equal(Object.hasOwn(internalBody, 'solar'), false);
  assert.deepEqual(internalBody.officialWarnings, [{
    id: '4b54699fa8b7',
    observedAt: '2026-07-14T01:55:00.000Z',
    expiresAt: '2026-07-14T04:00:00.000Z',
    severity: 'critical',
    title: '雷电红色预警',
  }]);
});

test('context snapshot rejects identity fields without contacting the context service', async () => {
  let calls = 0;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/context/snapshot`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ contractVersion: 2, deviceId: 'forbidden' }),
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: 'invalid_context_request' });
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    fetcher: async () => {
      calls += 1;
      throw new Error('must not be called');
    },
  });
  assert.equal(calls, 0);
});

test('active debug simulation returns V5 sessions and never forwards simulated feedback', async () => {
  const registry = new SimulationRegistry();
  registry.register('debugsession2345678', { contractVersion: 5 });
  const controlId = registry.list()[0].controlId;
  assert.equal(registry.activate(controlId, 'lake-sunset').ok, true);
  let upstreamCalls = 0;
  await withServer(async (baseUrl) => {
    const headers = {
      Authorization: 'Bearer test-service-token',
      'Content-Type': 'application/json',
      'X-LumaNest-Debug-Session': 'debugsession2345678',
      'X-LumaNest-Debug-Contract': '5',
    };
    const snapshot = await fetch(`${baseUrl}/v1/context/snapshot`, {
      method: 'POST', headers,
      body: JSON.stringify({
        contractVersion: 5,
        coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
        observedAt: '2026-07-18T10:00:00+08:00',
        locale: 'zh-CN', intent: 'photography',
        route: { mode: 'none', stage: 'none', routeId: null, corridorSamples: [] },
      }),
    });
    assert.equal(snapshot.status, 200);
    const simulated = await snapshot.json();
    assert.equal(simulated.facts.shootingSessions.length, 1);
    assert.equal(simulated.facts.shootingSessions[0].kind, 'waterEvening');

    const feedback = await fetch(`${baseUrl}/v1/context/shooting-feedback`, {
      method: 'POST', headers,
      body: JSON.stringify({
        contractVersion: 2,
        ruleVersion: simulated.facts.shootingSessions[0].ruleVersion,
        conditionBand: simulated.facts.shootingSessions[0].conditionBand,
        factors: simulated.facts.shootingSessions[0].factors.map(({ id, effect }) => ({ id, effect })),
        outcome: 'captured', reasons: [], targetId: null,
      }),
    });
    assert.equal(feedback.status, 202);
    assert.deepEqual(await feedback.json(), { accepted: true });
  }, {
    simulationRegistry: registry,
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('simulation must not contact upstream services');
    },
  });
  assert.equal(upstreamCalls, 0);
  assert.equal(registry.list()[0].suppressedFeedbackCount, 1);
});

test('target session verifies the reviewed target before fetching target weather', async () => {
  const target = {
    id: 'target_0123456789abcdef01234567', name: '东岸审核湖岸', kind: 'lakeshore',
    coordinate: { latitude: 30.251, longitude: 120.151, system: 'wgs84' },
    supportedSessions: ['waterEvening'], viewBearingDegrees: 286,
    bearingToleranceDegrees: 25, accessModes: ['driving'], leadTimeMinutes: 12,
    arrivalRadiusMeters: 100, shorelineSide: 'east', reviewedAt: '2026-07-01T00:00:00Z',
    reviewReference: 'https://review.example/targets/east-bank', sourceAttribution: '审核目录',
    sourceLicense: 'CC-BY-4.0', sourceUrl: 'https://source.example/lakes/east-bank',
  };
  let evaluatedBody;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/context/target-session`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contractVersion: 1, targetId: target.id, targetCoordinate: target.coordinate,
        observedAt: '2026-07-14T02:00:00Z', locale: 'zh-CN',
      }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).facts.shootingSessions[0].conditionBand, 'good');
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    now: () => new Date('2026-07-14T02:02:00Z'),
    fetcher: async (url, options) => {
      if (url.pathname === '/internal/v1/shooting-targets/resolve') {
        assert.deepEqual(JSON.parse(options.body), { targetId: target.id, coordinate: target.coordinate });
        return new Response(JSON.stringify(target), { status: 200 });
      }
      if (url.hostname.endsWith('.qweatherapi.com')) {
        if (url.pathname === '/v7/weather/now') return new Response(JSON.stringify({
          code: '200', now: { obsTime: '2026-07-14T10:00:00+08:00', temp: '26', icon: '101', windSpeed: '6.48', wind360: '90', vis: '20', precip: '0', cloud: '55' },
        }), { status: 200 });
        if (url.pathname === '/v7/weather/24h') return new Response(JSON.stringify({
          code: '200', hourly: Array.from({ length: 24 }, (_, index) => ({
            fxTime: new Date(Date.UTC(2026, 6, 14, 2 + index)).toISOString(), icon: '101',
            windSpeed: '6.48', precip: '0', cloud: '55',
          })),
        }), { status: 200 });
        if (url.pathname === '/v7/minutely/5m') return new Response(JSON.stringify({ code: '200', minutely: [] }), { status: 200 });
        if (url.pathname === '/v7/warning/now') return new Response(JSON.stringify({ code: '200', warning: [] }), { status: 200 });
        return new Response(JSON.stringify({ code: '404' }), { status: 200 });
      }
      assert.equal(url.pathname, '/internal/v1/evaluate');
      evaluatedBody = JSON.parse(options.body);
      return new Response(JSON.stringify(v5SnapshotBody()), { status: 200 });
    },
  });
  assert.deepEqual(evaluatedBody.coordinate, target.coordinate);
  assert.equal(evaluatedBody.evidence.waterBody, true);
});

test('shooting feedback accepts only the anonymous bounded contract', async () => {
  let upstreamCalls = 0;
  const body = {
    contractVersion: 2, ruleVersion: 'water-evening.1', conditionBand: 'good',
    factors: [{ id: 'wind', effect: 'limiting' }],
    outcome: 'conditionsDidNotAppear', reasons: ['wind'], targetId: null,
  };
  await withServer(async (baseUrl) => {
    const accepted = await fetch(`${baseUrl}/v1/context/shooting-feedback`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    assert.equal(accepted.status, 202);
    assert.deepEqual(await accepted.json(), { accepted: true });
    for (const field of ['coordinate', 'deviceId', 'photo', 'exif']) {
      const rejected = await fetch(`${baseUrl}/v1/context/shooting-feedback`, {
        method: 'POST',
        headers: { Authorization: 'Bearer test-service-token', 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...body, [field]: 'forbidden' }),
      });
      assert.equal(rejected.status, 400);
    }
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    fetcher: async (url, options) => {
      upstreamCalls += 1;
      assert.equal(url.pathname, '/internal/v1/shooting-feedback');
      assert.deepEqual(JSON.parse(options.body), body);
      return new Response(JSON.stringify({ accepted: true }), { status: 200 });
    },
  });
  assert.equal(upstreamCalls, 1);
});

test('discovery endpoint authenticates and only forwards the bounded contract', async () => {
  let upstreamRequest;
  const requestBody = discoveryRequestBody();
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/explore/discover`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, 'ready');
    const rejected = await fetch(`${baseUrl}/v1/explore/discover`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ ...requestBody, preferences: ['forbidden'] }),
    });
    assert.equal(rejected.status, 400);
    assert.deepEqual(await rejected.json(), { error: 'invalid_discovery_request' });
  }, {
    discoveryServiceUrl: 'http://discovery-api:8001',
    discoveryInternalToken: 'internal-discovery-token',
    fetcher: async (url, options) => {
      upstreamRequest = { url, options };
      return new Response(JSON.stringify({
        missionType: 'humanityEvents',
        status: 'ready',
        generatedAt: '2026-07-20T02:00:00Z',
        expiresAt: '2026-07-20T08:00:00Z',
        retryAfterSeconds: null,
        items: [{
          id: 'west-lake-viewpoint', kind: 'candidate_viewpoint', title: '湖畔观景点',
          subtitle: null, placeStatus: 'candidate',
          coordinate: { latitude: 30.249, longitude: 120.151, system: 'wgs84' },
          distanceMeters: 180, address: null, startsAt: null, endsAt: null,
          evidence: [{
            publisher: '审核目录', title: '西湖周边地点',
            url: 'https://example.test/places/west-lake', observedAt: '2026-07-20T01:00:00Z',
          }],
        }],
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  });
  assert.equal(upstreamRequest.url.pathname, '/internal/v1/discover');
  assert.equal(upstreamRequest.options.headers['X-Internal-Service-Token'], 'internal-discovery-token');
  assert.deepEqual(JSON.parse(upstreamRequest.options.body), {
    ...requestBody,
    sourcePolicies: [],
  });
});

test('discovery pending response becomes 202 without leaking upstream failure details', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/explore/discover`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(discoveryRequestBody({ missionType: 'hiddenPlaces', focus: '水岸小众地点', interests: ['waterCoast'] })),
    });
    assert.equal(response.status, 202);
    assert.deepEqual(await response.json(), {
      missionType: 'hiddenPlaces', status: 'pending', generatedAt: '2026-07-20T02:00:00Z',
      expiresAt: null, retryAfterSeconds: 30, items: [],
    });
  }, {
    discoveryServiceUrl: 'http://discovery-api:8001',
    discoveryInternalToken: 'internal-discovery-token',
    fetcher: async () => new Response(JSON.stringify({
      missionType: 'hiddenPlaces', status: 'pending', generatedAt: '2026-07-20T02:00:00Z',
      expiresAt: null, retryAfterSeconds: 30, items: [],
    }), { status: 202, headers: { 'Content-Type': 'application/json' } }),
  });
});

test('discovery uses its own bounded rate-limit policy', async () => {
  await withServer(async (baseUrl) => {
    const options = {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(discoveryRequestBody()),
    };
    for (let index = 0; index < 6; index += 1) {
      assert.equal((await fetch(`${baseUrl}/v1/explore/discover`, options)).status, 202);
    }
    const limited = await fetch(`${baseUrl}/v1/explore/discover`, options);
    assert.equal(limited.status, 429);
    assert.deepEqual(await limited.json(), { error: 'rate_limited' });
  }, {
    discoveryServiceUrl: 'http://discovery-api:8001',
    discoveryInternalToken: 'internal-discovery-token',
    fetcher: async () => new Response(JSON.stringify({
      missionType: 'humanityEvents', status: 'pending', generatedAt: '2026-07-20T02:00:00Z',
      expiresAt: null, retryAfterSeconds: 30, items: [],
    }), { status: 202, headers: { 'Content-Type': 'application/json' } }),
  });
});

test('safety detail is protected, bounded, and expires with its context', async () => {
  const cache = new MemoryWeatherCache();
  await cache.setSafetyDetails('ctx_1234567890abcdef12345678', [{
    eventId: 'weather-warning-abcdef123456',
    title: '雷电红色预警',
    description: '未来两小时局地有强雷电活动。',
    guidance: ['远离制高点和水边。'],
    source: '和风天气 · 官方预警',
    severity: 'critical',
    observedAt: '2026-07-14T01:55:00Z',
    expiresAt: '2026-07-14T04:00:00Z',
    contextId: 'ctx_1234567890abcdef12345678',
  }], '2026-07-14T04:00:00Z');
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/context/safety-detail`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contextId: 'ctx_1234567890abcdef12345678',
        eventId: 'weather-warning-abcdef123456',
      }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).title, '雷电红色预警');
  }, {
    weatherCache: cache,
    now: () => new Date('2026-07-14T02:00:00Z'),
    fetcher: async () => { throw new Error('detail must not contact upstream'); },
  });
});

test('removed client weather-token endpoint stays unavailable', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/qweather/token`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: 'not_found' });
  }, { requestRateLimiter: new MemoryRequestRateLimiter() });
});

test('starts isolated App and admin listeners without exposing admin on App API', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-services-'));
  const privateKeyPath = join(directory, 'qweather.pem');
  const { privateKey } = generateKeyPairSync('ed25519');
  await writeFile(privateKeyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  const services = await createBrokerServices({
    QWEATHER_PRIVATE_KEY_PATH: privateKeyPath,
    QWEATHER_KEY_ID: 'key-id', QWEATHER_PROJECT_ID: 'project-id',
    LUMANEST_SERVICE_TOKEN: 'service-token', AMAP_WEB_KEY: 'amap-key',
    LUMANEST_CONFIG_MASTER_KEY: Buffer.alloc(32, 3).toString('base64'),
    LUMANEST_ADMIN_PASSWORD: 'initial-password', LUMANEST_DATA_DIR: directory,
    PORT: '0', ADMIN_PORT: '0',
  });
  await Promise.all([
    new Promise((resolve) => services.appServer.listen(0, '127.0.0.1', resolve)),
    new Promise((resolve) => services.adminServer.listen(0, '127.0.0.1', resolve)),
  ]);
  try {
    const appUrl = `http://127.0.0.1:${services.appServer.address().port}`;
    const adminUrl = `http://127.0.0.1:${services.adminServer.address().port}`;
    assert.equal((await fetch(`${appUrl}/healthz`)).status, 200);
    assert.equal((await fetch(`${appUrl}/admin`)).status, 404);
    assert.equal((await fetch(`${adminUrl}/admin`)).status, 200);
  } finally {
    await Promise.all([
      new Promise((resolve) => services.appServer.close(resolve)),
      new Promise((resolve) => services.adminServer.close(resolve)),
    ]);
    await rm(directory, { recursive: true, force: true });
  }
});

test('environment configuration has no single-provider AI fields', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-environment-'));
  const privateKeyPath = join(directory, 'qweather.pem');
  const { privateKey } = generateKeyPairSync('ed25519');
  await writeFile(privateKeyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  try {
    const configuration = configurationFromEnvironment({
      QWEATHER_PRIVATE_KEY_PATH: privateKeyPath,
      QWEATHER_KEY_ID: 'key-id', QWEATHER_PROJECT_ID: 'project-id',
      LUMANEST_SERVICE_TOKEN: 'service-token', AMAP_WEB_KEY: 'amap-key',
      LUMANEST_RASTER_SERVICE_URL: 'http://lumanest-raster-service:8792',
      LUMANEST_RASTER_SERVICE_TOKEN: 'raster-token',
      LUMANEST_RASTER_DATASET_REVISION: 'eog-v2.2-2024-median-masked-r1',
      LUMANEST_TERRAIN_SERVICE_URL: 'http://lumanest-terrain-service:8793',
      LUMANEST_TERRAIN_SERVICE_TOKEN: 'terrain-token',
      LUMANEST_TERRAIN_DATASET_REVISION: 'copernicus-glo30-2024-r1',
    });
    assert.equal(Object.hasOwn(configuration, 'aiApiKey'), false);
    assert.equal(Object.hasOwn(configuration, 'aiBaseUrl'), false);
    assert.equal(Object.hasOwn(configuration, 'aiModel'), false);
    assert.equal(configuration.rasterServiceUrl, 'http://lumanest-raster-service:8792');
    assert.equal(configuration.rasterServiceToken, 'raster-token');
    assert.equal(configuration.rasterDatasetRevision, 'eog-v2.2-2024-median-masked-r1');
    assert.equal(configuration.terrainServiceUrl, 'http://lumanest-terrain-service:8793');
    assert.equal(configuration.terrainServiceToken, 'terrain-token');
    assert.equal(configuration.terrainHorizonDatasetRevision, 'copernicus-glo30-2024-r1');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('wildlife endpoint enforces production quality and keeps traceable aggregates', async () => {
  const datasetKey = '11111111-1111-4111-8111-111111111111';
  const secondDatasetKey = '33333333-3333-4333-8333-333333333333';
  const occurrenceUrls = [];
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.contractVersion, 2);
    assert.equal(body.source, 'GBIF');
    assert.equal(body.scope, 'regional_wildlife_observations');
    assert.equal(body.scannedOccurrenceSampleSize, 7);
    assert.equal(body.eligibleOccurrenceSampleSize, 3);
    assert.equal(body.occurrenceSampleSize, 3);
    assert.equal(body.datasetReferencesTruncated, false);
    assert.deepEqual(body.taxa, [
      {
        scientificName: 'Passer montanus',
        commonName: null,
        animalClass: 'bird',
        records: 2,
      },
      {
        scientificName: 'Lutra lutra',
        commonName: 'Eurasian Otter',
        animalClass: 'mammal',
        records: 1,
      },
    ]);
    assert.deepEqual(body.qualityPolicy.acceptedLicenses, ['CC0-1.0', 'CC-BY-4.0']);
    assert.equal(body.qualityPolicy.maximumCoordinateUncertaintyMeters, 10_000);
    assert.equal(body.qualityPolicy.maximumDatasetReferences, 8);
    assert.deepEqual(body.historicalRecordConcentration, {
      recordsWithMonth: 3,
      recordsWithTime: 3,
      months: [{ month: 5, records: 2 }, { month: 6, records: 1 }],
      timePeriods: [{ period: 'dawn', records: 2 }, { period: 'night', records: 1 }],
    });
    assert.deepEqual(body.datasets, [
      {
        datasetKey,
        title: 'Shanghai bird observations',
        publisher: 'Open Bird Lab',
        licenses: ['CC-BY-4.0'],
        records: 2,
        citation: 'Open Bird Lab (2026). Shanghai bird observations.',
        url: `https://www.gbif.org/dataset/${datasetKey}`,
      },
      {
        datasetKey: secondDatasetKey,
        title: 'Regional mammal observations',
        publisher: 'Regional Nature Centre',
        licenses: ['CC0-1.0'],
        records: 1,
        citation: 'Regional mammal observations. GBIF occurrence dataset.',
        url: `https://www.gbif.org/dataset/${secondDatasetKey}`,
      },
    ]);
    assert.equal(JSON.stringify(body).includes('decimalLatitude'), false);
    assert.equal(JSON.stringify(body).includes('decimalLongitude'), false);
  }, {
    fetcher: async (url) => {
      if (url.pathname.startsWith('/v1/dataset/')) {
        const isBirdDataset = url.pathname.endsWith(datasetKey);
        return new Response(JSON.stringify(isBirdDataset ? {
          title: 'Shanghai bird observations',
          citation: { text: 'Open Bird Lab (2026). Shanghai bird observations.' },
        } : {
          title: 'Regional mammal observations',
          citation: { text: 'Regional mammal observations. GBIF occurrence dataset.' },
        }), { status: 200 });
      }
      occurrenceUrls.push(url);
      const classKey = url.searchParams.get('classKey');
      const good = {
        occurrenceStatus: 'PRESENT',
        basisOfRecord: 'HUMAN_OBSERVATION',
        coordinateUncertaintyInMeters: 120,
        license: 'http://creativecommons.org/licenses/by/4.0/legalcode',
        issues: [],
      };
      const records = classKey === '212'
        ? [
          { ...good, species: 'Passer montanus', class: 'Aves', datasetKey,
            publishingOrgName: 'Open Bird Lab', month: 5, eventDate: '2026-05-01T06:20:00',
            decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { ...good, species: 'Passer montanus', class: 'Aves', datasetKey,
            publishingOrgName: 'Open Bird Lab', month: 5, hour: 7,
            decimalLatitude: 31.3, decimalLongitude: 121.5 },
          { ...good, species: 'Uncertain bird', class: 'Aves',
            coordinateUncertaintyInMeters: 50_000 },
          { ...good, species: 'Restricted bird', class: 'Aves', license: 'CC_BY_NC_4_0' },
        ]
        : classKey === '359'
        ? [
          { ...good, species: 'Lutra lutra', vernacularName: 'Eurasian Otter',
            class: 'Mammalia', datasetKey: secondDatasetKey,
            publishingOrgName: 'Regional Nature Centre', license: 'CC0_1_0',
            month: 6, hour: 23, decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { ...good, species: 'Felis catus', class: 'Mammalia', datasetKey },
          { ...good, species: 'Panthera pardus', class: 'Mammalia', datasetKey,
            issues: ['PRESUMED_SWAPPED_COORDINATE'] },
        ]
        : [];
      return new Response(JSON.stringify({ results: records }), { status: 200 });
    },
  });
  assert.equal(occurrenceUrls.length, 5);
  for (const url of occurrenceUrls) {
    assert.equal(url.searchParams.get('occurrenceStatus'), 'PRESENT');
    assert.equal(url.searchParams.get('hasGeospatialIssue'), 'false');
    assert.equal(url.searchParams.get('coordinateUncertaintyInMeters'), '10000');
    assert.deepEqual(url.searchParams.getAll('license'), ['CC0_1_0', 'CC_BY_4_0']);
    assert.deepEqual(url.searchParams.getAll('basisOfRecord'), [
      'HUMAN_OBSERVATION', 'MACHINE_OBSERVATION', 'OBSERVATION',
    ]);
  }
});

test('wildlife endpoint distinguishes an honest empty region from upstream failure', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.contractVersion, 2);
    assert.equal(body.occurrenceSampleSize, 0);
    assert.deepEqual(body.taxa, []);
    assert.deepEqual(body.datasets, []);
  }, {
    fetcher: async () => new Response(JSON.stringify({ results: [] }), { status: 200 }),
  });

  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 502);
  }, {
    fetcher: async () => new Response(JSON.stringify({ error: 'failed' }), { status: 503 }),
  });
});

test('wildlife aggregates only records covered by its bounded dataset references', async () => {
  const records = Array.from({ length: 9 }, (_, index) => {
    const digit = index + 1;
    return {
      species: `Traceable species ${digit}`,
      class: 'Aves',
      occurrenceStatus: 'PRESENT',
      basisOfRecord: 'HUMAN_OBSERVATION',
      coordinateUncertaintyInMeters: 100,
      license: 'CC0_1_0',
      issues: [],
      datasetKey: `0000000${digit}-0000-4000-8000-00000000000${digit}`,
      publishingOrgName: `Publisher ${digit}`,
    };
  });
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.eligibleOccurrenceSampleSize, 9);
    assert.equal(body.occurrenceSampleSize, 8);
    assert.equal(body.datasetReferencesTruncated, true);
    assert.equal(body.datasets.length, 8);
    assert.equal(body.taxa.length, 8);
  }, {
    fetcher: async (url) => {
      if (url.pathname.startsWith('/v1/dataset/')) {
        return new Response(JSON.stringify({ title: 'Traceable dataset' }), { status: 200 });
      }
      return new Response(JSON.stringify({
        results: url.searchParams.get('classKey') === '212' ? records : [],
      }), { status: 200 });
    },
  });
});

test('wildlife layer endpoint forwards reviewed polygons without exposing internal token', async () => {
  let upstreamRequest;
  await withServer(async (baseUrl) => {
    const unauthorized = await fetch(
      `${baseUrl}/v1/wildlife/layers?location=120.15,30.25&radiusKm=20`,
    );
    assert.equal(unauthorized.status, 401);

    const response = await fetch(
      `${baseUrl}/v1/wildlife/layers?location=120.15,30.25&radiusKm=20`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.areas[0].name, '历史观察区域');
    assert.equal(JSON.stringify(body).includes('internal-context-token'), false);
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    fetcher: async (url, options) => {
      upstreamRequest = { url, options };
      return new Response(JSON.stringify({
        contractVersion: 1,
        generatedAt: '2026-07-16T02:00:00Z',
        radiusKm: 20,
        areas: [{
          id: 'd'.repeat(64),
          name: '历史观察区域',
          geometry: {
            type: 'Polygon',
            coordinates: [[[120, 30], [120.2, 30], [120.2, 30.2], [120, 30]]],
          },
          source: {
            attribution: 'Reviewed wildlife dataset',
            version: '2026.07',
            updatedAt: '2026-07-16T00:00:00Z',
          },
        }],
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  });
  assert.equal(upstreamRequest.url.pathname, '/internal/v1/wildlife/layers');
  assert.equal(upstreamRequest.options.headers['X-Internal-Service-Token'], 'internal-context-token');
});

test('Amap proxy requires the app service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/nearby?location=121.47,31.23`);
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'unauthorized' });
  });
});

test('Amap nearby strips provider photos instead of treating them as place evidence', async () => {
  let upstreamRequests = 0;
  await withServer(async (baseUrl) => {
    const nearby = await fetch(
      `${baseUrl}/v1/amap/nearby?location=120.70,30.52&keywords=%E6%B9%BF%E5%9C%B0%E5%85%AC%E5%9B%AD`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(nearby.status, 200);
    const body = await nearby.json();
    assert.equal('photos' in body.pois[0], false);
    assert.equal('media' in body.pois[0], false);
  }, {
    fetcher: async (url) => {
      upstreamRequests += 1;
      if (url.hostname === 'restapi.amap.com') {
        return new Response(JSON.stringify({
          status: '1',
          pois: [{
            id: 'poi-1',
            name: '长山河生态湿地公园',
            photos: [
              { provider: '高德地图', title: '湿地公园', url: 'https://aos-comment.amap.com/pic/photo.jpg' },
              { provider: '未知来源', title: '错误图片', url: 'https://evil.example/photo.jpg' },
            ],
          }],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      throw new Error('provider image must never be fetched');
    },
  });
  assert.equal(upstreamRequests, 1);
});

test('place detail media prioritizes strict Commons evidence and supplements a matching AMap POI', async () => {
  const photoBytes = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
  let searchRequests = 0;
  let mediaRequests = 0;
  await withServer(async (baseUrl) => {
    const path = '/v1/explore/place-media?name=' +
      encodeURIComponent('长山河生态湿地公园') +
      '&city=' + encodeURIComponent('嘉兴市') + '&poiId=poi-1&lat=30.6842&lon=120.7281';
    const first = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(first.status, 200);
    const body = await first.json();
    assert.equal(body.status, 'ok');
    assert.equal(body.cacheStatus, 'miss');
    assert.equal(body.media.length, 2);
    assert.equal(body.media[0].attribution, 'Wikimedia Commons');
    assert.equal(body.media[0].sourceTier, 'primary');
    assert.equal(body.media[0].matchBasis, 'name');
    assert.equal(body.media[1].attribution, '高德地图');
    assert.equal(body.media[1].sourceTier, 'supplemental');
    assert.equal(body.media[1].matchBasis, 'amapPoiId');
    assert.equal('url' in body.media[0], false);

    const second = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal((await second.json()).cacheStatus, 'hit');

    const image = await fetch(`${baseUrl}${body.media[1].proxyPath}`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(image.status, 200);
    assert.equal(image.headers.get('content-type'), 'image/jpeg');
    assert.deepEqual(Buffer.from(await image.arrayBuffer()), photoBytes);
  }, {
    fetcher: async (url) => {
      if (url.hostname === 'commons.wikimedia.org') {
        searchRequests += 1;
        return new Response(JSON.stringify({
          query: {
            pages: [{
              pageid: 42,
              title: 'File:长山河生态湿地公园.jpg',
              imageinfo: [{
                mime: 'image/jpeg',
                thumburl: 'https://upload.wikimedia.org/example/wetland.jpg',
                extmetadata: {
                  ImageDescription: { value: '嘉兴市长山河生态湿地公园' },
                  LicenseShortName: { value: 'CC BY-SA 4.0' },
                },
              }],
            }],
          },
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (url.hostname === 'restapi.amap.com') {
        assert.equal(url.pathname, '/v3/place/detail');
        assert.equal(url.searchParams.get('id'), 'poi-1');
        return new Response(JSON.stringify({
          status: '1',
          pois: [{
            id: 'poi-1',
            name: '长山河生态湿地公园',
            photos: [{
              title: '湖岸步道',
              url: 'https://aos-comment.amap.com/example/wetland.jpg',
            }],
          }],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      mediaRequests += 1;
      assert.equal(url.hostname, 'aos-comment.amap.com');
      return new Response(photoBytes, {
        status: 200,
        headers: { 'Content-Type': 'image/jpeg', 'Content-Length': `${photoBytes.length}` },
      });
    },
  });
  assert.equal(searchRequests, 1);
  assert.equal(mediaRequests, 1);
});

test('Amap text search forwards only a bounded search phrase', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/search?keywords=%E8%A5%BF%E6%B9%96&offset=9`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, '1');
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ status: '1', pois: [] }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v3/place/text');
  assert.equal(upstreamUrl.searchParams.get('keywords'), '西湖');
  assert.equal(upstreamUrl.searchParams.get('offset'), '9');
  assert.equal(upstreamUrl.searchParams.get('extensions'), 'base');
});

test('Amap text search rejects an empty search phrase', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/search?keywords=`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: 'invalid_keywords' });
  });
});

test('Amap proxy rejects malformed coordinates before forwarding', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/nearby?location=not-a-coordinate`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: 'invalid_location' });
  });
});

test('Amap scene evidence forwards the client-provided GCJ-02 coordinate verbatim', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/scene-evidence?location=120.15,30.25`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ status: '1', regeocode: { pois: [], aois: [] } }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v3/geocode/regeo');
  // The broker must forward the client-provided GCJ-02 coordinate unchanged.
  // The Flutter client owns the single WGS84 → GCJ-02 conversion boundary.
  assert.equal(upstreamUrl.searchParams.get('location'), '120.15,30.25');
  assert.equal(upstreamUrl.searchParams.get('radius'), '3000');
  assert.equal(upstreamUrl.searchParams.get('extensions'), 'all');
});

test('Amap walking route forwards client-provided GCJ-02 origin and destination verbatim', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/amap/walking?origin=121.47,31.23&destination=121.48,31.24`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ status: '1', route: { paths: [] } }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v3/direction/walking');
  assert.equal(upstreamUrl.searchParams.get('origin'), '121.47,31.23');
  assert.equal(upstreamUrl.searchParams.get('destination'), '121.48,31.24');
  assert.equal(upstreamUrl.searchParams.has('strategy'), false);
});

test('Amap driving route forwards client-provided GCJ-02 origin and destination verbatim', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/amap/driving?origin=121.47,31.23&destination=121.4998,31.2397`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ status: '1', route: { paths: [] } }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v3/direction/driving');
  assert.equal(upstreamUrl.searchParams.get('origin'), '121.47,31.23');
  assert.equal(upstreamUrl.searchParams.get('destination'), '121.4998,31.2397');
  assert.equal(upstreamUrl.searchParams.get('strategy'), '0');
});

test('Amap nearby forwards the client-provided GCJ-02 location verbatim', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/amap/nearby?location=121.4782,31.2285&keywords=观景台&radius=5000`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, '1');
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ status: '1', pois: [] }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v3/place/around');
  assert.equal(upstreamUrl.searchParams.get('location'), '121.4782,31.2285');
  assert.equal(upstreamUrl.searchParams.get('keywords'), '观景台');
  assert.equal(upstreamUrl.searchParams.get('radius'), '5000');
  assert.equal(upstreamUrl.searchParams.get('sortrule'), 'distance');
});

test('elevation profile returns only a same-length sanitized array', async () => {
  let upstreamUrl;
  await withServer(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/elevation/profile?locations=121.47,31.23;121.48,31.24`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      source: 'Open-Meteo Elevation API',
      elevations: [5, 21],
    });
  }, {
    fetcher: async (url) => {
      upstreamUrl = url;
      return new Response(JSON.stringify({ elevation: [5, 21] }), { status: 200 });
    },
  });
  assert.equal(upstreamUrl.pathname, '/v1/elevation');
  assert.equal(upstreamUrl.searchParams.get('latitude'), '31.23,31.24');
  assert.equal(upstreamUrl.searchParams.get('longitude'), '121.47,121.48');
});

test('elevation profile rejects malformed or excessive coordinates', async () => {
  await withServer(async (baseUrl) => {
    const malformed = await fetch(
      `${baseUrl}/v1/elevation/profile?locations=bad;121.48,31.24`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(malformed.status, 400);

    const excessive = Array.from({ length: 65 }, (_, index) => `121.${index},31.2`).join(';');
    const response = await fetch(
      `${baseUrl}/v1/elevation/profile?locations=${excessive}`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 400);
  });
});

test('route weather fetches each WGS84 sample and returns only forecast progress', async () => {
  const requestedLocations = new Set();
  const now = new Date('2026-07-18T02:00:00Z');
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/route/weather`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        routeId: 'r1234abcd',
        samples: [
          {
            latitude: 30.25, longitude: 120.15, system: 'wgs84', progress: 0,
            expectedAt: '2026-07-18T02:10:00Z',
          },
          {
            latitude: 30.5, longitude: 120.5, system: 'wgs84', progress: 1,
            expectedAt: '2026-07-18T03:10:00Z',
          },
        ],
      }),
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.source, 'QWeather');
    assert.equal(body.coverage, 'full');
    assert.deepEqual(body.samples.map((sample) => sample.progress), [0, 1]);
    assert.equal(JSON.stringify(body).includes('latitude'), false);
    assert.equal(JSON.stringify(body).includes('longitude'), false);
  }, {
    now: () => now,
    fetcher: async (url) => {
      requestedLocations.add(url.searchParams.get('location'));
      const bodies = {
        '/v7/weather/now': { code: '200', now: {
          obsTime: '2026-07-18T10:00:00+08:00', temp: '26', icon: '101',
          windSpeed: '7.2', wind360: '90', vis: '20', precip: '0', cloud: '50',
        } },
        '/v7/weather/24h': { code: '200', hourly: [
          { fxTime: '2026-07-18T10:00:00+08:00', icon: '100', windSpeed: '5.4', precip: '0', vis: '25', cloud: '20' },
          { fxTime: '2026-07-18T11:00:00+08:00', icon: '305', windSpeed: '14.4', precip: '2.5', vis: '8', cloud: '90' },
        ] },
        '/v7/minutely/5m': { code: '200', minutely: [] },
        '/v7/warning/now': { code: '200', warning: [] },
        '/v7/air/now': { code: '200', updateTime: '2026-07-18T10:00:00+08:00', now: {
          pubTime: '2026-07-18T10:00:00+08:00', aqi: '40', category: '优', primary: 'NA',
        } },
      };
      return new Response(JSON.stringify(bodies[url.pathname]), { status: 200 });
    },
  });
  assert.deepEqual([...requestedLocations].sort(), ['120.15,30.25', '120.5,30.5']);
});

test('route weather rejects unbounded or non-WGS84 samples before upstream traffic', async () => {
  let upstreamCalls = 0;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/route/weather`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        routeId: 'r1234abcd',
        samples: [
          { latitude: 30, longitude: 120, system: 'gcj02', progress: 0, expectedAt: '2026-07-18T02:10:00Z' },
          { latitude: 31, longitude: 121, system: 'gcj02', progress: 1, expectedAt: '2026-07-18T03:10:00Z' },
        ],
      }),
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: 'invalid_route_weather_request' });
  }, {
    now: () => new Date('2026-07-18T02:00:00Z'),
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('must not be called');
    },
  });
  assert.equal(upstreamCalls, 0);
});

test('narrative endpoint is disabled without a server-side model key', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/narrative`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        scene: 'lake',
        dayPhase: 'sunset',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.water.evening'],
        templateSummary: '今晚可以留意湖面倒影。',
      }),
    });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'ai_unconfigured' });
  });
});

test('narrative endpoint is disabled by runtime settings without upstream traffic', async () => {
  let upstreamCalls = 0;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/narrative`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        scene: 'city',
        dayPhase: 'blueHour',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.city.blue_hour'],
        templateSummary: '蓝调时间适合拍城市灯光。',
      }),
    });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'ai_unconfigured' });
  }, {
    aiApiKey: 'configured-key',
    settings: { aiEnabled: false },
    fetcher: async () => {
      upstreamCalls += 1;
      throw new Error('must not be called');
    },
  });
  assert.equal(upstreamCalls, 0);
});

test('narrative endpoint sends only bounded creative context and sanitizes output', async () => {
  let upstreamRequest;
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/narrative`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        scene: 'lake',
        dayPhase: 'sunset',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.water.evening'],
        templateSummary: '今晚可以留意湖面倒影。',
        tone: 'detailed',
      }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      summary: '湖面正在安静下来，可以等等倒影。',
      noteLabels: { 'session.water.evening': '等倒影' },
    });
  }, {
    aiApiKey: 'test-ai-key',
    aiBaseUrl: 'https://model.example/v1',
    aiModel: 'test-model',
    fetcher: async (url, options) => {
      upstreamRequest = { url, options };
      return new Response(JSON.stringify({
        choices: [{
          message: {
            content: JSON.stringify({
              summary: '湖面正在安静下来，可以等等倒影。',
              noteLabels: { 'session.water.evening': '等倒影' },
            }),
          },
        }],
      }), { status: 200 });
    },
  });
  assert.equal(upstreamRequest.url.href, 'https://model.example/v1/chat/completions');
  assert.equal(upstreamRequest.options.headers.Authorization, 'Bearer test-ai-key');
  const modelBody = JSON.parse(upstreamRequest.options.body);
  assert.equal(modelBody.model, 'test-model');
  assert.equal(upstreamRequest.options.body.includes('latitude'), false);
  assert.equal(upstreamRequest.options.body.includes('longitude'), false);
  assert.equal(upstreamRequest.options.body.includes('详细'), true);
  for (const forbidden of [
    'photographyPreferences', 'activityPreferences', 'recommendationIntensity',
    'equipmentList', 'preferenceFingerprint',
  ]) {
    assert.equal(upstreamRequest.options.body.includes(forbidden), false);
  }
});

test('narrative tone is optional, bounded and changes only prompt guidance', async () => {
  const prompts = [];
  for (const tone of [undefined, 'concise', 'balanced', 'detailed']) {
    await withServer(async (baseUrl) => {
      const body = {
        scene: 'city',
        dayPhase: 'blueHour',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.city.after_rain'],
        templateSummary: '晨昏光线正在进入街巷。',
      };
      if (tone !== undefined) body.tone = tone;
      const response = await fetch(`${baseUrl}/v1/narrative`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer test-service-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
      assert.equal(response.status, 200);
    }, {
      aiApiKey: 'test-ai-key',
      fetcher: async (_url, options) => {
        prompts.push(JSON.parse(options.body).messages);
        return new Response(JSON.stringify({
          choices: [{ message: { content: JSON.stringify({
            summary: '街巷光线正在变暖。',
            noteLabels: { 'session.city.after_rain': '看街巷' },
          }) } }],
        }), { status: 200 });
      },
    });
  }

  assert.match(prompts[0][0].content, /自然均衡/);
  assert.match(prompts[1][0].content, /简洁直接/);
  assert.match(prompts[2][0].content, /自然均衡/);
  assert.match(prompts[3][0].content, /较详细/);
});

test('narrative endpoint rejects extra fields and unknown model labels', async () => {
  await withServer(async (baseUrl) => {
    const invalid = await fetch(`${baseUrl}/v1/narrative`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        scene: 'lake',
        dayPhase: 'sunset',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.water.evening'],
        templateSummary: '今晚可以留意湖面倒影。',
        latitude: 30.25,
      }),
    });
    assert.equal(invalid.status, 400);
  }, { aiApiKey: 'test-ai-key' });

  for (const forbiddenBody of [
    { tone: 'verbose' },
    { photographyPreferences: ['landscape'] },
    { activityPreferences: ['driving'] },
    { recommendationIntensity: 1 },
    { equipmentList: 'camera' },
    { preferenceFingerprint: 'abc' },
    { userId: 'person' },
  ]) {
    await withServer(async (baseUrl) => {
      const response = await fetch(`${baseUrl}/v1/narrative`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer test-service-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          scene: 'lake',
          dayPhase: 'sunset',
          weather: 'clear',
          activeRoute: false,
          creativeEventIds: ['session.water.evening'],
          templateSummary: '今晚可以留意湖面倒影。',
          ...forbiddenBody,
        }),
      });
      assert.equal(response.status, 400);
    }, { aiApiKey: 'test-ai-key' });
  }

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/narrative`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        scene: 'lake',
        dayPhase: 'sunset',
        weather: 'clear',
        activeRoute: false,
        creativeEventIds: ['session.water.evening'],
        templateSummary: '今晚可以留意湖面倒影。',
      }),
    });
    assert.equal(response.status, 502);
  }, {
    aiApiKey: 'test-ai-key',
    fetcher: async () => new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({
        summary: '可以拍。',
        noteLabels: { unknown: '新事实' },
      }) } }],
    }), { status: 200 }),
  });
});
