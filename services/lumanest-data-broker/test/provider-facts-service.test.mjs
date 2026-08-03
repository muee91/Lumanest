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
      return json({ signals: [{
        kind: `${id}Signal`,
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
    sentinelStacBaseUrl: 'https://stac.test/v1',
    camsGatewayUrl: 'https://cams.test/facts',
    aeronetBaseUrl: 'https://aeronet.test',
    officialNoticeGatewayUrl: 'https://notices.test/facts',
    overpassUrl: 'https://overpass.test/api/interpreter',
    wikidataEndpoint: 'https://wikidata.test/sparql',
    commonsApiUrl: 'https://commons.test/w/api.php',
    gbifBaseUrl: 'https://gbif.test',
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
