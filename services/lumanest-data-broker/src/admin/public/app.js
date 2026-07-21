const state={csrf:null,config:null,llmProfiles:[],llmRouting:null,llmProviders:[],selectedLLMProfileId:null,simulationEnabled:false,simulationPresets:[],sevenTimerHealth:null};
const $=(selector)=>document.querySelector(selector);
const $$=(selector)=>[...document.querySelectorAll(selector)];
const status=(message)=>{$('#global-status').textContent=message;};

async function api(path,{method='GET',body}={}){
  const headers={};
  if(body!==undefined)headers['Content-Type']='application/json';
  if(method!=='GET'&&state.csrf)headers['X-CSRF-Token']=state.csrf;
  const response=await fetch(`/admin-api/${path}`,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
  const value=await response.json().catch(()=>({error:'invalid_response'}));
  if(response.status===401&&path!=='login'&&value.error==='unauthenticated')showLogin();
  if(!response.ok)throw new Error(value.error||'request_failed');
  return value;
}

function showLogin(){state.csrf=null;state.config=null;state.simulationEnabled=false;$('#developer-tools-label').hidden=true;$('#simulation-nav').hidden=true;$('#app-view').hidden=true;$('#login-view').hidden=false;}
function showApp(){ $('#login-view').hidden=true;$('#app-view').hidden=false; }
function maskText(value){return value?.configured?`已配置 ···· ${value.lastFour||''}`.trim():'尚未配置';}
function setMask(name,value){const node=document.querySelector(`[data-mask="${name}"]`);if(node)node.textContent=maskText(value);}
function statusTone(status){return status==='ready'?'ready':status==='disabled'?'disabled':'attention';}
function appendServiceRow({name,description,status,label,target,id}){const row=document.createElement('article');row.className='service-status-row';if(id)row.id=id;const identity=document.createElement('div');identity.className='service-identity';const mark=document.createElement('span');mark.className=`service-mark ${statusTone(status)}`;mark.textContent=name.slice(0,1);const copy=document.createElement('div');const title=document.createElement('strong');title.textContent=name;const detail=document.createElement('small');detail.textContent=description;copy.append(title,detail);identity.append(mark,copy);const stateNode=document.createElement('span');stateNode.className=`service-state ${statusTone(status)}`;stateNode.textContent=label;const button=document.createElement('button');button.type='button';button.className='row-action';button.dataset.target=target;button.textContent='管理';row.append(identity,stateNode,button);$('#service-status-list').append(row);}
function appendSummary(label,value,tone=''){const row=document.createElement('div');const term=document.createElement('dt');term.textContent=label;const detail=document.createElement('dd');detail.textContent=value;if(tone)detail.className=tone;row.append(term,detail);$('#runtime-summary').append(row);}
function appendCapability({name,detail,enabled}){const item=document.createElement('article');item.className=`capability-item ${enabled?'enabled':'disabled'}`;const top=document.createElement('div');const dot=document.createElement('i');const label=document.createElement('span');label.textContent=enabled?'已启用':'未启用';top.append(dot,label);const title=document.createElement('strong');title.textContent=name;const description=document.createElement('small');description.textContent=detail;item.append(top,title,description);$('#capability-grid').append(item);}
function renderOutboundNetwork(network){const form=$('#outbound-network-form');if(!form)return;const statusNode=$('#outbound-network-status');const detailNode=$('#outbound-network-detail');const message=$('#outbound-network-message');const mode=network?.effectiveMode;const ready=network?.status==='ready';if(mode)form.elements.mode.value=mode;const modeLabel=mode==='mihomo'?'经 mihomo':mode==='direct'?'直连':'未确认';statusNode.textContent=ready?`${modeLabel} · 已生效`:network?.status==='applying'?'正在切换网络方式':'未确认实际网络方式';const serviceCount=(network?.services??[]).filter((service)=>service.mode===mode&&service.proxyConfigured===(mode==='mihomo')).length;if(ready){detailNode.textContent=`${serviceCount}/4 个应用容器使用同一出口。切换时仅重建应用容器。`;message.textContent='';}else if(network?.status==='applying'){detailNode.textContent='容器正在按新环境变量逐个重建，通常需要半分钟。';message.textContent='正在应用，完成后会自动刷新状态。';setTimeout(()=>loadConfig().catch(()=>{}),8000);}else{detailNode.textContent=network?.error==='controller_not_configured'?'网络控制入口尚未部署或未配置。':'无法确认所有应用容器的网络环境。';}}
function renderBrokerHealth(health){const runtime=health?.runtime;$('#broker-status').textContent=health?.status==='healthy'?'健康':'需要关注';$('#broker-detail').textContent=runtime?.memory?`运行 ${runtime.uptimeSeconds} 秒 · RSS ${runtime.memory.rssMiB} MiB · 堆 ${Math.round(runtime.memory.heapUsageRatio*100)}% · 事件循环 ${Math.round(runtime.eventLoop.utilization*100)}%`:'后端资源状态未读取';$('#last-updated').textContent=`同步于 ${new Date(health.checkedAt).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false})}`;renderSevenTimerHealth(health?.services?.sevenTimer);}
function renderSevenTimerHealth(health){
  state.sevenTimerHealth=health;
  const labels={healthy:'健康',degraded:'降级',unavailable:'不可用',disabled:'已关闭',unknown:'未检测'};
  const overall=$('#seven-timer-overall');
  if(overall)overall.textContent=health?.enabled?`整体状态：${labels[health.status]??'未检测'} · ${new Date(health.checkedAt).toLocaleTimeString('zh-CN',{hour12:false})}`:'整体状态：已关闭';
  const overviewRow=$('#seven-timer-overview-row');
  if(overviewRow){const tone=health?.enabled?(health.status==='healthy'?'ready':'attention'):'disabled';overviewRow.querySelector('.service-mark').className=`service-mark ${tone}`;overviewRow.querySelector('.service-state').className=`service-state ${tone}`;overviewRow.querySelector('.service-state').textContent=labels[health?.status]??'未检测';overviewRow.querySelector('.service-identity small').textContent=health?.enabled?`ASTRO / METEO / TWO · ${labels[health.status]??'未检测'}`:'Provider 已关闭';}
  const metrics=health?.metrics;const persistence=health?.persistence;const resource=$('#seven-timer-resource-summary');
  if(resource){const requests=(metrics?.products??[]).reduce((sum,item)=>sum+item.requestTotal,0);const cacheHits=(metrics?.products??[]).reduce((sum,item)=>sum+item.cacheHit,0);const cacheBackend=health?.cacheBackend;resource.textContent=`进行中 ${metrics?.inFlight??0} · 请求 ${requests} · 缓存命中 ${cacheHits} · 缓存 ${cacheBackend?.mode??'未知'}${cacheBackend?.available?' 可用':' 不可用'} · 诊断 ${persistence?.mode??'未知'}${persistence?.durable?' 持久':' 临时'}`;}
  const root=$('#seven-timer-products');if(!root)return;root.replaceChildren();
  const metricByProduct=new Map((metrics?.products??[]).map((item)=>[item.product,item]));
  for(const item of (health?.products??[])){const metric=metricByProduct.get(item.product)??{};const row=document.createElement('div');row.className='seven-timer-product';const title=document.createElement('strong');title.textContent=item.product.toUpperCase();const detail=document.createElement('small');const statusLabel=labels[item.status]??'未检测';const cache=item.cacheStatus==='unknown'?'缓存未知':`缓存：${item.cacheStatus}`;detail.textContent=`${statusLabel} · ${cache} · ${item.pointCount||0} 点 · 源龄 ${item.sourceAgeMinutes??'—'} 分钟 · 熔断 ${item.circuitState} · P95 ${metric.p95LatencyMs??0} ms`;const trace=document.createElement('code');trace.textContent=item.lastErrorCode?`${item.lastErrorCode} · ${item.lastAttempts} 次 · ${item.lastLatencyMs??'—'} ms · ${item.traceId||'无 Trace ID'}`:(item.lastSuccessAt?`成功 ${item.lastSuccessLatencyMs??'—'} ms · ${item.traceId||'无 Trace ID'}`:'暂无尝试');row.append(title,detail,trace);root.append(row);}
}

function renderConfig(config){
  state.config=config;
  const integrations=[
    ['和风天气',{configured:Boolean(config.services.qweatherPrivateKey?.configured&&config.services.keyId?.configured&&config.services.projectId?.configured),lastFour:config.services.keyId?.lastFour}],
    ['高德地图',config.services.amapWebKey],
    ['App 访问',config.services.serviceToken],
  ];
  const configuredCount=integrations.filter(([,value])=>value?.configured).length;
  const enabledCapabilities=config.settings?.sunsetbotProviderEnabled?['skyOpportunityCardEnabled','skyOpportunityNotificationEnabled','skyOpportunityMapEnabled','skyOpportunityTomorrowSunsetEnabled'].filter((name)=>config.settings?.[name]).length:0;
  const enabledSourceCount=(config.discoverySearch?.sourcePolicies??[]).filter((policy)=>policy.enabled).length;
  $('#revision').textContent=String(config.revision??'—');
  $('#configured-count').textContent=`${configuredCount} / ${integrations.length}`;
  $('#configured-rate').textContent=`${Math.round(configuredCount/integrations.length*100)}%`;
  $('#configured-detail').textContent=configuredCount===integrations.length?'全部核心服务已完成配置':`还有 ${integrations.length-configuredCount} 项服务待配置`;
  $('#llm-profile-count').textContent=String(config.llm?.profileCount??0);
  $('#llm-route-state').textContent=config.llm?.primaryProfileId?'主路由已选':'无主路由';
  $('#ai-state').textContent=config.settings?.aiEnabled?(config.llm?.primaryProfileId?'AI 文案链路可用':'AI 已开启，但缺少主模型'):'当前使用本地确定性文案';
  $('#capability-count').textContent=String(enabledCapabilities);
  $('#sky-opportunity-state').textContent=config.settings?.sunsetbotProviderEnabled?'SunsetBot Provider 已接入':'朝晚霞 Provider 未启用';
  const qweatherReady=integrations[0][1].configured;
  const amapReady=Boolean(config.services.amapWebKey?.configured);
  const appReady=Boolean(config.services.serviceToken?.configured);
  const searchReady=Boolean(config.discoverySearch?.enabled&&config.discoverySearch?.apiKey?.configured&&enabledSourceCount>0);
  const llmReady=Boolean(config.settings?.aiEnabled&&config.llm?.primaryProfileId);
  $('#service-status-list').replaceChildren();
  appendServiceRow({name:'和风天气',description:'私钥、凭据 ID 与项目 ID',status:qweatherReady?'ready':'attention',label:qweatherReady?'链路就绪':'配置不完整',target:'services'});
  appendServiceRow({name:'高德地图',description:'场景证据、路线与地点检索',status:amapReady?'ready':'attention',label:amapReady?'链路就绪':'缺少 Web Key',target:'services'});
  appendServiceRow({name:'App 访问',description:'客户端访问 Broker 的服务令牌',status:appReady?'ready':'attention',label:appReady?'访问受保护':'缺少令牌',target:'services'});
  appendServiceRow({name:'审核来源搜索',description:`${enabledSourceCount} 条已启用来源政策`,status:searchReady?'ready':config.discoverySearch?.enabled?'attention':'disabled',label:searchReady?'检索可用':config.discoverySearch?.enabled?'配置不完整':'已关闭',target:'services'});
  appendServiceRow({name:'模型路由',description:`${config.llm?.profileCount??0} 个模型档案`,status:llmReady?'ready':config.settings?.aiEnabled?'attention':'disabled',label:llmReady?'主路由可用':config.settings?.aiEnabled?'等待主模型':'本地模式',target:'llm'});
  appendServiceRow({name:'7Timer',description:'专业气象补充源 · 健康状态待读取',status:'attention',label:'未检测',target:'runtime',id:'seven-timer-overview-row'});
  $('#runtime-summary').replaceChildren();
  appendSummary('AI 文案',config.settings?.aiEnabled?'启用':'关闭',config.settings?.aiEnabled?'positive':'muted');
  appendSummary('助手联网搜索',config.settings?.assistantWebSearchEnabled?'启用':'关闭',config.settings?.assistantWebSearchEnabled?'warning-text':'muted');
  appendSummary('AI 超时',`${config.settings?.aiTimeoutMs??'—'} ms`);
  appendSummary('上游超时',`${config.settings?.upstreamTimeoutMs??'—'} ms`);
  appendSummary('野生动物范围',`${config.settings?.wildlifeRadiusKm??'—'} km`);
  appendSummary('调试日志',config.settings?.debugLogging?'启用':'关闭',config.settings?.debugLogging?'warning-text':'muted');
  $('#capability-grid').replaceChildren();
  appendCapability({name:'AI 创作表达',detail:config.llm?.primaryProfileId?'已绑定主模型档案':'本地文案仍可独立运行',enabled:Boolean(config.settings?.aiEnabled&&config.llm?.primaryProfileId)});
  appendCapability({name:'助手联网搜索',detail:'独立于探索搜索，回答展示可点击来源',enabled:Boolean(config.settings?.assistantWebSearchEnabled&&searchReady)});
  appendCapability({name:'审核来源探索',detail:`${enabledSourceCount} 条已启用来源政策`,enabled:searchReady});
  appendCapability({name:'首页机会对象',detail:'朝霞与晚霞机会按阈值出现',enabled:Boolean(config.settings?.sunsetbotProviderEnabled&&config.settings?.skyOpportunityCardEnabled)});
  appendCapability({name:'机会通知',detail:'只在达到独立通知阈值时触发',enabled:Boolean(config.settings?.sunsetbotProviderEnabled&&config.settings?.skyOpportunityNotificationEnabled)});
  const issueCount=[qweatherReady,amapReady,appReady,searchReady||!config.discoverySearch?.enabled,llmReady||!config.settings?.aiEnabled].filter((ready)=>!ready).length;
  $('#action-summary').textContent=issueCount===0?'当前没有阻塞性配置问题。':`检测到 ${issueCount} 项启用中的能力尚未完成配置。`;
  for(const [name,value] of Object.entries(config.services))setMask(name,value);
  for(const [name,value] of Object.entries(config.settings)){
    const control=$('#runtime-form').elements[name];if(!control)continue;
    if(control.type==='checkbox')control.checked=value;else control.value=String(value);
  }
  const discovery=config.discoverySearch;
  if(discovery){const form=$('#discovery-search-form');form.elements.baseUrl.value=discovery.baseUrl;form.elements.apiKey.value='';form.elements.timeoutMs.value=String(discovery.timeoutMs);form.elements.enabled.checked=discovery.enabled;form.elements.sourcePolicies.value=JSON.stringify(discovery.sourcePolicies||[],null,2);$('#discovery-search-key-mask').textContent=maskText(discovery.apiKey);}
  renderOutboundNetwork(config.outboundNetwork);
}

async function loadSevenTimerHealth(){renderSevenTimerHealth(await api('services/7timer'));}
async function loadBrokerHealth(){renderBrokerHealth(await api('health'));}
async function loadConfig(){renderConfig(await api('config'));await loadBrokerHealth();}
async function loadCapabilities(){
  const capabilities=await api('capabilities');
  state.simulationEnabled=Boolean(capabilities.developerTools?.simulationEnabled);
  $('#developer-tools-label').hidden=!state.simulationEnabled;
  $('#simulation-nav').hidden=!state.simulationEnabled;
  if(!state.simulationEnabled&&document.querySelector('.page[data-panel="simulation"].active'))switchPage('overview');
}
function llmStatus(profile){return profile.enabled?'已启用':'已停用';}
function selectLLMProfile(id){state.selectedLLMProfileId=id;renderLLM();}
function renderProviderOptions(){const list=$('#provider-options');list.replaceChildren();for(const provider of state.llmProviders){const button=document.createElement('button');button.type='button';button.className='provider-option';const title=document.createElement('strong');title.textContent=provider.name;const detail=document.createElement('small');detail.textContent=provider.protocol.replaceAll('_',' · ');button.append(title,detail);button.addEventListener('click',()=>startLLMProfile(provider));list.append(button);}}
function llmProfileDraft(){const form=$('#llm-profile-form');const draft={id:form.elements.id.value,name:form.elements.name.value.trim(),providerId:form.elements.providerId.value,protocol:form.elements.protocol.value,baseUrl:form.elements.baseUrl.value.trim(),model:form.elements.model.value.trim(),enabled:form.elements.enabled.checked,allowFallback:form.elements.allowFallback.checked,timeoutMs:Number(form.elements.timeoutMs.value)};const key=form.elements.apiKey.value.trim();if(key)draft.apiKey=key;return draft;}
function renderModelOptions(models){const select=$('#llm-model-select');select.replaceChildren();const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent=models.length?'从已读取模型中选择':'刷新后在此选择模型';select.append(placeholder);for(const model of models){const option=document.createElement('option');option.value=model;option.textContent=model;select.append(option);}select.disabled=models.length===0;$('#llm-model-hint').textContent=models.length?`已读取 ${models.length} 个可用模型，也可继续手动输入。`:'没有读取到模型，可手动输入模型 ID。';}
function startLLMProfile(provider){const form=$('#llm-profile-form');form.reset();form.elements.id.value=`${provider.id}-${Date.now().toString(36)}`;form.elements.providerId.value=provider.id;form.elements.protocol.value=provider.protocol;form.elements.name.value=provider.name;form.elements.baseUrl.value=provider.baseUrl||'';form.elements.model.value=provider.suggestedModels[0]||'';form.elements.enabled.checked=true;form.elements.allowFallback.checked=false;form.elements.timeoutMs.value='8000';$('#llm-provider-protocol').textContent=provider.protocol.replaceAll('_',' · ');$('#llm-profile-title').textContent=`新建 · ${provider.name}`;$('#llm-profile-status').textContent='未保存';$('#llm-key-mask').textContent=provider.requiresApiKey?'需要 API Key':'可不填 API Key';state.selectedLLMProfileId=null;$('#llm-empty-state').hidden=true;form.hidden=false;$('#delete-llm-profile').hidden=true;$('#provider-dialog').close();}
function renderLLM(){const list=$('#llm-profile-list');list.replaceChildren();const profiles=state.llmProfiles;for(const profile of profiles){const button=document.createElement('button');button.type='button';button.className=`profile-row${profile.id===state.selectedLLMProfileId?' active':''}`;const name=document.createElement('strong');name.textContent=profile.name;const detail=document.createElement('small');detail.textContent=`${profile.providerId} · ${profile.model||'未选择模型'} · ${llmStatus(profile)}`;button.append(name,detail);button.addEventListener('click',()=>selectLLMProfile(profile.id));list.append(button);}const selected=profiles.find((profile)=>profile.id===state.selectedLLMProfileId);const form=$('#llm-profile-form');$('#llm-empty-state').hidden=selected!=null||profiles.length>0;if(selected==null){form.hidden=true;if(profiles.length>0){state.selectedLLMProfileId=profiles[0].id;renderLLM();}return;}form.hidden=false;form.elements.id.value=selected.id;form.elements.providerId.value=selected.providerId;form.elements.protocol.value=selected.protocol;form.elements.name.value=selected.name;form.elements.baseUrl.value=selected.baseUrl;form.elements.model.value=selected.model;form.elements.apiKey.value='';form.elements.timeoutMs.value=String(selected.timeoutMs);form.elements.enabled.checked=selected.enabled;form.elements.allowFallback.checked=selected.allowFallback;$('#llm-provider-protocol').textContent=selected.protocol.replaceAll('_',' · ');$('#llm-profile-title').textContent=selected.name;$('#llm-profile-status').textContent=selected.model?llmStatus(selected):'等待选择模型';$('#llm-key-mask').textContent=maskText(selected.apiKey);$('#delete-llm-profile').hidden=false;renderRouting();}
function renderRouting(){const routing=state.llmRouting||{primaryProfileId:null,fallbackEnabled:false,fallbackProfileIds:[],maximumAttempts:3};const primary=$('#llm-primary-select');primary.replaceChildren();const none=document.createElement('option');none.value='';none.textContent='未选择';primary.append(none);for(const profile of state.llmProfiles.filter((profile)=>profile.enabled&&profile.model)){const option=document.createElement('option');option.value=profile.id;option.textContent=`${profile.name} · ${profile.model}`;option.selected=profile.id===routing.primaryProfileId;primary.append(option);}const form=$('#llm-routing-form');form.elements.fallbackEnabled.checked=routing.fallbackEnabled;form.elements.maximumAttempts.value=String(routing.maximumAttempts);const fallbackList=$('#llm-fallback-list');fallbackList.replaceChildren();for(const profile of state.llmProfiles.filter((profile)=>profile.enabled&&profile.model&&profile.allowFallback&&profile.id!==routing.primaryProfileId)){const label=document.createElement('label');label.className='fallback-choice';const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.name='fallbackProfileId';checkbox.value=profile.id;checkbox.checked=routing.fallbackProfileIds.includes(profile.id);const text=document.createElement('span');text.textContent=`备用 · ${profile.name}`;label.append(checkbox,text);fallbackList.append(label);}}
async function loadLLM(){const [providerData,profileData]=await Promise.all([api('llm/providers'),api('llm/profiles')]);state.llmProviders=providerData.providers;state.llmProfiles=profileData.profiles;state.llmRouting=profileData.routing;renderProviderOptions();renderLLM();}
function switchPage(name){
  $$('.nav-item[data-page]').forEach((button)=>button.classList.toggle('active',button.dataset.page===name));
  $$('.page').forEach((panel)=>{panel.hidden=panel.dataset.panel!==name;panel.classList.toggle('active',panel.dataset.panel===name);});
  if(name==='simulation'&&!state.simulationEnabled)return;
  const pages={overview:['概览','查看栖光数据服务的状态与配置。'],services:['密钥与服务','管理上游服务凭据、App 访问与审核来源搜索。'],llm:['模型服务','配置创作表达模型、连接状态与备用路由。'],runtime:['运行设置','调整服务端实时策略、缓存和机会功能开关。'],simulation:['场景实验室','向已配对的 Debug App 注入隔离、可复现的 V5 环境场景。'],calibration:['反馈校准','查看达到隐私阈值的匿名拍摄反馈聚合。'],security:['安全与维护','管理控制台凭据、运行缓存与服务维护操作。']};$('#page-title').textContent=pages[name][0];$('#page-subtitle').textContent=pages[name][1];status('');
  if(name==='security')loadAudit();
  if(name==='llm')loadLLM().catch(()=>status('模型服务配置读取失败'));
  if(name==='simulation')loadSimulation().catch(()=>status('模拟会话读取失败'));
  if(name==='calibration')loadCalibration().catch(()=>status('反馈校准读数读取失败'));
  if(name==='runtime')loadSevenTimerHealth().catch(()=>status('7Timer 健康状态读取失败'));
}

const calibrationLabels={
  band:{good:'较好',fair:'一般',limited:'受限'},
  factor:{cloud:'云层',wind:'风况',precipitation:'降水',visibility:'能见度',dataCoverage:'数据完整性'},
  effect:{supporting:'支持',neutral:'中性',limiting:'限制'},
};

function renderCalibration(report){
  const summary=$('#calibration-summary');summary.replaceChildren();
  const facts=[
    ['统计起点',new Date(report.since).toLocaleString('zh-CN',{hour12:false})],
    ['生成时间',new Date(report.generatedAt).toLocaleString('zh-CN',{hour12:false})],
    ['隐私阈值',`每组至少 ${report.minimumSamples} 条`],
  ];
  for(const [label,value] of facts){const item=document.createElement('div');const small=document.createElement('small');small.textContent=label;const strong=document.createElement('strong');strong.textContent=value;item.append(small,strong);summary.append(item);}
  const body=$('#calibration-rows');body.replaceChildren();
  $('#calibration-empty').hidden=report.rows.length!==0;
  for(const row of report.rows){
    const tr=document.createElement('tr');
    const values=[row.ruleVersion,calibrationLabels.band[row.conditionBand],calibrationLabels.factor[row.factorId],calibrationLabels.effect[row.factorEffect],String(row.evaluatedCount),String(row.capturedCount),String(row.conditionsDidNotAppearCount),`${Math.round(row.capturedRate*100)}%`];
    for(const value of values){const cell=document.createElement('td');cell.textContent=value;tr.append(cell);}
    body.append(tr);
  }
}

async function loadCalibration(){
  const form=$('#calibration-form');
  const days=Number(form.elements.days.value);const minimumSamples=Number(form.elements.minimumSamples.value);
  renderCalibration(await api(`context/shooting-calibration?days=${days}&minimumSamples=${minimumSamples}`));
}

const simulationLabels={conditionBand:{good:'条件较好',fair:'条件一般',limited:'条件受限'},confidenceBand:{high:'高置信',medium:'中置信',limited:'有限置信'}};
function remainingText(expiresAt){const seconds=Math.max(0,Math.floor((new Date(expiresAt).getTime()-Date.now())/1000));const minutes=Math.floor(seconds/60);return `${minutes} 分 ${seconds%60} 秒后过期`;}
function renderSimulationPreset(){
  const preset=state.simulationPresets.find((item)=>item.value===$('#simulation-preset').value)??state.simulationPresets[0];
  if(!preset)return;
  $('#simulation-preset-title').textContent=preset.label;
  $('#simulation-preset-description').textContent=preset.description;
  const tags=$('#simulation-preset-tags');tags.replaceChildren();
  for(const value of [preset.kind,simulationLabels.conditionBand[preset.conditionBand],simulationLabels.confidenceBand[preset.confidenceBand],preset.hasSafetyAlert?'包含安全提醒':'创作场景']){const tag=document.createElement('span');tag.textContent=value;tags.append(tag);}
}
function renderSimulationPresets(presets){
  state.simulationPresets=presets;
  const select=$('#simulation-preset');const previous=select.value;select.replaceChildren();
  for(const preset of presets){const option=document.createElement('option');option.value=preset.value;option.textContent=preset.label;option.selected=preset.value===previous;select.append(option);}
  renderSimulationPreset();
}
function simulationPresetLabel(value){return state.simulationPresets.find((item)=>item.value===value)?.label??value;}
async function loadSimulation(){
  const {presets,sessions}=await api('simulation');
  renderSimulationPresets(presets);
  $('#simulation-session-count').textContent=String(sessions.length);
  const activeCount=sessions.filter((session)=>session.activePreset).length;
  $('#simulation-active-count').textContent=String(activeCount);
  $('#clear-all-simulations').disabled=activeCount===0;
  const list=$('#simulation-session-list');list.replaceChildren();
  if(!sessions.length){const item=document.createElement('li');item.className='simulation-empty';item.textContent='尚无 Debug App 会话。打开 Debug App 并刷新一次环境数据后，会在这里出现临时配对会话。';list.append(item);return;}
  for(const session of sessions){
    const item=document.createElement('li');item.className='simulation-session-card';
    const identity=document.createElement('div');identity.className='simulation-session-identity';const title=document.createElement('strong');title.textContent=`Debug App · ${session.sessionCode}`;const meta=document.createElement('small');meta.textContent=`契约 V${session.contractVersion??'未知'} · 最后在线 ${new Date(session.lastSeenAt).toLocaleTimeString('zh-CN',{hour12:false})} · ${remainingText(session.expiresAt)}`;identity.append(title,meta);
    const delivery=document.createElement('div');delivery.className='simulation-delivery';const deliveryTitle=document.createElement('strong');deliveryTitle.textContent=session.activePreset?simulationPresetLabel(session.activePreset):'未启用模拟';const deliveryMeta=document.createElement('small');deliveryMeta.textContent=`已下发 ${session.deliveryCount} 次 · 已隔离 ${session.suppressedFeedbackCount} 条反馈`;delivery.append(deliveryTitle,deliveryMeta);
    const actions=document.createElement('div');actions.className='simulation-session-actions';const send=document.createElement('button');send.type='button';send.className='secondary';send.textContent=session.activePreset?'切换场景':'发送场景';send.addEventListener('click',async()=>{send.disabled=true;try{await api(`simulation/sessions/${session.controlId}`,{method:'POST',body:{preset:$('#simulation-preset').value}});status('场景已激活；Debug App 下次刷新环境数据时生效');await loadSimulation();}catch{status('场景发送失败，会话可能已经过期');}finally{send.disabled=false;}});const clear=document.createElement('button');clear.type='button';clear.className='secondary';clear.textContent='停止';clear.disabled=!session.activePreset;clear.addEventListener('click',async()=>{clear.disabled=true;try{await api(`simulation/sessions/${session.controlId}`,{method:'DELETE',body:{}});status('该会话的模拟已停止');await loadSimulation();}catch{status('停止失败，会话可能已经过期');}});actions.append(send,clear);
    item.append(identity,delivery,actions);list.append(item);
  }
}

async function loadAudit(){
  try{const {entries}=await api('audit');const list=$('#audit-list');list.replaceChildren();
    for(const entry of entries){const item=document.createElement('li');const result=[entry.result,entry.details?.product,entry.details?.traceId].filter(Boolean).join(' · ');for(const value of [new Date(entry.timestamp).toLocaleString(),entry.operation,result]){const span=document.createElement('span');span.textContent=value;item.append(span);}list.append(item);}
  }catch{status('审计记录读取失败');}
}

$('#login-form').addEventListener('submit',async(event)=>{
  event.preventDefault();
  const form=event.currentTarget;
  const button=event.submitter;
  button.disabled=true;
  $('#login-status').textContent='正在验证…';
  let result;
  try{
    result=await api('login',{method:'POST',body:{password:form.elements.password.value}});
  }catch(error){
    const messages={invalid_credentials:'密码不正确',rate_limited:'尝试次数过多，请 15 分钟后再试',lan_only:'当前网络不能访问管理台',invalid_request:'登录请求无效'};
    $('#login-status').textContent=messages[error.message]??'登录服务暂不可用，请检查 Broker 状态';
    button.disabled=false;
    return;
  }
  state.csrf=result.csrfToken;
  form.reset();
  $('#login-status').textContent='';
  showApp();
  try{await Promise.all([loadConfig(),loadCapabilities()]);}catch{status('登录成功，但控制台状态加载失败，请刷新页面');}
  button.disabled=false;
});

$$('.nav-item[data-page]').forEach((button)=>button.addEventListener('click',()=>switchPage(button.dataset.page)));
document.addEventListener('click',(event)=>{const button=event.target.closest('button[data-target]');if(button)switchPage(button.dataset.target);});
$('#refresh-overview').addEventListener('click',async()=>{const button=$('#refresh-overview');button.disabled=true;try{status('正在刷新配置快照…');await loadConfig();status('状态已刷新');}catch{status('刷新失败，请确认 Broker 服务状态');}finally{button.disabled=false;}});
$('#calibration-form').addEventListener('submit',async(event)=>{event.preventDefault();try{status('正在读取匿名聚合…');await loadCalibration();status('反馈校准读数已更新');}catch{status('读取失败，请确认 Context Service 与数据库迁移已就绪');}});
$('#simulation-preset').addEventListener('change',renderSimulationPreset);
$('#refresh-simulations').addEventListener('click',async()=>{const button=$('#refresh-simulations');button.disabled=true;try{await loadSimulation();status('测试会话已刷新');}catch{status('测试会话读取失败');}finally{button.disabled=false;}});
$('#clear-all-simulations').addEventListener('click',async()=>{if(!window.confirm('确认停止全部活动模拟？Debug App 下一次刷新将恢复真实环境链路。'))return;try{const result=await api('simulation/sessions',{method:'DELETE',body:{}});status(`已停止 ${result.cleared} 个活动模拟`);await loadSimulation();}catch{status('停止全部模拟失败');}});
$('#logout').addEventListener('click',async()=>{try{await api('logout',{method:'POST'});}finally{showLogin();}});

$('#services-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const patch={};for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken']){const value=form.elements[name].value.trim();if(value)patch[name]=value;}try{status('正在加密并应用…');renderConfig(await api('config',{method:'PUT',body:patch}));for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken'])form.elements[name].value='';status('密钥与服务配置已生效');}catch{status('保存失败，请检查输入范围与格式');}});
$('#discovery-search-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;let sourcePolicies;try{sourcePolicies=JSON.parse(form.elements.sourcePolicies.value);}catch{status('来源政策必须是有效 JSON 数组');return;}const profile={baseUrl:form.elements.baseUrl.value.trim(),enabled:form.elements.enabled.checked,timeoutMs:Number(form.elements.timeoutMs.value),sourcePolicies};const apiKey=form.elements.apiKey.value.trim();if(apiKey)profile.apiKey=apiKey;try{const result=await api('discovery/search-profile',{method:'PUT',body:profile});form.elements.apiKey.value='';$('#discovery-search-key-mask').textContent=maskText(result.profile.apiKey);status('探索搜索配置已加密保存');await loadConfig();}catch{status('搜索配置保存失败，请检查来源许可、域名和字段');}});

$('#add-llm-profile').addEventListener('click',()=>$('#provider-dialog').showModal());
$('#add-llm-profile-empty').addEventListener('click',()=>$('#provider-dialog').showModal());
$('#llm-profile-form').addEventListener('submit',async(event)=>{event.preventDefault();const payload=llmProfileDraft();try{const editing=state.llmProfiles.some((profile)=>profile.id===payload.id);await api(editing?`llm/profiles/${payload.id}`:'llm/profiles',{method:editing?'PUT':'POST',body:payload});status('模型档案已加密保存');state.selectedLLMProfileId=payload.id;await loadLLM();}catch{status('保存失败，请检查档案字段和服务端点');}});
$('#refresh-llm-models').addEventListener('click',async()=>{const button=$('#refresh-llm-models');button.disabled=true;try{status('正在读取模型列表…');const result=await api('llm/models',{method:'POST',body:llmProfileDraft()});renderModelOptions(result.models);status(result.error?`无法读取模型列表：${result.error}`:'模型列表已更新');}catch{status('无法读取模型列表，请检查端点和 Key');}finally{button.disabled=false;}});
$('#llm-model-select').addEventListener('change',(event)=>{if(event.currentTarget.value){$('#llm-profile-form').elements.model.value=event.currentTarget.value;}});
$('#test-llm-profile').addEventListener('click',async()=>{const id=$('#llm-profile-form').elements.id.value;try{status('正在测试模型档案…');const result=await api(`llm/profiles/${id}/test`,{method:'POST',body:{}});status(result.status==='ok'?'模型档案连接正常':`连接结果：${result.status}`);}catch{status('模型档案测试失败');}});
$('#delete-llm-profile').addEventListener('click',async()=>{const id=$('#llm-profile-form').elements.id.value;if(!window.confirm('确认删除此模型档案？如它正被主模型或备用链引用，系统会拒绝删除。'))return;try{await api(`llm/profiles/${id}`,{method:'DELETE',body:{confirmId:id}});state.selectedLLMProfileId=null;status('模型档案已删除');await loadLLM();}catch{status('删除失败：请先解除主模型或备用链引用');}});
$('#llm-routing-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const routing={primaryProfileId:form.elements.primaryProfileId.value||null,fallbackEnabled:form.elements.fallbackEnabled.checked,fallbackProfileIds:[...form.querySelectorAll('input[name="fallbackProfileId"]:checked')].map((node)=>node.value),maximumAttempts:Number(form.elements.maximumAttempts.value)};try{await api('llm/routing',{method:'PUT',body:routing});status('模型路由策略已生效');await loadLLM();}catch{status('路由策略无效：主模型和备用档案必须已启用');}});

$('#test-services').addEventListener('click',async()=>{try{status('正在测试上游连接…');const result=await api('test-connection',{method:'POST',body:{}});status(result.status==='ok'?'连接正常':`连接结果：${result.status}`);}catch{status('连接测试失败');}});

$('#runtime-form').addEventListener('submit',async(event)=>{event.preventDefault();const settings={};for(const control of event.currentTarget.elements){if(!control.name)continue;settings[control.name]=control.type==='checkbox'?control.checked:Number(control.value);}try{renderConfig(await api('config',{method:'PUT',body:{settings}}));status('运行设置已生效');}catch{status('设置超出允许范围');}});
$('#refresh-seven-timer').addEventListener('click',async()=>{const button=$('#refresh-seven-timer');button.disabled=true;try{await loadSevenTimerHealth();status('7Timer 健康状态已刷新');}catch{status('7Timer 健康状态读取失败');}finally{button.disabled=false;}});
$('#test-seven-timer').addEventListener('click',async()=>{const button=$('#test-seven-timer');button.disabled=true;const product=$('#seven-timer-test-product').value;try{const result=await api('services/7timer/test',{method:'POST',body:{product,latitude:Number($('#seven-timer-test-latitude').value),longitude:Number($('#seven-timer-test-longitude').value)}});status(`${product.toUpperCase()} 检测成功：${result.pointCount} 点 · Trace ID ${result.traceId}`);await loadSevenTimerHealth();}catch(error){status(`${product.toUpperCase()} 检测失败：${error.message}；可在健康面板查看 Trace ID`);await loadSevenTimerHealth().catch(()=>{});}finally{button.disabled=false;}});

$('#outbound-network-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const mode=form.elements.mode.value;const label=mode==='mihomo'?'经 mihomo':'直连';if(!window.confirm(`确认将整个后端的外网 HTTP(S) 切换为「${label}」？四个应用容器会短暂重建，数据库和缓存不会清除。`))return;const button=event.submitter;button.disabled=true;try{await api('outbound-network',{method:'PUT',body:{mode}});$('#outbound-network-message').textContent='网络方式已提交，正在重建应用容器…';setTimeout(()=>loadConfig().catch(()=>{$('#outbound-network-message').textContent='状态刷新失败，请稍后刷新页面确认。';}),8000);}catch{ $('#outbound-network-message').textContent='切换未被接受；当前网络方式没有改变。';}finally{setTimeout(()=>{button.disabled=false;},8000);}});

$('#password-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const button=event.submitter;const passwordStatus=$('#password-status');const currentPassword=form.elements.currentPassword.value;const newPassword=form.elements.newPassword.value;const confirmPassword=form.elements.confirmPassword.value;if(newPassword!==confirmPassword){passwordStatus.textContent='两次输入的新密码不一致';return;}button.disabled=true;passwordStatus.textContent='正在更新密码…';try{await api('change-password',{method:'POST',body:{currentPassword,newPassword,confirmPassword}});form.reset();showLogin();$('#login-status').textContent='密码已更换，所有设备均需重新登录';}catch(error){const messages={invalid_current_password:'当前密码不正确',password_mismatch:'两次输入的新密码不一致',invalid_password:'新密码必须为 8 至 256 个字符',invalid_request:'改密请求无效'};passwordStatus.textContent=messages[error.message]??'密码更新失败，请检查 Broker 状态';}finally{button.disabled=false;}});
$('#clear-cache').addEventListener('click',async()=>{try{await api('clear-cache',{method:'POST',body:{}});status('缓存已清理');await loadAudit();}catch{status('缓存清理失败');}});
$('#restart').addEventListener('click',async()=>{if(!window.confirm('确认重启 Broker？App API 会短暂中断。'))return;try{await api('restart',{method:'POST',body:{}});status('重启指令已发送');}catch{status('重启指令发送失败');}});

(async()=>{try{const session=await api('session');state.csrf=session.csrfToken;showApp();await Promise.all([loadConfig(),loadCapabilities()]);}catch{showLogin();}})();
