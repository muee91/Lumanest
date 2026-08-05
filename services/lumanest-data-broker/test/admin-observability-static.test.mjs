import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('admin observability surface is external-scripted and privacy explicit', async () => {
  const [html, script, css] = await Promise.all([
    readFile(new URL('../src/admin/public/index.html', import.meta.url), 'utf8'),
    readFile(new URL('../src/admin/public/observability.js', import.meta.url), 'utf8'),
    readFile(new URL('../src/admin/public/observability.css', import.meta.url), 'utf8'),
  ]);
  assert.match(html, /data-page="observability"/);
  assert.match(html, /data-panel="observability"/);
  assert.match(html, /\/admin-assets\/observability\.js/);
  assert.match(html, /不保存用户问题、精确坐标或原始事实文本/);
  assert.match(script, /fetch\(`\/admin-api\/\$\{path\}`\)/);
  assert.match(script, /api\('observability'\)/);
  assert.doesNotMatch(script, /innerHTML\s*=/);
  assert.match(css, /observability-summary/);
});