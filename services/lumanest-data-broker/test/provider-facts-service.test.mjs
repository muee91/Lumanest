import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ProviderFactsService,
  supportedProviderIds,
  validProviderFactsQuery,
} from '../src/environment/provider-facts-service.mjs';

const instant = new Date('2026-08-03T08:00:00.000Z');

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function text(body, status = 200) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/plain' },
  });
}

function query(include = supportedProviderIds.join(',')) {
  const params = new URLSearchParams({
    lat: '30.25',
    lon: '120.15',
    radiusKm: '25',
    locale: 'zh-CN',
    at: instant.toISOString(),
    include,
  });
  return validProviderFactsQuery(params, instant);
}

test('default provider query keeps eBird optional and includes iNaturalist', () => {
  const params = new URLSearchParams({ lat: '30.25', lon: '120.15' });
  const parsed = validProviderFactsQuery(params, instant);
  assert.equal(parsed.providerIds.includes('inaturalist'), true);
  assert.equal(parsed.providerIds.includes('ebird'), false);
});

test('provider query is bounded and rejects unknown sources', () => {
  assert.equal(validProviderFactsQuery(new URLSearchParams({ lat: '91', lon: '120' }), instant), null);
  assert.equal(validProviderFactsQuery(new URLSearchParams({ lat: '30', lon: '120', include: 'unknown' }), instant), null);
  assert.deepEqual(query('osm,wikidata').providerIds, ['osm', 'wikidata']);
});

test('all provider adapters normalize into one failure-isolated contract', async () => {
  const fetcher = async (input, init = {}) => {
    const url = new URL(input);
    if (url.hostname === 'stac.test') {
      const request = JSON.parse(init.body ?? '{}');
      const collection = request.collections?.[0];
      return json({ features: [{
        id: `${collection}-item`,
        properties: { datetime: '2026-08-02T02:00:00Z', 'eo:cloud_cover': 12 },
        links: [{ rel: 'self', href: `https://stac.test/items/${collection}` }],
      }] });
    }
    if (url.hostname === 'cams.test' || url.hostname === 'notices.test' || url.hostname === 'marine.test') {
      const id = url.hostname.split('.')[0];
      const kind = id === 'cams'
        ? 'aerosolOpticalDepth'
        : id === 'notices'
          ? 'closure'
          : 'significantWaveHeight';
      return json({ signals: [{
        kind,
        title: `${id} ready`,
        summary: `${id} normalized provider signal`,
        verification: id === 'notices' ? 'authoritative' : 'model',
        observedAt: instant.toISOString(),
        expiresAt: new Date(instant.getTime() + 3_600_000).toISOString(),
        sourceUrl: `https://${url.hostname}/source`,
      }] });
    }
    if (url.hostname === 'aeronet.test') {
      return text([
        'AERONET Version 3',
        'AERONET_Site,Longitude,Latitude,Date(dd:mm:yyyy),Time(hh:mm:ss),AOD_500nm',
        'Hangzhou,120.1,30.2,03:08:2026,07:30:00,0.123',
      ].join('\n'));
    }
    if (url.hostname === 'overpass.test') {
      return json({ elements: [
        { tags: { tourism: 'viewpoint' } },
        { tags: { highway: 'path' } },
        { tags: { amenity: 'shelter' } },
        { tags: { historic: 'yes' } },
      ] });
    }
    if (url.hostname === 'wikidata.test') {
      return json({ results: { bindings: [
        { itemLabel: { value: '历史建筑甲' } },
        { itemLabel: { value: '非遗场馆乙' } },
      ] } });
    }
    if (url.hostname === 'commons.test') {
      return json({ query: { pages: [{ title: 'File:Example.jpg' }] } });
    }
    if (url.hostname === 'gbif.test') return json({ count: 421 });
    if (url.hostname === 'inaturalist.test') {
      assert.equal(url.searchParams.get('taxon_id'), '3');
      assert.equal(url.searchParams.get('quality_grade'), 'research');
      assert.equal(url.searchParams.get('captive'), 'false');
      assert.equal(url.searchParams.get('d1'), '2026-05-05');
      return json({
        total_results: 48,
        results: [
          { taxon: { id: 101 }, observed_on: '2026-08-02', user: { login: 'private' }, geojson: { coordinates: [120.1, 30.2] } },
          { taxon: { id: 102 }, time_observed_at: '2026-08-03T06:30:00Z', photos: [{ url: 'https://example.invalid/photo.jpg' }] },
        ],
      });
    }
    if (url.hostname === 'ebird.test') return json([
      { sciName: 'Ardea alba', obsDt: '2026-08-03 07:00' },
      { sciName: 'Passer montanus', obsDt: '2026-08-03 06:00' },
    ]);
    if (url.hostname === 'firms.test') {
      return text('latitude,longitude,frp,acq_date,acq_time\n30.3,120.2,7.5,2026-08-03,0730\n');
    }
    if (url.hostname === 'horizons.test') return json({ result: '$$SOE\nrow\n$$EOE' });
    if (url.hostname === 'swpc.test') return json([
      ['time_tag', 'Kp'],
      ['2026-08-03T07:00:00Z', '4.0'],
    ]);
    throw new Error(`unexpected ${url}`);
  };

  const service = new ProviderFactsService({
    fetcher,
    now: () => instant,
    configuration: () => ({ enabledProviders: [...supportedProviderIds] }),
    sentinelStacBaseUrl: 'https://stac.test/v1',
    camsGatewayUrl: 'https://cams.test/facts',
    aeronetBaseUrl: 'https://aeronet.test',
    officialNoticeGatewayUrl: 'https://notices.test/facts',
    overpassUrl: 'https://overpass.test/api/interpreter',
    wikidataEndpoint: 'https://wikidata.test/sparql',
    commonsApiUrl: 'https://commons.test/w/api.php',
    gbifBaseUrl: 'https://gbif.test',
    inaturalistBaseUrl: 'https://inaturalist.test',
    ebirdBaseUrl: 'https://ebird.test',
    ebirdToken: 'ebird-token',
    firmsBaseUrl: 'https://firms.test',
    firmsMapKey: 'firms-key',
    marineGatewayUrl: 'https://marine.test/facts',
    horizonsBaseUrl: 'https://horizons.test',
    swpcBaseUrl: 'https://swpc.test',
  });
  const result = await service.facts(query());
  assert.equal(result.contractVersion, 1);
  assert.equal(result.status, 'ready');
  assert.equal(result.providers.length, supportedProviderIds.length);
  assert.deepEqual(result.providers.map((item) => item.id), supportedProviderIds);
  assert.ok(result.providers.every((item) => item.status === 'ready'));
  assert.ok(result.providers.every((item) => item.signals.length > 0));
});

