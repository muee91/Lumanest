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
  assert.deepEqual(valid, request);
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
  assert.equal(result.media.attribution, 'Wikimedia Commons');
  assert.equal(result.media.matchBasis, 'name');
  assert.equal(result.media.creator, 'Example photographer');
  assert.match(result.media.proxyPath, /^\/v1\/explore\/media\/[A-Za-z0-9_-]+$/);
  assert.equal('url' in result.media, false);
  const token = result.media.proxyPath.split('/').at(-1);
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
  assert.deepEqual(result, { ok: true, media: null });
});

test('verified media accepts a geotagged photo close to the requested POI', async () => {
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
  assert.equal(result.media.matchBasis, 'coordinate');
});

test('verified media proxy token rejects arbitrary hosts', () => {
  const token = Buffer.from('https://images.example.com/wrong.jpg').toString('base64url');
  assert.equal(decodedVerifiedMediaUrl(token), null);
});
