const state={csrf:null,config:null,llmProfiles:[],llmRouting:null,llmProviders:[],selectedLLMProfileId:null};
const $=(selector)=>document.querySelector(selector);
const $$=(selector)=>[...document.querySelectorAll(selector)];
const status=(message)=>{$('#global-status').textContent=message;};

async function api(path,{method='GET',body}={}){
  const headers={};
  if(body!==undefined)headers['Content-Type']='application/json';
  if(method!=='GET'&&state.csrf)headers['X-CSRF-Token']=state.csrf;
  const response=await fetch(`/admin-api/${path}`,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
  const value=await response.json().catch(()=>({error:'invalid_response'}));
  if(response.status===401&&path!=='login')showLogin();
  if(!response.ok)throw new Error(value.error||'request_failed');
  return value;
}

function showLogin(){state.csrf=null;state.config=null;$('#app-view').hidden=true;$('#login-view').hidden=false;}
function showApp(){ $('#login-view').hidden=true;$('#app-view').hidden=false; }
function maskText(value){return value?.configured?`已配置 ···· ${value.lastFour||''}`.trim():'尚未配置';}
function setMask(name,value){const node=document.querySelector(`[data-mask="${name}"]`);if(node)node.textContent=maskText(value);}
function tile(label,value){const node=document.createElement('article');node.className='service-tile';const small=document.createElement('small');small.textContent=label;const strong=document.createElement('strong');strong.textContent=maskText(value);node.append(small,strong);return node;}

function renderConfig(config){
  state.config=config;$('#revision').textContent=`配置版本 ${config.revision??'—'}`;
  const grid=$('#service-grid');grid.replaceChildren();
  const labels={qweatherPrivateKey:'和风私钥',amapWebKey:'高德地图',serviceToken:'App 访问'};
  for(const [name,label] of Object.entries(labels))grid.append(tile(label,config.services[name]));
  for(const [name,value] of Object.entries(config.services))setMask(name,value);
  for(const [name,value] of Object.entries(config.settings)){
    const control=$('#runtime-form').elements[name];if(!control)continue;
    if(control.type==='checkbox')control.checked=value;else control.value=String(value);
  }
}

async function loadConfig(){renderConfig(await api('config'));}
function llmStatus(profile){return profile.enabled?'已启用':'已停用';}
function selectLLMProfile(id){state.selectedLLMProfileId=id;renderLLM();}
function renderProviderOptions(){const list=$('#provider-options');list.replaceChildren();for(const provider of state.llmProviders){const button=document.createElement('button');button.type='button';button.className='provider-option';const title=document.createElement('strong');title.textContent=provider.name;const detail=document.createElement('small');detail.textContent=provider.protocol.replaceAll('_',' · ');button.append(title,detail);button.addEventListener('click',()=>startLLMProfile(provider));list.append(button);}}
function llmProfileDraft(){const form=$('#llm-profile-form');const draft={id:form.elements.id.value,name:form.elements.name.value.trim(),providerId:form.elements.providerId.value,protocol:form.elements.protocol.value,baseUrl:form.elements.baseUrl.value.trim(),model:form.elements.model.value.trim(),enabled:form.elements.enabled.checked,allowFallback:form.elements.allowFallback.checked,timeoutMs:Number(form.elements.timeoutMs.value)};const key=form.elements.apiKey.value.trim();if(key)draft.apiKey=key;return draft;}
function renderModelOptions(models){const list=$('#llm-model-options');list.replaceChildren();for(const model of models){const option=document.createElement('option');option.value=model;list.append(option);}$('#llm-model-hint').textContent=models.length?`已读取 ${models.length} 个可用模型，可继续手动输入。`:'没有读取到模型，可手动输入模型 ID。';}
function startLLMProfile(provider){const form=$('#llm-profile-form');form.reset();form.elements.id.value=`${provider.id}-${Date.now().toString(36)}`;form.elements.providerId.value=provider.id;form.elements.protocol.value=provider.protocol;form.elements.name.value=provider.name;form.elements.baseUrl.value=provider.baseUrl||'';form.elements.model.value=provider.suggestedModels[0]||'';form.elements.enabled.checked=true;form.elements.allowFallback.checked=false;form.elements.timeoutMs.value='8000';$('#llm-provider-protocol').textContent=provider.protocol.replaceAll('_',' · ');$('#llm-profile-title').textContent=`新建 · ${provider.name}`;$('#llm-profile-status').textContent='未保存';$('#llm-key-mask').textContent=provider.requiresApiKey?'需要 API Key':'可不填 API Key';state.selectedLLMProfileId=null;$('#llm-empty-state').hidden=true;form.hidden=false;$('#delete-llm-profile').hidden=true;$('#provider-dialog').close();}
function renderLLM(){const list=$('#llm-profile-list');list.replaceChildren();const profiles=state.llmProfiles;for(const profile of profiles){const button=document.createElement('button');button.type='button';button.className=`profile-row${profile.id===state.selectedLLMProfileId?' active':''}`;const name=document.createElement('strong');name.textContent=profile.name;const detail=document.createElement('small');detail.textContent=`${profile.providerId} · ${profile.model} · ${llmStatus(profile)}`;button.append(name,detail);button.addEventListener('click',()=>selectLLMProfile(profile.id));list.append(button);}const selected=profiles.find((profile)=>profile.id===state.selectedLLMProfileId);const form=$('#llm-profile-form');$('#llm-empty-state').hidden=selected!=null||profiles.length>0;if(selected==null){form.hidden=true;if(profiles.length>0){state.selectedLLMProfileId=profiles[0].id;renderLLM();}return;}form.hidden=false;form.elements.id.value=selected.id;form.elements.providerId.value=selected.providerId;form.elements.protocol.value=selected.protocol;form.elements.name.value=selected.name;form.elements.baseUrl.value=selected.baseUrl;form.elements.model.value=selected.model;form.elements.apiKey.value='';form.elements.timeoutMs.value=String(selected.timeoutMs);form.elements.enabled.checked=selected.enabled;form.elements.allowFallback.checked=selected.allowFallback;$('#llm-provider-protocol').textContent=selected.protocol.replaceAll('_',' · ');$('#llm-profile-title').textContent=selected.name;$('#llm-profile-status').textContent=llmStatus(selected);$('#llm-key-mask').textContent=maskText(selected.apiKey);$('#delete-llm-profile').hidden=false;renderRouting();}
function renderRouting(){const routing=state.llmRouting||{primaryProfileId:null,fallbackEnabled:false,fallbackProfileIds:[],maximumAttempts:3};const primary=$('#llm-primary-select');primary.replaceChildren();const none=document.createElement('option');none.value='';none.textContent='未选择';primary.append(none);for(const profile of state.llmProfiles.filter((profile)=>profile.enabled)){const option=document.createElement('option');option.value=profile.id;option.textContent=`${profile.name} · ${profile.model}`;option.selected=profile.id===routing.primaryProfileId;primary.append(option);}const form=$('#llm-routing-form');form.elements.fallbackEnabled.checked=routing.fallbackEnabled;form.elements.maximumAttempts.value=String(routing.maximumAttempts);const fallbackList=$('#llm-fallback-list');fallbackList.replaceChildren();for(const profile of state.llmProfiles.filter((profile)=>profile.enabled&&profile.allowFallback&&profile.id!==routing.primaryProfileId)){const label=document.createElement('label');label.className='fallback-choice';const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.name='fallbackProfileId';checkbox.value=profile.id;checkbox.checked=routing.fallbackProfileIds.includes(profile.id);const text=document.createElement('span');text.textContent=`备用 · ${profile.name}`;label.append(checkbox,text);fallbackList.append(label);}}
async function loadLLM(){const [providerData,profileData]=await Promise.all([api('llm/providers'),api('llm/profiles')]);state.llmProviders=providerData.providers;state.llmProfiles=profileData.profiles;state.llmRouting=profileData.routing;renderProviderOptions();renderLLM();}
function switchPage(name){
  $$('.nav-item[data-page]').forEach((button)=>button.classList.toggle('active',button.dataset.page===name));
  $$('.page').forEach((panel)=>{panel.hidden=panel.dataset.panel!==name;panel.classList.toggle('active',panel.dataset.panel===name);});
  const titles={overview:'概览',services:'密钥与服务',llm:'模型服务',runtime:'运行设置',security:'安全与维护'};$('#page-title').textContent=titles[name];
  if(name==='security')loadAudit();
  if(name==='llm')loadLLM().catch(()=>status('模型服务配置读取失败'));
}

async function loadAudit(){
  try{const {entries}=await api('audit');const list=$('#audit-list');list.replaceChildren();
    for(const entry of entries){const item=document.createElement('li');for(const value of [new Date(entry.timestamp).toLocaleString(),entry.operation,entry.result]){const span=document.createElement('span');span.textContent=value;item.append(span);}list.append(item);}
  }catch{status('审计记录读取失败');}
}

$('#login-form').addEventListener('submit',async(event)=>{
  event.preventDefault();
  const button=event.submitter;
  button.disabled=true;
  $('#login-status').textContent='正在验证…';
  let result;
  try{
    result=await api('login',{method:'POST',body:{password:event.currentTarget.elements.password.value}});
  }catch(error){
    $('#login-status').textContent=error.message==='rate_limited'?'尝试次数过多，请 15 分钟后再试':'密码不正确';
    button.disabled=false;
    return;
  }
  state.csrf=result.csrfToken;
  event.currentTarget.reset();
  $('#login-status').textContent='';
  showApp();
  try{await loadConfig();}catch{status('登录成功，但配置加载失败，请刷新页面');}
  button.disabled=false;
});

$$('.nav-item[data-page]').forEach((button)=>button.addEventListener('click',()=>switchPage(button.dataset.page)));
$('#logout').addEventListener('click',async()=>{try{await api('logout',{method:'POST'});}finally{showLogin();}});

$('#services-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const patch={};for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken']){const value=form.elements[name].value.trim();if(value)patch[name]=value;}try{status('正在加密并应用…');renderConfig(await api('config',{method:'PUT',body:patch}));for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken'])form.elements[name].value='';status('密钥与服务配置已生效');}catch{status('保存失败，请检查输入范围与格式');}});

$('#add-llm-profile').addEventListener('click',()=>$('#provider-dialog').showModal());
$('#add-llm-profile-empty').addEventListener('click',()=>$('#provider-dialog').showModal());
$('#llm-profile-form').addEventListener('submit',async(event)=>{event.preventDefault();const payload=llmProfileDraft();try{const editing=state.llmProfiles.some((profile)=>profile.id===payload.id);await api(editing?`llm/profiles/${payload.id}`:'llm/profiles',{method:editing?'PUT':'POST',body:payload});status('模型档案已加密保存');state.selectedLLMProfileId=payload.id;await loadLLM();}catch{status('保存失败，请检查档案字段和服务端点');}});
$('#refresh-llm-models').addEventListener('click',async()=>{const button=$('#refresh-llm-models');button.disabled=true;try{status('正在读取模型列表…');const result=await api('llm/models',{method:'POST',body:llmProfileDraft()});renderModelOptions(result.models);status(result.error?`无法读取模型列表：${result.error}`:'模型列表已更新');}catch{status('无法读取模型列表，请检查端点和 Key');}finally{button.disabled=false;}});
$('#test-llm-profile').addEventListener('click',async()=>{const id=$('#llm-profile-form').elements.id.value;try{status('正在测试模型档案…');const result=await api(`llm/profiles/${id}/test`,{method:'POST',body:{}});status(result.status==='ok'?'模型档案连接正常':`连接结果：${result.status}`);}catch{status('模型档案测试失败');}});
$('#delete-llm-profile').addEventListener('click',async()=>{const id=$('#llm-profile-form').elements.id.value;if(!window.confirm('确认删除此模型档案？如它正被主模型或备用链引用，系统会拒绝删除。'))return;try{await api(`llm/profiles/${id}`,{method:'DELETE',body:{confirmId:id}});state.selectedLLMProfileId=null;status('模型档案已删除');await loadLLM();}catch{status('删除失败：请先解除主模型或备用链引用');}});
$('#llm-routing-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const routing={primaryProfileId:form.elements.primaryProfileId.value||null,fallbackEnabled:form.elements.fallbackEnabled.checked,fallbackProfileIds:[...form.querySelectorAll('input[name="fallbackProfileId"]:checked')].map((node)=>node.value),maximumAttempts:Number(form.elements.maximumAttempts.value)};try{await api('llm/routing',{method:'PUT',body:routing});status('模型路由策略已生效');await loadLLM();}catch{status('路由策略无效：主模型和备用档案必须已启用');}});

$('#test-services').addEventListener('click',async()=>{try{status('正在测试上游连接…');const result=await api('test-connection',{method:'POST',body:{}});status(result.status==='ok'?'连接正常':`连接结果：${result.status}`);}catch{status('连接测试失败');}});

$('#runtime-form').addEventListener('submit',async(event)=>{event.preventDefault();const settings={};for(const control of event.currentTarget.elements){if(!control.name)continue;settings[control.name]=control.type==='checkbox'?control.checked:Number(control.value);}try{renderConfig(await api('config',{method:'PUT',body:{settings}}));status('运行设置已生效');}catch{status('设置超出允许范围');}});

$('#password-form').addEventListener('submit',async(event)=>{event.preventDefault();try{await api('change-password',{method:'POST',body:{password:event.currentTarget.elements.password.value}});event.currentTarget.reset();showLogin();$('#login-status').textContent='密码已更换，请重新登录';}catch{status('密码更换失败');}});
$('#clear-cache').addEventListener('click',async()=>{try{await api('clear-cache',{method:'POST',body:{}});status('缓存已清理');await loadAudit();}catch{status('缓存清理失败');}});
$('#restart').addEventListener('click',async()=>{if(!window.confirm('确认重启 Broker？App API 会短暂中断。'))return;try{await api('restart',{method:'POST',body:{}});status('重启指令已发送');}catch{status('重启指令发送失败');}});

(async()=>{try{const session=await api('session');state.csrf=session.csrfToken;showApp();await loadConfig();}catch{showLogin();}})();