test('credentials stay server-side and missing providers degrade without blocking public sources', async () => {
  const service = new ProviderFactsService({
    now: () => instant,
    fetcher: async (input) => {
      const url = new URL(input);
      if (url.hostname === 'overpass.test') return json({ elements: [{ tags: { highway: 'path' } }] });
      throw new Error('offline');
    },
    sentinelStacBaseUrl: 'https://stac.test/v1',
    aeronetBaseUrl: 'https://aeronet.test',
    overpassUrl: 'https://overpass.test/api/interpreter',
    wikidataEndpoint: 'https://wikidata.test/sparql',
    commonsApiUrl: 'https://commons.test/w/api.php',
    gbifBaseUrl: 'https://gbif.test',
    inaturalistBaseUrl: 'https://inaturalist.test',
    ebirdBaseUrl: 'https://ebird.test',
    ebirdToken: '',
    firmsBaseUrl: 'https://firms.test',
    firmsMapKey: '',
    horizonsBaseUrl: 'https://horizons.test',
    swpcBaseUrl: 'https://swpc.test',
  });
  const result = await service.facts(query('osm,ebird,firms,cams,copernicusMarine'));
  assert.equal(result.status, 'partial');
  assert.equal(result.providers.find((item) => item.id === 'osm').status, 'ready');
  assert.equal(result.providers.find((item) => item.id === 'ebird').status, 'unconfigured');
  assert.equal(result.providers.find((item) => item.id === 'firms').status, 'unconfigured');
  assert.equal(result.providers.find((item) => item.id === 'cams').status, 'unconfigured');
  assert.equal(result.providers.find((item) => item.id === 'copernicusMarine').status, 'unconfigured');
});


