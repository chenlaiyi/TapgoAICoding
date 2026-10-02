/** Isolated HTTPS RPC/WebSocket fixture; contains no real accounts or pairing tokens. */
import https from 'node:https'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(new URL('../../../apps/desktop/package.json',import.meta.url))
const {WebSocketServer}=require('ws')
const key=process.env.TAPGO_ANDROID_FIXTURE_KEY
if(!key)throw new Error('Set TAPGO_ANDROID_FIXTURE_KEY to the local generated test key')
const follows=new Map();let nextSeq=2;
let questionAnswered=false;let approvalAnswered=false
const server=https.createServer({key:readFileSync(key),cert:readFileSync(new URL('../app/src/debug/res/raw/fixture_ca.pem',import.meta.url))},(req,res)=>{
 let body='';req.on('data',part=>body+=part);req.on('end',()=>{
  if(req.url==='/reset'){approvalAnswered=false;questionAnswered=false;res.end('reset');return}
  if(req.url==='/health'){res.end('ready');return}
  if(req.url.startsWith('/api/')){
   if(!req.headers.cookie?.includes('fixture-auth=accepted')){res.writeHead(401).end();return}
   const rpc=JSON.parse(body);if(rpc.type!=='client-request'||!rpc.rpcId||!rpc.payload?.args){res.writeHead(400).end();return}
   let value={}
   if(rpc.method==='session/list')value={items:[{sessionId:'session-one',cwd:'/work/Android',updatedAt:3,running:false,projections:{values:{title:'Android 验收对话'}}}]}
   if(rpc.method==='directoryPicker/list')value={path:rpc.payload.args.path||'/work',home:'/work',crumbs:[{name:'work',path:'/work'}],entries:[],truncated:false};
   if(rpc.method==='directoryPicker/createDirectory')value=rpc.payload.args.path+'/'+rpc.payload.args.name;
   if(rpc.method==='workspace/create')value={workspace:{workspaceId:'project-two',path:rpc.payload.args.request.path,title:'安卓新项目'}};
   if(rpc.method==='session/create'){if(rpc.payload.args.request.workspaceId!=='project-two'){res.writeHead(400).end();return}value={sessionId:'session-two'}};
   if(rpc.method==='account/getBalance')value={status:'ready',value:[{currency:'CNY',balance:'10.00'}],bonusWallets:[{currency:'CNY',balance:'2.50'}]};
   if(rpc.method==='session/modelCatalog')value={groups:[{id:'fixture',models:[{id:'fixture-model',name:'验收模型'}]}]};
   if(rpc.method==='permissionPresets/catalog')value={options:[{value:'safe',name:'安全模式',description:'验收权限确认'}]};
   if(rpc.method==='commands/execute')value={result:{kind:'success'}};
   if(rpc.method==='session/prompt'){
    const request=rpc.payload.args.request;
    if(request.sessionId!=='session-one'||!request.requestId||request.mode!=='queue'||!['模拟器消息','停止验收'].includes(request.content?.[0]?.text)){res.writeHead(400).end();return}
    if(request.content[0].text==='模拟器消息'&&(request.content[1]?.type!=='image'||request.content[1]?.mediaType!=='image/jpeg'||!request.content[1]?.data?.startsWith('/9j/'))){res.writeHead(400).end();return}
    for(const [socket,streamId] of follows){const emit=value=>socket.send(JSON.stringify({type:'item',streamId,value}));
     emit({type:'event',event:{seq:nextSeq++,type:'user/message',data:{source:{kind:'user'},content:request.content}}});
     emit({type:'event',event:{seq:nextSeq++,type:'turn/start',data:{}}});
     if(request.content[0].text==='停止验收')continue;
     emit({type:'assistant-stream',frame:{type:'start'}});
     emit({type:'assistant-stream',frame:{type:'chunk',chunk:{type:'text-delta',text:'流式验收回复'}}});
     emit({type:'event',event:{seq:nextSeq++,type:'assistant/message',data:{message:{content:[{type:'text',text:'流式验收回复'}]}}}});
     emit({type:'event',event:{seq:nextSeq++,type:'turn/end',data:{}}});
    }
   }
   if(rpc.method==='session/cancel'){if(rpc.payload.args.request.sessionId!=='session-one'){res.writeHead(400).end();return}for(const [socket,streamId] of follows)socket.send(JSON.stringify({type:'item',streamId,value:{type:'event',event:{seq:nextSeq++,type:'turn/end',data:{}}}}))}
   if(rpc.method==='$events/result'){
    if(rpc.payload.args.clientId!=='android-fixture'||!['approval-one','question-one'].includes(rpc.payload.args.eventId)){res.writeHead(400).end();return}
    if(rpc.payload.args.eventId==='approval-one')approvalAnswered=rpc.payload.args.outcome.value==='allowed-once';
    else {if(rpc.payload.args.outcome.value?.answers?.[0]?.selected?.[0]!=='继续验收'){res.writeHead(400).end();return}questionAnswered=true}
   }
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify({result:{ok:true,value}}));return
  }
  if(req.url.includes('token=fixture')){res.setHeader('Set-Cookie','fixture-auth=accepted; Path=/; Secure; HttpOnly; SameSite=Strict');res.writeHead(303,{Location:'./'}).end();return}
  else if(!req.headers.cookie?.includes('fixture-auth=accepted')){res.writeHead(401).end();return}
  res.setHeader('Content-Type','text/html');res.end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Android 工作区验收</title><h1>Android 工作区验收</h1><p id="selection"></p><button>模型</button><button>权限</button><input placeholder="发送消息"><button>发送</button><input type="file" accept="image/*"><script>document.querySelector('#selection').textContent=JSON.parse(localStorage.getItem('dsh.sessions.current')||'{}').sessionId||'新对话'</script>`)
 })
})
const sockets=new WebSocketServer({server,path:'/api/remote.mux'})
sockets.on('connection',(socket,request)=>{
 if(!request.headers.cookie?.includes('fixture-auth=accepted')){socket.close();return}
 socket.on('message',raw=>{const open=JSON.parse(raw);
  const send=value=>socket.send(JSON.stringify({type:'item',streamId:open.streamId,value}))
  if(open.endpoint==='workspace/follow'){send({type:'baseline',value:{items:[]}});return}
  if(open.endpoint==='session/follow'){follows.set(socket,open.streamId);socket.on('close',()=>follows.delete(socket));send({type:'snapshot',projections:{values:{tokenUsage:{uncachedInputTokens:75,outputTokens:25},contextPressure:{contextWindow:1000,projectedTokens:250}}},records:[{event:{seq:1,type:'assistant/message',data:{message:{content:[{type:'text',text:'安卓原生对话已连接'}]}}}}]});return}
  if(open.endpoint!=='$events')return;
  send({type:'ready',clientId:'android-fixture'})
  if(!approvalAnswered)send({type:'waterfall',eventId:'approval-one',agentId:'session-one',event:'approval/request',request:{toolName:'fixture-check',reason:'模拟器隔离审批测试'}})
  if(!questionAnswered)send({type:'waterfall',eventId:'question-one',agentId:'session-one',event:'user-questions/request',request:{questions:[{id:'continue',question:'是否继续模拟器验收？',options:[{label:'继续验收'},{label:'稍后'}]}]}})

 })
})
const port=Number(process.env.TAPGO_ANDROID_FIXTURE_PORT||0)
if(!Number.isInteger(port)||port<0||port>65535)throw new Error('Invalid fixture port')
server.listen(port,'127.0.0.1',()=>console.log(JSON.stringify({ready:true,port:server.address().port})))
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{for(const socket of sockets.clients)socket.terminate();sockets.close();server.close(()=>process.exit(0));server.closeAllConnections()})
