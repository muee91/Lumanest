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
  assert.match(html, /name="currentPassword"/);
  assert.match(html, /name="newPassword"/);
  assert.match(html, /name="confirmPassword"/);
  assert.match(html, /留空表示不修改/);
  assert.doesNotMatch(html, /sk-[A-Za-z0-9]/);
  assert.doesNotMatch(html, /AK[A-Za-z0-9]{8}/);
});

test('overview presents an operational dashboard without claiming health before config loads', async () => {
  const html = await readFile(new URL('index.html', publicRoot), 'utf8');
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.match(html, /class="dashboard-hero"/);
  assert.match(html, /id="configured-count"/);
  assert.match(html, /id="ai-state"/);
  assert.match(html, /id="sky-opportunity-state"/);
  assert.match(html, /id="broker-status">正在连接/);
  assert.match(html, /id="service-status-list"/);
  assert.match(html, /id="runtime-summary"/);
  assert.match(html, /id="capability-grid"/);
  assert.match(html, /id="refresh-overview"/);
  assert.match(script, /api\('health'\)/);
  assert.match(script, /renderBrokerHealth/);
  assert.doesNotMatch(script, /\$\('#broker-status'\)\.textContent='在线'/);
  assert.match(script, /qweatherPrivateKey\?\.configured&&config\.services\.keyId\?\.configured&&config\.services\.projectId\?\.configured/);
  assert.match(script, /appendServiceRow/);
  assert.match(script, /appendCapability/);
  assert.doesNotMatch(html, /canvas|sparkline|chart/);
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
  assert.match(script, /invalid_credentials:'密码不正确'/);
  assert.match(script, /登录服务暂不可用，请检查 Broker 状态/);
  assert.match(script, /state\.csrf=result\.csrfToken/);
  assert.match(script, /const form=event\.currentTarget/);
  assert.match(script, /body:\{password:form\.elements\.password\.value\}/);
  assert.doesNotMatch(script, /await api\('login',[\s\S]{0,500}event\.currentTarget/);
  assert.match(
    script,
    /try\{await Promise\.all\(\[loadConfig\(\),loadCapabilities\(\)\]\);\}catch\{status\('登录成功，但控制台状态加载失败，请刷新页面'\);\}/,
  );
});

test('password UI distinguishes credential, confirmation and service failures', async () => {
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.match(script, /invalid_current_password:'当前密码不正确'/);
  assert.match(script, /password_mismatch:'两次输入的新密码不一致'/);
  assert.match(script, /登录服务暂不可用，请检查 Broker 状态/);
  assert.match(script, /body:\{currentPassword,newPassword,confirmPassword\}/);
  assert.match(script, /value\.error==='unauthenticated'\)showLogin/);
  assert.doesNotMatch(script, /response\.status===401&&path!=='login'\)showLogin/);
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

test('settings pages use grouped compact controls without changing form contracts', async () => {
  const html = await readFile(new URL('index.html', publicRoot), 'utf8');
  assert.match(html, /class="credential-layout"/);
  assert.match(html, /class="advanced-settings"/);
  assert.match(html, /class="settings-group policy-editor"/);
  assert.match(html, /class="runtime-grid"/);
  assert.match(html, /class="setting-row"/);
  assert.match(html, /class="sunset-layout"/);
  assert.match(html, /class="security-layout"/);
  assert.match(html, /class="password-fields"/);
  for (const name of [
    'keyId', 'projectId', 'qweatherPrivateKeyPem', 'amapWebKey', 'serviceToken',
    'aiEnabled', 'assistantWebSearchEnabled', 'aiTimeoutMs', 'sunsetbotProviderEnabled', 'debugLogging',
    'currentPassword', 'newPassword', 'confirmPassword',
  ]) {
    assert.equal((html.match(new RegExp(`name="${name}"`, 'g')) ?? []).length, 1, name);
  }
});

test('developer tools stay hidden until the authenticated capability is enabled', async () => {
  const html = await readFile(new URL('index.html', publicRoot), 'utf8');
  const script = await readFile(new URL('app.js', publicRoot), 'utf8');
  assert.match(html, /id="developer-tools-label"[^>]+hidden/);
  assert.match(html, /id="simulation-nav"[^>]+hidden/);
  assert.match(html, /场景实验室/);
  assert.match(html, /模拟快照不会进入真实缓存、Companion 记忆或反馈校准/);
  assert.match(script, /api\('capabilities'\)/);
  assert.match(script, /api\('simulation'\)/);
  assert.match(script, /simulation\/sessions\/\$\{session\.controlId\}/);
  assert.match(script, /clear-all-simulations/);
  assert.doesNotMatch(html, /<option value="lake-sunset"/);
});
