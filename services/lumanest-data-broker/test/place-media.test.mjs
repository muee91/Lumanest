import assert from 'node:assert/strict';
import test from 'node:test';

import {
  decodedVerifiedMediaUrl,
  parsePlaceMediaRequest,
  searchVerifiedPlaceMedia,
} from '../src/discovery/place-media.mjs';

const request = Object.freeze({
  name: '长山河生态湿地公园',
  city: '嘉兴市',
  latitude: 30.6842,
  longitude: 120.7281,
});

function commonsResponse(pages) {
  return new Response(JSON.stringify({ query: { pages } }), {
    status: 200,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

test('place media request requires an exact name and valid coordinate', () => {
  const valid = parsePlaceMediaRequest(new URLSearchParams({
    name: request.name,
    city: request.city,
    lat: `${request.latitude}`,
    lon: `${request.longitude}`,
  }));
  assert.deepEqual(valid, { ...request, poiId: null });
  assert.equal(parsePlaceMediaRequest(new URLSearchParams({
    name: '湿地', lat: '91', lon: '120',
  })), null);
});

test('verified media accepts exact place-name evidence and exposes only a broker proxy', async () => {
  const result = await searchVerifiedPlaceMedia({
    request,
    fetcher: async () => commonsResponse([{
      pageid: 42,
      title: 'File:长山河生态湿地公园.jpg',
      imageinfo: [{
        mime: 'image/jpeg',
        thumburl: 'https://upload.wikimedia.org/example/wetland.jpg',
        extmetadata: {
          ImageDescription: { value: '嘉兴市长山河生态湿地公园' },
          Artist: { value: '<b>Example photographer</b>' },
          LicenseShortName: { value: 'CC BY-SA 4.0' },
        },
      }],
    }]),
  });
  assert.equal(result.ok, true);
  assert.equal(result.media[0].attribution, 'Wikimedia Commons');
  assert.equal(result.media[0].sourceTier, 'primary');
  assert.equal(result.media[0].matchBasis, 'name');
  assert.equal(result.media[0].creator, 'Example photographer');
  assert.match(result.media[0].proxyPath, /^\/v1\/explore\/media\/[A-Za-z0-9_-]+$/);
  assert.equal('url' in result.media[0], false);
  const token = result.media[0].proxyPath.split('/').at(-1);
  assert.equal(
    decodedVerifiedMediaUrl(token).toString(),
    'https://upload.wikimedia.org/example/wetland.jpg',
  );
});

test('verified media rejects a visually plausible but unrelated search result', async () => {
  const result = await searchVerifiedPlaceMedia({
    request,
    fetcher: async () => commonsResponse([{
      pageid: 99,
      title: 'File:Generic wetland sunset.jpg',
      imageinfo: [{
        mime: 'image/jpeg',
        thumburl: 'https://upload.wikimedia.org/example/unrelated.jpg',
        extmetadata: {
          ImageDescription: { value: '某地湿地日落' },
        },
      }],
    }]),
  });
  assert.deepEqual(result, { ok: true, media: [] });
});

test('verified media rejects a nearby photo that does not name the requested POI', async () => {
  const result = await searchVerifiedPlaceMedia({
    request,
    fetcher: async () => commonsResponse([{
      pageid: 100,
      title: 'File:Wetland boardwalk.jpg',
      coordinates: [{ lat: 30.6844, lon: 120.7283 }],
      imageinfo: [{
        mime: 'image/webp',
        thumburl: 'https://upload.wikimedia.org/example/nearby.webp',
        extmetadata: {},
      }],
    }]),
  });
  assert.deepEqual(result, { ok: true, media: [] });
});

test('verified media retains multiple independently named Commons photos', async () => {
  const result = await searchVerifiedPlaceMedia({
    request,
    fetcher: async () => commonsResponse([42, 43].map((pageid) => ({
      pageid,
      title: `File:嘉兴市长山河生态湿地公园-${pageid}.jpg`,
      imageinfo: [{
        mime: 'image/jpeg',
        thumburl: `https://upload.wikimedia.org/example/wetland-${pageid}.jpg`,
        extmetadata: { ImageDescription: { value: '嘉兴市长山河生态湿地公园' } },
      }],
    }))),
  });

  assert.equal(result.media.length, 2);
  assert.equal(result.media.every((item) => item.sourceTier === 'primary'), true);
});

test('Wikidata failure does not discard an already verified Commons image', async () => {
  const result = await searchVerifiedPlaceMedia({
    request,
    fetcher: async (url) => {
      if (url.hostname === 'www.wikidata.org') throw new Error('offline');
      return commonsResponse([{
        pageid: 44,
        title: 'File:长山河生态湿地公园.jpg',
        imageinfo: [{
          mime: 'image/jpeg',
          thumburl: 'https://upload.wikimedia.org/example/verified.jpg',
          extmetadata: { ImageDescription: { value: '嘉兴市长山河生态湿地公园' } },
        }],
      }]);
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.media.length, 1);
  assert.equal(result.media[0].matchBasis, 'name');
});

test('verified media resolves translated Commons titles through a coordinate-bound Wikidata entity', async () => {
  const calls = [];
  const result = await searchVerifiedPlaceMedia({
    request: {
      name: '天安门',
      city: '北京市',
      latitude: 39.907354,
      longitude: 116.391220,
    },
    fetcher: async (url) => {
      calls.push(url);
      if (url.hostname === 'www.wikidata.org' && url.searchParams.get('action') === 'wbsearchentities') {
        return new Response(JSON.stringify({
          search: [{ id: 'Q83973', label: '天安门' }],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (url.hostname === 'www.wikidata.org' && url.searchParams.get('action') === 'wbgetentities') {
        return new Response(JSON.stringify({
          entities: {
            Q83973: {
              id: 'Q83973',
              labels: {
                zh: { value: '天安门' },
                en: { value: 'Tiananmen' },
              },
              aliases: {},
              claims: {
                P18: [{ mainsnak: { datavalue: { value: 'Tiananmen night.jpg' } } }],
                P625: [{ mainsnak: { datavalue: { value: {
                  latitude: 39.90735,
                  longitude: 116.39122,
                } } } }],
              },
            },
          },
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (url.hostname === 'commons.wikimedia.org' && url.searchParams.has('titles')) {
        return commonsResponse([{
          pageid: 501,
          title: 'File:Tiananmen night.jpg',
          imageinfo: [{
            mime: 'image/jpeg',
            thumburl: 'https://upload.wikimedia.org/example/tiananmen-night.jpg',
            extmetadata: { LicenseShortName: { value: 'CC BY-SA 4.0' } },
          }],
        }]);
      }
      if (url.hostname === 'commons.wikimedia.org' &&
          url.searchParams.get('gsrsearch') === 'haswbstatement:P180=Q83973 filetype:bitmap') {
        return commonsResponse([{
          pageid: 502,
          title: 'File:Tiananmen gate.jpg',
          imageinfo: [{
            mime: 'image/jpeg',
            thumburl: 'https://upload.wikimedia.org/example/tiananmen-gate.jpg',
            extmetadata: {},
          }],
        }]);
      }
      return commonsResponse([]);
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.media.length, 2);
  assert.equal(result.media.every((item) => item.matchBasis === 'wikidataEntity'), true);
  assert.equal(result.media.every((item) => item.sourceTier === 'primary'), true);
  assert.equal(calls.some((url) => url.hostname === 'www.wikidata.org'), true);
});

test('verified media proxy token rejects arbitrary hosts', () => {
  const token = Buffer.from('https://images.example.com/wrong.jpg').toString('base64url');
  assert.equal(decodedVerifiedMediaUrl(token), null);
});
