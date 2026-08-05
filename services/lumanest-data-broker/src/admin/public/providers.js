(() => {
  const providerState = {
    csrf: null,
    catalog: [],
    configuration: null,
    health: null,
    initialized: false,
    loading: false,
  };
  const $ = (selector) => document.querySelector(selector);

  async function providerApi(path, { method = 'GET', body } = {}) {
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (method !== 'GET' && providerState.csrf) headers['X-CSRF-Token'] = providerState.csrf;
    const response = await fetch(`/admin-api/${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const value = await response.json().catch(() => ({ error: 'invalid_response' }));
    if (!response.ok) throw new Error(value.error ?? 'request_failed');
    return value;
  }

  function setProviderStatus(message) {
    const node = $('#provider-console-status');
    if (node) node.textContent = message;
    const global = $('#global-status');
    if (global && message) global.textContent = message;
  }

  function maskText(value) {
    return value?.configured
      ? `已配置 ···· ${value.lastFour ?? ''}`.trim()
      : '尚未配置';
  }

  function renderEnabledProviders(configuration) {
    const root = $('#provider-enabled-list');
    if (!root) return;
    root.replaceChildren();
    const enabled = new Set(configuration.enabledProviders ?? []);
    for (const provider of providerState.catalog) {
      const label = document.createElement('label');
      label.className = 'fallback-choice';
      const input = document.createElement('input');
      input.type = 'checkbox';
      input.name = 'enabledProvider';
      input.value = provider.id;
      input.checked = enabled.has(provider.id);
      const text = document.createElement('span');
      text.textContent = provider.label;
      label.append(input, text);
      root.append(label);
    }
  }

  const urlFields = [
    'sentinelStacBaseUrl',
    'sentinelRasterGatewayUrl',
    'camsGatewayUrl',
    'aeronetBaseUrl',
    'officialNoticeGatewayUrl',
    'overpassUrl',
    'wikidataEndpoint',
    'commonsApiUrl',
    'gbifBaseUrl',
    'inaturalistBaseUrl',
    'ebirdBaseUrl',
    'firmsBaseUrl',
    'marineGatewayUrl',
    'horizonsBaseUrl',
    'swpcBaseUrl',
  ];
  const secretFields = [
    'sentinelRasterToken',
    'camsApiKey',
    'officialNoticeGatewayToken',
    'ebirdToken',
    'firmsMapKey',
    'marineApiKey',
  ];

  function renderProviderConfiguration(configuration) {
    providerState.configuration = configuration;
    const form = $('#provider-sources-form');
    if (!form) return;
    form.elements.enabled.checked = configuration.enabled !== false;
    form.elements.timeoutMs.value = String(configuration.timeoutMs ?? 8_000);
    for (const name of urlFields) {
      if (form.elements[name]) form.elements[name].value = configuration[name] ?? '';
    }
    for (const name of secretFields) {
      if (form.elements[name]) form.elements[name].value = '';
      const mask = document.querySelector(`[data-provider-mask="${name}"]`);
      if (mask) mask.textContent = maskText(configuration[name]);
    }
    form.elements.officialNoticeSources.value = JSON.stringify(
      configuration.officialNoticeSources ?? [],
      null,
      2,
    );
    renderEnabledProviders(configuration);
  }

  function providerHealthLabel(item) {
    const status = item?.lastStatus ?? (item?.configured ? 'unknown' : 'unconfigured');
    const labels = {
      ready: '可用',
      noData: '暂无数据',
      unconfigured: '未配置',
      unavailable: '暂不可用',
      disabled: '已关闭',
      unknown: '未检测',
    };
    return labels[status] ?? '未检测';
  }

  function providerTone(item) {
    const status = item?.lastStatus;
    if (status === 'ready' || status === 'noData') return 'ready';
    if (!item?.configured || status === 'disabled') return 'disabled';
    return 'attention';
  }

  function renderProviderHealth(health) {
    providerState.health = health;
    const root = $('#provider-health-list');
    if (root) {
      root.replaceChildren();
      for (const item of health.providers ?? []) {
        const row = document.createElement('article');
        row.className = 'service-status-row';
        const identity = document.createElement('div');
        identity.className = 'service-identity';
        const mark = document.createElement('span');
        mark.className = `service-mark ${providerTone(item)}`;
        mark.textContent = item.label?.slice(0, 1) ?? item.id.slice(0, 1).toUpperCase();
        const copy = document.createElement('div');
        const title = document.createElement('strong');
        title.textContent = item.label ?? item.id;
        const detail = document.createElement('small');
        const latency = item.lastLatencyMs == null ? '—' : `${item.lastLatencyMs} ms`;
        const success = item.lastSuccessAt
          ? new Date(item.lastSuccessAt).toLocaleString('zh-CN', { hour12: false })
          : '尚无成功记录';
        const runs = item.requestTotal ?? 0;
        const ready = item.readyTotal ?? 0;
        const noData = item.noDataTotal ?? 0;
        const unavailable = item.unavailableTotal ?? 0;
        const unconfigured = item.unconfiguredTotal ?? 0;
        const outcomes = runs === 0
          ? '尚未运行'
          : `运行 ${runs} · 就绪 ${ready} · 无数据 ${noData} · 不可用 ${unavailable} · 未配置 ${unconfigured}`;
        detail.textContent = `${success} · 最近 ${latency} · ${outcomes} · 信号 ${item.lastSignalCount ?? 0}`;
        copy.append(title, detail);
        identity.append(mark, copy);
        const state = document.createElement('span');
        state.className = `service-state ${providerTone(item)}`;
        state.textContent = providerHealthLabel(item);
        row.append(identity, state);
        root.append(row);
      }
    }
    const summary = $('#provider-health-summary');
    if (summary) {
      const configured = (health.providers ?? []).filter((item) => item.configured).length;
      const ready = (health.providers ?? []).filter((item) =>
        item.lastStatus === 'ready' || item.lastStatus === 'noData').length;
      summary.textContent = `${configured}/${health.providers?.length ?? 0} 已配置 · ${ready} 个最近可达 · 缓存命中 ${health.cache?.hits ?? 0}`;
    }
    renderOverviewProviderRow();
  }

  function renderOverviewProviderRow() {
    const list = $('#service-status-list');
    if (!list || !providerState.configuration) return;
    let row = $('#provider-hub-overview-row');
    if (!row) {
      row = document.createElement('article');
      row.id = 'provider-hub-overview-row';
      row.className = 'service-status-row';
      const identity = document.createElement('div');
      identity.className = 'service-identity';
      const mark = document.createElement('span');
      mark.className = 'service-mark attention';
      mark.textContent = 'P';
      const copy = document.createElement('div');
      const title = document.createElement('strong');
      title.textContent = 'Provider Hub';
      const detail = document.createElement('small');
      copy.append(title, detail);
      identity.append(mark, copy);
      const state = document.createElement('span');
      state.className = 'service-state attention';
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'row-action';
      button.dataset.target = 'services';
      button.textContent = '管理';
      row.append(identity, state, button);
      list.append(row);
    }
    const providers = providerState.health?.providers ?? [];
    const configured = providers.filter((item) => item.configured).length;
    const ready = providers.filter((item) =>
      item.lastStatus === 'ready' || item.lastStatus === 'noData').length;
    const enabled = providerState.configuration.enabled !== false;
    const tone = !enabled ? 'disabled' : ready > 0 ? 'ready' : configured > 0 ? 'attention' : 'disabled';
    row.querySelector('.service-mark').className = `service-mark ${tone}`;
    row.querySelector('.service-state').className = `service-state ${tone}`;
    row.querySelector('.service-state').textContent = !enabled ? '已关闭' : ready > 0 ? '链路运行中' : configured > 0 ? '等待检测' : '等待配置';
    row.querySelector('.service-identity small').textContent = `${configured}/${providers.length || providerState.catalog.length} 已配置 · ${ready} 个最近可达`;
  }

  async function loadProviderConsole() {
    if (providerState.loading) return;
    providerState.loading = true;
    try {
      const session = await providerApi('session');
      providerState.csrf = session.csrfToken;
      const [config, health] = await Promise.all([
        providerApi('config'),
        providerApi('providers/health'),
      ]);
      providerState.catalog = config.providers?.catalog ?? [];
      renderProviderConfiguration(config.providers?.configuration ?? {});
      renderProviderHealth(health);
      providerState.initialized = true;
      setProviderStatus('');
    } catch {
      providerState.initialized = false;
    } finally {
      providerState.loading = false;
    }
  }

  function providerPatch(form) {
    let officialNoticeSources;
    try {
      officialNoticeSources = JSON.parse(form.elements.officialNoticeSources.value || '[]');
    } catch {
      throw new Error('invalid_notice_sources');
    }
    if (!Array.isArray(officialNoticeSources)) throw new Error('invalid_notice_sources');
    const patch = {
      enabled: form.elements.enabled.checked,
      enabledProviders: [...form.querySelectorAll('input[name="enabledProvider"]:checked')]
        .map((input) => input.value),
      timeoutMs: Number(form.elements.timeoutMs.value),
      officialNoticeSources,
    };
    for (const name of urlFields) patch[name] = form.elements[name]?.value.trim() ?? '';
    for (const name of secretFields) {
      const value = form.elements[name]?.value.trim();
      if (value) patch[name] = value;
    }
    return patch;
  }

  function bindProviderActions() {
    const form = $('#provider-sources-form');
    if (form && !form.dataset.bound) {
      form.dataset.bound = 'true';
      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        try {
          setProviderStatus('正在加密并应用 Provider 配置…');
          const result = await providerApi('config', {
            method: 'PUT',
            body: { providerSources: providerPatch(form) },
          });
          providerState.catalog = result.providers?.catalog ?? providerState.catalog;
          renderProviderConfiguration(result.providers?.configuration ?? {});
          setProviderStatus('Provider 配置已生效；密钥未返回浏览器');
          await refreshProviderHealth();
        } catch (error) {
          setProviderStatus(error.message === 'invalid_notice_sources'
            ? '官方公告源必须是有效 JSON 数组'
            : 'Provider 配置未保存，请检查 HTTPS 地址、范围和字段');
        }
      });
    }

    const refresh = $('#refresh-provider-health');
    if (refresh && !refresh.dataset.bound) {
      refresh.dataset.bound = 'true';
      refresh.addEventListener('click', async () => {
        refresh.disabled = true;
        try {
          await refreshProviderHealth();
          setProviderStatus('Provider 健康状态已刷新');
        } catch {
          setProviderStatus('Provider 健康状态读取失败');
        } finally {
          refresh.disabled = false;
        }
      });
    }

    const testForm = $('#provider-test-form');
    if (testForm && !testForm.dataset.bound) {
      testForm.dataset.bound = 'true';
      testForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const button = event.submitter;
        button.disabled = true;
        try {
          const body = {
            providerId: testForm.elements.providerId.value,
            latitude: Number(testForm.elements.latitude.value),
            longitude: Number(testForm.elements.longitude.value),
            radiusKm: Number(testForm.elements.radiusKm.value),
          };
          setProviderStatus(`正在检测 ${body.providerId}…`);
          const result = await providerApi('providers/test', { method: 'POST', body });
          setProviderStatus(`${body.providerId}：${providerHealthLabel({ lastStatus: result.status, configured: true })} · ${result.signalCount} 条信号 · ${result.latencyMs} ms · Trace ${result.traceId}`);
          await refreshProviderHealth();
        } catch (error) {
          setProviderStatus(`Provider 检测失败：${error.message}`);
        } finally {
          button.disabled = false;
        }
      });
    }
  }

  async function refreshProviderHealth() {
    renderProviderHealth(await providerApi('providers/health'));
  }

  function attemptInitialize() {
    bindProviderActions();
    const app = $('#app-view');
    if (!app || app.hidden) return;
    void loadProviderConsole();
  }

  document.addEventListener('DOMContentLoaded', attemptInitialize);
  const observer = new MutationObserver(attemptInitialize);
  observer.observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
  setInterval(() => {
    const app = $('#app-view');
    if (app && !app.hidden && !providerState.loading && !providerState.initialized) {
      void loadProviderConsole();
    }
  }, 2_000);
})();
