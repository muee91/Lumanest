import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const publicRoot = new URL('../src/admin/public/', import.meta.url);

test('provider console exposes ecology roles and outcome counters', async () => {
  const [html, script] = await Promise.all([
    readFile(new URL('index.html', publicRoot), 'utf8'),
    readFile(new URL('providers.js', publicRoot), 'utf8'),
  ]);
  assert.match(html, /name="inaturalistBaseUrl"/);
  assert.match(html, /iNaturalist 近期自然观察/);
  assert.match(html, /eBird（可选）/);
  assert.match(html, /缺失不会影响默认 Provider Hub 健康度/);
  assert.match(script, /'inaturalistBaseUrl'/);
  assert.match(script, /item\.readyTotal/);
  assert.match(script, /item\.noDataTotal/);
  assert.match(script, /item\.unavailableTotal/);
  assert.match(script, /item\.unconfiguredTotal/);
});
