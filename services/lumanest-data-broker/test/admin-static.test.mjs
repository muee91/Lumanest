import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createAdminServer } from '../src/admin/admin-server.mjs';

const publicRoot = new URL('../src/admin/public/', import.meta.url);

function dependencies() {
  return {
    authService: {
      authenticate: async () => ({ ok: false, reason: 'unauthenticated' }),
      login: async () => ({ ok: false, reason: 'invalid_credentials' }),
    },
    runtimeConfig: {},
    auditLog: { record() {}, list: () => [] },
  };
}

test('admin listener serves the shell and local assets with a restrictive CSP', async () => {
  const server = createAdminServer(dependencies());
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/admin`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-security-policy'), /default-src 'self'/);
    assert.match(response.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    assert.match(response.headers.get('content-security-policy'), /form-action 'self'/);
    const html = await response.text();
    assert.match(html, /<script src="\/admin-assets\/app\.js" defer><\/script>/);
    assert.match(html, /<link rel="stylesheet" href="\/admin-assets\/styles\.css">/);
    assert.doesNotMatch(html, /<script(?![^>]+src=)/);
    assert.doesNotMatch(html, /style="/);
    const scriptResponse = await fetch(`${baseUrl}/admin-assets/app.js`);
    assert.equal(scriptResponse.headers.get('cache-control'), 'no-store');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('static UI has accessible auth/status regions and no secret placeholder values', async () => {
  const html = await readFile(new URL('index.html', publicRoot), 'utf8');
  assert.match(html, /<label[^>]+for="password"/);
  assert.match(html, /role="status"/);
  assert.match(html, /留空表示不修改/);
  assert.doesNotMatch(html, /sk-[A-Za-z0-9]/);
  assert.doesNotMatch(html, /AK[A-Za-z0-9]{8}/);
});

test('client rendering avoids HTML injection and browser-persisted secrets', async () => {
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.doesNotMatch(script, /innerHTML|outerHTML|document\.write/);
  assert.doesNotMatch(script, /localStorage/);
  assert.doesNotMatch(script, /sessionStorage\.setItem\([^,]+(?:password|key|token)/i);
  assert.match(script, /textContent/);
});

test('successful authentication is not relabeled as a password error when config loading fails', async () => {
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.match(
    script,
    /catch\(error\)\{[^}]*密码不正确[^}]*\}\s*state\.csrf=result\.csrfToken/s,
  );
  assert.match(
    script,
    /try\{await loadConfig\(\);\}catch\{status\('登录成功，但配置加载失败，请刷新页面'\);\}/,
  );
});

test('LLM console starts empty and requires explicit provider selection', async () => {
  const html = await readFile(new URL('index.html', publicRoot), 'utf8');
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.match(html, /模型服务/);
  assert.match(html, /id="llm-empty-state"/);
  assert.match(html, /id="provider-dialog"/);
  assert.match(html, /id="llm-profile-form"/);
  assert.match(html, /id="llm-routing-form"/);
  assert.match(html, /id="llm-model-select"/);
  assert.doesNotMatch(html, /<datalist/);
  assert.match(html, /选择供应商后再填写模型与密钥/);
  assert.doesNotMatch(html, /qwen-plus|通义千问 · 默认/);
  assert.match(script, /api\('llm\/providers'\)/);
  assert.match(script, /api\('llm\/profiles'\)/);
  assert.match(script, /api\('llm\/routing'/);
  assert.match(script, /api\('llm\/models'/);
  assert.match(script, /window\.confirm/);
});
