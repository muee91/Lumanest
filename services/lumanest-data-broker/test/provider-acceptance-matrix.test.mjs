import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const locations = JSON.parse(await readFile(new URL('./fixtures/provider-acceptance-locations.json', import.meta.url)));
const allowedScenes = new Set(['city', 'lake', 'mountain', 'desert', 'village']);
const allowedCategories = new Set(['surface', 'atmosphere', 'operations', 'outdoor', 'culture', 'wildlife', 'fire', 'marine', 'astronomy', 'spaceWeather']);

test('provider acceptance matrix covers ten distinct real-world travel scenes', () => {
  assert.equal(locations.length, 10);
  assert.equal(new Set(locations.map((item) => item.id)).size, locations.length);
  assert.equal(new Set(locations.map((item) => item.name)).size, locations.length);
  for (const item of locations) {
    assert.equal(Number.isFinite(item.latitude) && item.latitude >= -90 && item.latitude <= 90, true);
    assert.equal(Number.isFinite(item.longitude) && item.longitude >= -180 && item.longitude <= 180, true);
    assert.equal(allowedScenes.has(item.scene), true);
    assert.equal(item.categories.length >= 4, true);
    assert.equal(item.categories.every((category) => allowedCategories.has(category)), true);
    assert.equal(item.categories.includes('operations'), true);
  }
});
