(() => {
  const state = { csrf: null, loading: false, initialized: false };
  const $ = (selector) => document.querySelector(selector);
  const percent = (value) => `${Math.round((Number(value) || 0) * 100)}%`;
  const number = (value) => new Intl.NumberFormat('zh-CN').format(Number(value) || 0);

  async function api(path) {
    const response = await fetch(`/admin-api/${path}`);
    const value = await response.json().catch(() => ({ error: 'invalid_response' }));
    if (!response.ok) throw new Error(value.error ?? 'request_failed');
    return value;
  }

  function text(id, value) {
    const node = $(`#${id}`);
    if (node) node.textContent = value;
  }

  function statusTone(status) {
    return ['ready', 'noData'].includes(status) ? 'ready'
      : ['disabled', 'unconfigured'].includes(status) ? 'disabled'
        : 'attention';
  }

  function renderSections(sections) {
    const root = $('#observability-section-list');
    if (!root) return;
    root.replaceChildren();
    for (const item of sections ?? []) {
      const row = document.createElement('div');
      row.className = 'observability-row';
      const label = document.createElement('strong');
      label.textContent = item.label;
      const bar = document.createElement('div');
      bar.className = 'observability-bar';
      const fill = document.createElement('i');
      fill.style.width = percent(item.hitRate);
      bar.append(fill);
      const value = document.createElement('span');
      value.textContent = `${percent(item.hitRate)} · ${number(item.hit)}/${number(item.requested)}`;
      row.append(label, bar, value);
      root.append(row);
    }
  }

  function renderComponents(components) {
    const root = $('#observability-context-components');
    if (!root) return;
    root.replaceChildren();
    const labels = {
      snapshot: '环境与拍摄窗口',
      route: '路线沿途',
      regionBrief: '区域简报',
      providers: '补充数据源',
    };
    for (const item of components ?? []) {
      const card = document.createElement('article');
      card.className = 'observability-component';
      const title = document.createElement('strong');
      title.textContent = labels[item.id] ?? item.id;
      const rate = document.createElement('b');
      rate.textContent = percent(item.readyRate);
      const detail = document.createElement('small');
      detail.textContent = `可用 ${number(item.ready)} · 缺失 ${number(item.unavailable)} · 不适用 ${number(item.notApplicable)}`;
      card.append(title, rate, detail);
      root.append(card);
    }
  }

  function renderRoute(route) {
    const root = $('#observability-route-list');
    if (!root) return;
    root.replaceChildren();
    const rows = [
      ['采样段覆盖', percent(route.segmentCoverageRate), `${number(route.supplyReferenceSegments)} 段有补给参考 · ${number(route.parkingReferenceSegments)} 段有停车参考`],
      ['官方管制证据', number(route.authoritativeRestrictions), `存在 ${number(route.restrictionsPresent)} 段 · 未检出 ${number(route.restrictionsNoneObserved)} 段 · 不可用 ${number(route.restrictionsUnavailable)} 段`],
      ['摄影语义参考', number(route.photographyReferenceSegments), '公开地图观景点与历史对象只作检索参考，不是已验证机位'],
    ];
    for (const [labelText, valueText, detailText] of rows) {
      const row = document.createElement('article');
      row.className = 'observability-component';
      const label = document.createElement('strong');
      label.textContent = labelText;
      const value = document.createElement('b');
      value.textContent = valueText;
      const detail = document.createElement('small');
      detail.textContent = detailText;
      row.append(label, value, detail);
      root.append(row);
    }
  }

  function renderProviders(providers) {
    const root = $('#observability-provider-list');
    if (!root) return;
    root.replaceChildren();
    for (const item of providers?.rows ?? []) {
      const row = document.createElement('article');
      row.className = 'service-status-row';
      const identity = document.createElement('div');
      identity.className = 'service-identity';
      const mark = document.createElement('span');
      mark.className = `service-mark ${statusTone(item.status)}`;
      mark.textContent = (item.label ?? item.id).slice(0, 1);
      const copy = document.createElement('div');
      const title = document.createElement('strong');
      title.textContent = item.label ?? item.id;
      const detail = document.createElement('small');
      detail.textContent = `请求 ${number(item.requestTotal)} · 成功 ${number(item.readyTotal)} · 不可用 ${number(item.unavailableTotal)} · 最近信号 ${number(item.lastSignalCount)}`;
      copy.append(title, detail);
      identity.append(mark, copy);
      const stateNode = document.createElement('span');
      stateNode.className = `service-state ${statusTone(item.status)}`;
      const labels = { ready: '可用', noData: '暂无数据', unavailable: '不可用', unconfigured: '未配置', disabled: '已关闭', unknown: '未检测' };
      stateNode.textContent = labels[item.status] ?? '未检测';
      row.append(identity, stateNode);
      root.append(row);
    }
  }

  function render(value) {
    const region = value.regionBrief ?? {};
    const context = value.assistantContext ?? {};
    const route = value.routeCorridor ?? {};
    const providers = value.providers ?? {};
    text('observability-updated', `同步于 ${new Date(value.checkedAt).toLocaleString('zh-CN', { hour12: false })}`);
    text('observability-brief-rate', percent(region.usableRate));
    text('observability-brief-detail', `${number(region.usable)}/${number(region.requests)} 次请求形成可用简报`);
    text('observability-expansion-rate', percent(region.manualExpansionValueRate));
    text('observability-expansion-detail', `${number(region.manualRequests)} 次主动扩展 · 平均 ${number(region.averageLatencyMs)} ms`);
    text('observability-context-rate', percent(context.readyRate));
    text('observability-context-detail', `${number(context.ready)}/${number(context.builds)} 次 AI 上下文包含成立事实`);
    text('observability-route-rate', percent(route.usableRate));
    text('observability-route-detail', `${number(route.ready + route.partial)}/${number(route.requests)} 次路线情报形成可用覆盖`);
    text('observability-provider-rate', `${number(providers.recentlyReady)}/${number(providers.total)}`);
    text('observability-provider-detail', `${number(providers.configured)} 已配置 · 缓存命中 ${percent(providers.cacheHitRate)}`);
    text('observability-context-sources', `来源支撑 ${percent(context.sourceBackedRate)} · 已核验证据 ${percent(context.verifiedEvidenceRate)} · 平均 ${number(context.averageFactCount)} 条事实`);
    text('observability-privacy', value.privacy?.preciseCoordinatesStored === false && value.privacy?.promptsStored === false
      ? '只保存固定枚举聚合；不保存精确坐标、用户问题或原始事实文本。进程重启后计数清零。'
      : '隐私边界状态异常，请检查服务端实现。');
    renderSections(region.sections);
    renderRoute(route);
    renderComponents(context.components);
    renderProviders(providers);
  }

  async function load() {
    if (state.loading) return;
    state.loading = true;
    try {
      render(await api('observability'));
      state.initialized = true;
      text('observability-status', '');
    } catch {
      state.initialized = false;
      text('observability-status', '运行指标读取失败');
    } finally {
      state.loading = false;
    }
  }

  function visible() {
    const panel = document.querySelector('.page[data-panel="observability"]');
    return panel != null && !panel.hidden;
  }

  document.addEventListener('DOMContentLoaded', () => {
    const refresh = $('#refresh-observability');
    refresh?.addEventListener('click', () => void load());
    const observer = new MutationObserver(() => {
      if (visible() && !state.loading) void load();
    });
    observer.observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
  });
})();
