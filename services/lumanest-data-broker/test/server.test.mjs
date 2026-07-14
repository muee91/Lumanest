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

const { privateKey: testQWeatherPrivateKey } = generateKeyPairSync('ed25519');

async function withServer(run, {
  fetcher,
  aiApiKey = '',
  aiBaseUrl,
  aiModel,
  settings,
  runtimeConfig,
  contextServiceUrl = '',
  contextInternalToken = '',
  qweatherApiHost = 'https://project.qweatherapi.com',
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
    qweatherApiHost,
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

test('health check never requires a service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});

test('context snapshot accepts only the bounded v2 contract and forwards with an internal token', async () => {
  let upstreamRequest;
  const requestBody = {
    contractVersion: 2,
    coordinate: { latitude: 30.25, longitude: 120.15, system: 'wgs84' },
    observedAt: '2026-07-14T10:00:00+08:00',
    locale: 'zh-CN',
    intent: 'photography',
    route: { mode: 'none', stage: 'none' },
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
    assert.equal((await response.json()).scene, 'lake');
    const legacyResponse = await fetch(`${baseUrl}/v1/context/snapshot`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer test-service-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ...requestBody,
        evidence: { urban: false, waterBody: false, mountainous: true, aridLand: false, settlement: false },
        weather: {
          observedAt: '2026-07-14T10:00:00+08:00', condition: 'rain',
          windSpeedMps: 100, precipitationMm: 100, visibilityKm: 1,
          thunder: true, stale: false,
          temperatureCelsius: 5, windDirectionDegrees: 180, cloudCoverPercent: 100,
        },
        solar: { dayPhase: 'night', elevationDegrees: -30, azimuthDegrees: 1 },
      }),
    });
    assert.equal(legacyResponse.status, 200);
  }, {
    contextServiceUrl: 'http://context-service:8000',
    contextInternalToken: 'internal-context-token',
    fetcher: async (url, options) => {
      if (url.hostname.endsWith('.qweatherapi.com')) {
        const bodies = {
          '/v7/weather/now': { code: '200', now: {
            obsTime: '2026-07-14T10:00:00+08:00', temp: '26', icon: '100',
            windSpeed: '7.2', wind360: '90', vis: '20', precip: '0', cloud: '12',
          } },
          '/v7/weather/24h': { code: '200', hourly: [] },
          '/v7/minutely/5m': { code: '200', minutely: [] },
          '/v7/warning/now': { code: '200', warning: [] },
        };
        return new Response(JSON.stringify(bodies[url.pathname]), { status: 200 });
      }
      upstreamRequest = { url, options };
      return new Response(JSON.stringify({
        contractVersion: 2,
        contextId: 'ctx_1234567890abcdef12345678',
        generatedAt: '2026-07-14T02:00:00Z',
        expiresAt: '2026-07-14T02:15:00Z',
        scene: 'lake', fingerprint: '1234567890abcdef12345678', stale: false,
        dataFreshness: {
          context: 'fresh', weather: 'fresh', weatherObservedAt: '2026-07-14T02:00:00Z',
        },
        weather: {
          condition: 'clear', temperatureCelsius: 26, windSpeedMps: 2,
          windDirectionDegrees: 90, precipitationMm: 0, visibilityKm: 20,
          cloudCoverPercent: null, thunder: false,
        },
        sunMoon: {
          dayPhase: 'sunset', sunElevationDegrees: 4, sunAzimuthDegrees: 280,
          moonPhase: 'waxingCrescent', moonIllumination: 0.2,
        },
        route: { mode: 'none', stage: 'none', active: false },
        events: [], allowedActions: [],
        manifest: { layoutMode: 'quiet', primaryEventId: null, secondaryEventIds: [], safetyEventIds: [] },
      }), { status: 200 });
    },
  });
  assert.equal(upstreamRequest.url.pathname, '/internal/v1/evaluate');
  assert.equal(upstreamRequest.options.headers['X-Internal-Service-Token'], 'internal-context-token');
  const internalBody = JSON.parse(upstreamRequest.options.body);
  assert.deepEqual(Object.keys(internalBody).sort(), [
    'contractVersion', 'coordinate', 'forecast', 'intent', 'locale',
    'observedAt', 'officialWarnings', 'route', 'weather',
  ].sort());
  assert.equal(internalBody.weather.temperatureCelsius, 26);
  assert.equal(internalBody.weather.windSpeedMps, 2);
  assert.equal(internalBody.weather.thunder, false);
  assert.equal(Object.hasOwn(internalBody, 'evidence'), false);
  assert.equal(Object.hasOwn(internalBody, 'solar'), false);
  assert.deepEqual(internalBody.officialWarnings, []);
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

test('empty legacy AI environment has no provider-specific defaults', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-environment-'));
  const privateKeyPath = join(directory, 'qweather.pem');
  const { privateKey } = generateKeyPairSync('ed25519');
  await writeFile(privateKeyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  try {
    const configuration = configurationFromEnvironment({
      QWEATHER_PRIVATE_KEY_PATH: privateKeyPath,
      QWEATHER_KEY_ID: 'key-id', QWEATHER_PROJECT_ID: 'project-id',
      LUMANEST_SERVICE_TOKEN: 'service-token', AMAP_WEB_KEY: 'amap-key',
      AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '',
    });
    assert.equal(configuration.aiApiKey, '');
    assert.equal(configuration.aiBaseUrl, '');
    assert.equal(configuration.aiModel, '');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('wildlife endpoint returns regional aggregates without observation coordinates', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.source, 'GBIF');
    assert.equal(body.scope, 'regional_wildlife_observations');
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
    assert.equal(JSON.stringify(body).includes('decimalLatitude'), false);
    assert.equal(JSON.stringify(body).includes('decimalLongitude'), false);
  }, {
    fetcher: async (url) => {
      const classKey = url.searchParams.get('classKey');
      const records = classKey === '212'
        ? [
          { species: 'Passer montanus', class: 'Aves', decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { species: 'Passer montanus', class: 'Aves', decimalLatitude: 31.3, decimalLongitude: 121.5 },
        ]
        : classKey === '359'
        ? [
          { species: 'Lutra lutra', vernacularName: 'Eurasian Otter', class: 'Mammalia', decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { species: 'Felis catus', class: 'Mammalia', decimalLatitude: 31.2, decimalLongitude: 121.4 },
        ]
        : [];
      return new Response(JSON.stringify({ results: records }), { status: 200 });
    },
  });
});

test('Amap proxy requires the app service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/nearby?location=121.47,31.23`);
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'unauthorized' });
  });
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
        creativeEventIds: ['reflection'],
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
        creativeEventIds: ['city_blue_hour'],
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
        creativeEventIds: ['reflection'],
        templateSummary: '今晚可以留意湖面倒影。',
      }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      summary: '湖面正在安静下来，可以等等倒影。',
      noteLabels: { reflection: '等倒影' },
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
              noteLabels: { reflection: '等倒影' },
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
        creativeEventIds: ['reflection'],
        templateSummary: '今晚可以留意湖面倒影。',
        latitude: 30.25,
      }),
    });
    assert.equal(invalid.status, 400);
  }, { aiApiKey: 'test-ai-key' });

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
        creativeEventIds: ['reflection'],
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