test('dynamic provider configuration, health and Sentinel derivatives stay traceable', async () => {
  let configuration = {
    enabled: true,
    enabledProviders: [...supportedProviderIds],
    timeoutMs: 8000,
    sentinelStacBaseUrl: 'https://stac.dynamic/v1',
    sentinelRasterGatewayUrl: 'https://raster.dynamic/facts',
    sentinelRasterToken: 'raster-token',
    camsGatewayUrl: '', camsApiKey: '',
    aeronetBaseUrl: 'https://aeronet.dynamic',
    officialNoticeGatewayUrl: '', officialNoticeGatewayToken: '', officialNoticeSources: [],
    overpassUrl: 'https://overpass.dynamic', wikidataEndpoint: 'https://wikidata.dynamic',
    commonsApiUrl: 'https://commons.dynamic', gbifBaseUrl: 'https://gbif.dynamic',
    inaturalistBaseUrl: 'https://inaturalist.dynamic',
    ebirdBaseUrl: 'https://ebird.dynamic', ebirdToken: '',
    firmsBaseUrl: 'https://firms.dynamic', firmsMapKey: '',
    marineGatewayUrl: '', marineApiKey: '',
    horizonsBaseUrl: 'https://horizons.dynamic', swpcBaseUrl: 'https://swpc.dynamic',
  };
  const service = new ProviderFactsService({
    now: () => instant,
    configuration: () => configuration,
    fetcher: async (input, init = {}) => {
      const url = new URL(input);
      if (url.hostname === 'stac.dynamic') return json({ features: [{
        properties: { datetime: '2026-08-02T02:00:00Z', 'eo:cloud_cover': 8 },
        links: [{ rel: 'self', href: 'https://stac.dynamic/item' }],
      }] });
      if (url.hostname === 'raster.dynamic') {
        assert.equal(init.headers.Authorization, 'Bearer raster-token');
        return json({ observations: [{
          metric: 'ndvi', delta: 0.123, cloudCoverage: 8,
          spatialResolutionMeters: 10, confidence: 'high',
          comparisonStart: '2026-07-15T00:00:00Z', comparisonEnd: '2026-08-02T00:00:00Z',
          observedAt: '2026-08-02T02:00:00Z', expiresAt: '2026-08-04T02:00:00Z',
          sourceUrl: 'https://raster.dynamic/observations/1',
        }] });
      }
      throw new Error('offline');
    },
  });
  const result = await service.facts(query('sentinel2'));
  const signals = result.providers[0].signals;
  assert.equal(signals[0].kind, 'vegetationIndexChange');
  assert.match(signals[0].summary, /不代表现场已进入最佳状态/);
  const health = service.healthSnapshot();
  assert.equal(health.providers.find((item) => item.id === 'sentinel2').lastStatus, 'ready');
  configuration = { ...configuration, enabledProviders: [] };
  const disabled = await service.testProvider({ providerId: 'sentinel2', latitude: 30.25, longitude: 120.15 });
  assert.equal(disabled.status, 'unconfigured');
});

test('only authoritative current operational notices are promoted to Context warnings', async () => {
  const service = new ProviderFactsService({
    now: () => instant,
    officialNoticeGatewayUrl: 'https://notices.safe/facts',
    fetcher: async (input) => {
      const url = new URL(input);
      if (url.hostname !== 'notices.safe') throw new Error('unexpected');
      return json({ signals: [
        { kind: 'closure', title: '景区临时关闭', summary: '官方公告确认当前关闭。', verification: 'authoritative', observedAt: instant.toISOString(), expiresAt: '2026-08-04T08:00:00Z', sourceUrl: 'https://notices.safe/closure' },
        { kind: 'eventChange', title: '演出改期', summary: '演出时间调整。', verification: 'authoritative', observedAt: instant.toISOString(), expiresAt: '2026-08-04T08:00:00Z', sourceUrl: 'https://notices.safe/event' },
      ] });
    },
  });
  const warnings = await service.authoritativeSafetyNotices(query('officialNotices'));
  assert.equal(warnings.length, 1);
  assert.match(warnings[0].id, /^[a-f0-9]{12}$/);
  assert.equal(warnings[0].title, '景区临时关闭');
});


test('iNaturalist exposes bounded aggregate evidence without raw observation data', async () => {
  let requestedUrl;
  const service = new ProviderFactsService({
    now: () => instant,
    inaturalistBaseUrl: 'https://inaturalist.privacy',
    fetcher: async (input) => {
      requestedUrl = new URL(input);
      return json({
        total_results: 2750,
        results: [
          {
            id: 999,
            taxon: { id: 3, name: 'Aves' },
            observed_on: '2026-08-02',
            user: { login: 'observer-name' },
            geojson: { coordinates: [120.12345, 30.23456] },
            photos: [{ url: 'https://example.invalid/private-media.jpg' }],
            description: 'raw observer note',
          },
        ],
      });
    },
  });
  const result = await service.facts(query('inaturalist'));
  const provider = result.providers[0];
  const serialized = JSON.stringify(provider);
  assert.equal(provider.status, 'ready');
  assert.equal(provider.signals[0].verification, 'candidate');
  assert.deepEqual(provider.signals[0].attributes, {
    observationCount: 1000,
    sampledTaxaCount: 1,
    lookbackDays: 90,
  });
  assert.equal(serialized.includes('observer-name'), false);
  assert.equal(serialized.includes('120.12345'), false);
  assert.equal(serialized.includes('private-media'), false);
  assert.equal(serialized.includes('raw observer note'), false);
  assert.equal(provider.signals[0].sourceUrl.includes('lat='), false);
  assert.equal(requestedUrl.searchParams.get('taxon_id'), '3');
  assert.equal(requestedUrl.searchParams.get('quality_grade'), 'research');
});
