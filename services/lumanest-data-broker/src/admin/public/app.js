const state={csrf:null,config:null};
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
  const labels={qweatherPrivateKey:'和风私钥',amapWebKey:'高德地图',aiApiKey:'AI 文案',serviceToken:'App 访问'};
  for(const [name,label] of Object.entries(labels))grid.append(tile(label,config.services[name]));
  for(const [name,value] of Object.entries(config.services))setMask(name,value);
  $('#services-form').elements.aiModel.value=config.aiModel||'';
  $('#services-form').elements.aiBaseUrl.value=config.aiBaseUrl||'';
  for(const [name,value] of Object.entries(config.settings)){
    const control=$('#runtime-form').elements[name];if(!control)continue;
    if(control.type==='checkbox')control.checked=value;else control.value=String(value);
  }
}

async function loadConfig(){renderConfig(await api('config'));}
function switchPage(name){
  $$('.nav-item[data-page]').forEach((button)=>button.classList.toggle('active',button.dataset.page===name));
  $$('.page').forEach((panel)=>{panel.hidden=panel.dataset.panel!==name;panel.classList.toggle('active',panel.dataset.panel===name);});
  const titles={overview:'概览',services:'密钥与服务',runtime:'运行设置',security:'安全与维护'};$('#page-title').textContent=titles[name];
  if(name==='security')loadAudit();
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

$('#services-form').addEventListener('submit',async(event)=>{event.preventDefault();const form=event.currentTarget;const patch={};for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken','aiApiKey']){const value=form.elements[name].value.trim();if(value)patch[name]=value;}patch.aiModel=form.elements.aiModel.value.trim();patch.aiBaseUrl=form.elements.aiBaseUrl.value.trim();try{status('正在加密并应用…');renderConfig(await api('config',{method:'PUT',body:patch}));for(const name of ['keyId','projectId','qweatherPrivateKeyPem','amapWebKey','serviceToken','aiApiKey'])form.elements[name].value='';status('密钥与服务配置已生效');}catch{status('保存失败，请检查输入范围与格式');}});

$('#test-services').addEventListener('click',async()=>{try{status('正在测试上游连接…');const result=await api('test-connection',{method:'POST',body:{}});status(result.status==='ok'?'连接正常':`连接结果：${result.status}`);}catch{status('连接测试失败');}});

$('#runtime-form').addEventListener('submit',async(event)=>{event.preventDefault();const settings={};for(const control of event.currentTarget.elements){if(!control.name)continue;settings[control.name]=control.type==='checkbox'?control.checked:Number(control.value);}try{renderConfig(await api('config',{method:'PUT',body:{settings}}));status('运行设置已生效');}catch{status('设置超出允许范围');}});

$('#password-form').addEventListener('submit',async(event)=>{event.preventDefault();try{await api('change-password',{method:'POST',body:{password:event.currentTarget.elements.password.value}});event.currentTarget.reset();showLogin();$('#login-status').textContent='密码已更换，请重新登录';}catch{status('密码更换失败');}});
$('#clear-cache').addEventListener('click',async()=>{try{await api('clear-cache',{method:'POST',body:{}});status('缓存已清理');await loadAudit();}catch{status('缓存清理失败');}});
$('#restart').addEventListener('click',async()=>{if(!window.confirm('确认重启 Broker？App API 会短暂中断。'))return;try{await api('restart',{method:'POST',body:{}});status('重启指令已发送');}catch{status('重启指令发送失败');}});

(async()=>{try{const session=await api('session');state.csrf=session.csrfToken;showApp();await loadConfig();}catch{showLogin();}})();
