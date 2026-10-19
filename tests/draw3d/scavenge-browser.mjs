// Actual compiled Scavenge controls and worker demolition rendered through Chromium WebGPU.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony, client, colonyWords, clientWords, at, pixelAt, setWorker, withdrawReserves} from '../applications/colony-state.mjs';
const origin = process.argv[2], devtools = process.argv[3] ?? 'http://127.0.0.1:9452';
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
ws.onmessage = event => { const data = JSON.parse(event.data); if (data.id) { pending.get(data.id)?.(data); pending.delete(data.id); } };
function call(method, params = {}) {
  return new Promise((resolve, reject) => { const id = ++sequence;
    const timeout = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 30000);
    pending.set(id, data => { clearTimeout(timeout); data.error ? reject(new Error(data.error.message)) : resolve(data.result); });
    ws.send(JSON.stringify({id, method, params})); });
}
async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function until(test, message, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { const value = await test(); if (value) return value; await pause(100); }
  throw new Error(message);
}
const world = async () => colony(await evaluate('snailApp.runtime.snapshot(1)'));
const local = async () => client(await evaluate('snailApp.runtime.snapshot(2)'));
const command = async (binding,args=[]) => {await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`);await settled();};
const displayFrame = () => evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
// Freeze only the fixture clock; a paused World now correctly opens its menu.
const settled = async () => {await evaluate('snailApp.drainUpdates()');await evaluate('snailApp.session.stopClock()');await until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');};

async function restore(world) {
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(world))})`);await settled();
}
async function advance() {
  await evaluate("snailApp.session.local.submit(snailApp.runtime.command('match','advance'))");await settled();
}
async function select(site) {
  const camera=await local();await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords({...camera,
    cameraX:site.x*1000,cameraY:site.y*1000,homing:false,scale:900,chooser:true,targetX:site.x,targetY:site.y}))})`);
  await command('viewport',[await evaluate('innerWidth'),await evaluate('innerHeight')]);await displayFrame();
}
async function click(key) {
  const point=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await call('Input.dispatchMouseEvent',{type:'mousePressed',...point,button:'left',clickCount:1});
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',...point,button:'left',clickCount:1});await settled();
}
async function inspect(suffix) {
  const result=await evaluate(`(async()=>{const nodes=[...document.querySelectorAll('[data-ui-key="context"] button')];
    const boxes=nodes.map(n=>{const r=n.getBoundingClientRect();return{key:n.dataset.uiKey,x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height,blocked:document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)!==n}});
    const clipped=[...document.querySelectorAll('[data-ui-key="context-description"],[data-ui-key$="-caption"]')].filter(n=>n.scrollWidth>n.clientWidth+1||n.scrollHeight>n.clientHeight+1).map(n=>n.dataset.uiKey);
    const pixels=await snailApp.renderer.readPixels(snailApp.runtime.view().scene);return{boxes,clipped,colors:new Set(pixels.bytes).size,lost:snailApp.renderer.resources.lost};})()`);
  assert.deepEqual(result.clipped,[]);assert.equal(result.lost,false);assert.ok(result.colors>30);
  for(const b of result.boxes){assert.ok(b.x>=0&&b.y>=0&&b.right<=await evaluate('innerWidth')+.5&&b.bottom<=await evaluate('innerHeight')+.5,JSON.stringify(b));assert.equal(b.blocked,false);assert.equal(b.width,56);assert.equal(b.height,56);}
  if(process.argv[4]){const shot=await call('Page.captureScreenshot',{format:'png'});writeFileSync(process.argv[4].replace('.png',`-${suffix}.png`),Buffer.from(shot.data,'base64'));}
}
try {
  await call('Runtime.enable');await call('Page.navigate',{url:origin});await call('Page.bringToFront');
  await until(()=>evaluate('!!globalThis.snailApp?.session'),'game startup');await settled();await command('restart-seed',[1]);
  const value=await world(),site=at(value,12,22),point=pixelAt(value,12,22);value.started=true;value.spent=25;value.ore-=25;value.bots.length=1;
  value.buildings=[{id:value.nextId++,kind:3,...site,level:1,hp:90,stock:0,stage:2,cooldown:0,aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1}];
  value.surveys.push({...site,radius:7});setWorker(value,0,{x:12,y:22});await restore(value);
  for(const [width,height]of[[1100,760],[390,844],[320,568],[568,320]]){
    await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<700});await select(site);
    assert.equal(await evaluate('document.querySelector("[data-ui-key=scavenge-caption]").textContent'),'+5 ore');
    assert.equal(await evaluate('document.querySelector("[data-ui-key=scavenge]").disabled'),false);await inspect(`${width}x${height}-quote`);
    await click('scavenge');assert.equal((await world()).ore,value.ore);assert.equal((await world()).bots[0].job,16);
    await select(site);assert.equal(await evaluate('!!document.querySelector("[data-ui-key=scavenge]")'),false);await inspect(`${width}x${height}-working`);
    await click('cancel-build');assert.equal((await world()).bots[0].job,0);assert.equal((await world()).buildings.length,1);
    console.log(`ok - GPU ${width}x${height}: quote, worker assignment, cancel and unclipped controls`);
  }
  await select(site);await call('Input.dispatchKeyEvent',{type:'keyDown',key:'x',code:'KeyX'});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'x',code:'KeyX'});await settled();
  assert.equal((await world()).bots[0].job,16);for(let i=0;i<21;i++)await advance();
  assert.equal((await world()).buildings.length,0);assert.equal((await world()).ore,value.ore+5);console.log('ok - browser X action pays only after worker completion');
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
