// Chromium input, WebGPU readback and durable reopen for either 3D package.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony, client, siteAt} from '../applications/colony-state.mjs';
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
const has = key => evaluate(`!!document.querySelector('[data-ui-key="${key}"]')`);
const command = async (binding,args=[]) => {await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`);await settled();};
const displayFrame = () => evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
const settled = () => until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');
async function press(position) {
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...position, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...position, button: 'left', clickCount: 1}); await settled();
}
async function click(key) {
  const position = await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await press(position);
}
async function pointCell(x, y, click = false, z = 0) {
  const hub=(await world()).surveys.find(s=>s.radius===9); x+=hub.x-8; y+=hub.y-22;
  const position = await evaluate(`(()=>{const scene=snailApp.runtime.view().scene,m=scene.uniforms,r=snailApp.canvas.getBoundingClientRect(),v=scene.viewport??[0,0,r.width,r.height];
    return{x:r.x+v[0]+(m[0]*${x}-m[4]*${y}+m[8]*${z}+m[12]+1)*v[2]/2,y:r.y+v[1]+(1-(m[1]*${x}-m[5]*${y}+m[9]*${z}+m[13]))*v[3]/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', ...position}); await settled();
  if (click) await press(position);
  return position;
}
async function frameCell(x,y) {
  const hub=(await world()).surveys.find(s=>s.radius===9);
  await command('inspect-attack',[hub.x+x-8,hub.y+y-22]);
  await until(async()=>!(await local()).homing,'frame selected test cell');
}
async function capture(suffix='') {
  const clipped=await evaluate(`(()=>[...document.querySelectorAll('[data-ui-key=header] .snail-ui-button-label,[data-ui-key=orbit] .snail-ui-button-label,[data-ui-key=context-actions] .snail-ui-button-label')]
    .filter(label=>label.scrollWidth>label.clientWidth+1||label.closest('button').scrollHeight>label.closest('button').clientHeight+1)
    .map(label=>({key:label.closest('button').dataset.uiKey,text:label.textContent})))()`);
  assert.deepEqual(clipped,[],'visible action labels must fit without ellipsis or a vertical scrollbar');
  if(!process.argv[4])return;
  const shot=await call('Page.captureScreenshot',{format:'png'});
  writeFileSync(process.argv[4].replace('.png',`${suffix}.png`),Buffer.from(shot.data,'base64'));
}
async function touchAt(position) {
  await call('Input.dispatchTouchEvent', {type:'touchStart',touchPoints:[{...position,id:1}]});await displayFrame();
  await call('Input.dispatchTouchEvent', {type:'touchEnd',touchPoints:[]});await displayFrame();await settled();
}
async function touchControl(key) {
  await touchAt(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`));
}
async function key(key, code) {
  await evaluate('document.activeElement?.blur()');
  const windowsVirtualKeyCode=key==='Enter'?13:key==='Escape'?27:key===' '?32:key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code,windowsVirtualKeyCode,...(key==='Enter'?{text:'\r'}:{})});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code,windowsVirtualKeyCode}); await settled();
}try {
  await call('Runtime.enable');await call('Network.enable');await call('Network.setCacheDisabled',{cacheDisabled:true});
  await call('Page.navigate',{url:origin});await call('Page.bringToFront');await until(()=>evaluate('!!globalThis.snailApp'),'3D startup');
  await command('restart-seed',[1]);await command('suspend',[1]);await command('center');
  assert.equal((await world()).buildings.length,0);assert.equal(await has('context'),false);
  assert.equal(await evaluate('!!snailApp.manifest.settings.controller || !!snailApp.manifest.settings.controllerAxes'),false);
  await evaluate('snailApp.session.stopClock()');
  const uploads=await evaluate('globalThis.retainedScene=snailApp.runtime.view().scene;snailApp.renderer.resources.uploads');
  await command('drift',[1,0]);
  assert.equal(await evaluate('snailApp.renderer.resources.uploads'),uploads);
  assert.equal(await evaluate('[0,3,10].every(key=>snailApp.runtime.view().scene.batches.find(b=>b.key===key)===retainedScene.batches.find(b=>b.key===key))'),true);
  await command('home');await until(async()=>!(await local()).homing,'smooth home');await key('Escape','Escape');
  await evaluate('snailApp.session.faulted=false;snailApp.session.startClock()');
  const center=[(await local()).cameraX,(await local()).cameraY],scale=(await local()).scale;
  const wheel=await pointCell(9,23);await call('Input.dispatchMouseEvent',{type:'mouseWheel',...wheel,deltaX:0,deltaY:200});
  await until(async()=>(await local()).scale>scale,'wheel zoom');
  await click('orbit');assert.equal((await local()).scale,12000);await click('orbit');assert.equal((await local()).scale,1000);
  assert.deepEqual([(await local()).cameraX,(await local()).cameraY],center);
  console.log('ok - pan reuses retained geometry; wheel and orbital view preserve the orthographic look-at');

  await pointCell(12,20);assert.equal(await has('context'),false);
  const beforeSelect=await evaluate('snailApp.runtime.snapshot(1)');await key('Enter','Enter');
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeSelect);assert.equal((await world()).paused,1);
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/deposit/i);await capture('-deposit');
  await key('Escape','Escape');assert.equal(await has('context'),false);await key(' ','Space');assert.equal(await has('context'),true);
  assert.equal((await world()).buildings.length,0);await click('extractor');
  assert.equal((await world()).buildings.length,1);assert.equal(await has('context'),false);
  await click('pause');await until(async()=>siteAt(await world(),12,20)?.stage===2,'mine completion',45000);await click('pause');
  await pointCell(12,20,true,.94);assert.equal(siteAt(await world(),12,20).level,1);
  await click('upgrade');assert.equal(siteAt(await world(),12,20).level,2);
  console.log('ok - hover opens nothing, Enter/Space select only, and extractor construction and upgrading use explicit actions');

  await key('Escape','Escape');const chosenSite=await pointCell(12,21),beforeChoice=await evaluate('snailApp.runtime.snapshot(1)');
  await evaluate('globalThis.retainedTrack=snailApp.runtime.view().scene.batches.find(b=>b.key===2)');await press(chosenSite);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeChoice);assert.equal((await local()).preview,0);
  assert.equal(await evaluate('snailApp.runtime.view().scene.batches.find(b=>b.key===2)===retainedTrack'),true);
  const chooser=await evaluate(`(()=>{const panel=document.querySelector('[data-ui-key="context"]'),r=panel.getBoundingClientRect();
    const h=document.querySelector('[data-ui-key="header"]').getBoundingClientRect();return{left:r.left,top:r.top,right:r.right,bottom:r.bottom,
      arrow:Number(panel.dataset.arrow),overlap:r.left<h.right&&h.left<r.right&&r.top<h.bottom&&h.top<r.bottom};})()`);
  const dx=Math.max(chooser.left-chosenSite.x,chosenSite.x-chooser.right,0),dy=Math.max(chooser.top-chosenSite.y,chosenSite.y-chooser.bottom,0);
  assert.ok(dx>0||dy>0);assert.ok(chooser.arrow>0);assert.equal(chooser.overlap,false);
  await capture('-build-boundary');await call('Input.dispatchMouseEvent',{type:'mouseMoved',...await evaluate(`(()=>{const r=document.querySelector('[data-ui-key=artillery]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()`)});await settled();assert.equal((await local()).preview,2);await capture('-build-preview');
  await pointCell(13,21);assert.deepEqual(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="context"]').getBoundingClientRect();return{left:r.left,top:r.top,right:r.right,bottom:r.bottom};})()`),
    {left:chooser.left,top:chooser.top,right:chooser.right,bottom:chooser.bottom});
  await key('1','Digit1');assert.equal(siteAt(await world(),12,21)?.kind,3);
  await click('pause');await until(async()=>siteAt(await world(),12,21)?.stage===2,'locked tower construction',45000);await click('pause');
  const pixels=await evaluate(`(async()=>{const frame=snailApp.runtime.view(),p=await snailApp.renderer.readPixels(frame.scene);return{
    vertices:frame.scene.batches.reduce((n,b)=>n+b.vertices.length/10,0),bytes:p.bytes.length,colors:new Set(Array.from(p.bytes).filter((_,i)=>i%4!==3)).size};})()`);
  assert.ok(pixels.colors>30&&pixels.vertices>1000);
  console.log('ok - a single anchored context card keeps its selected cell through hover and sends the explicit tower order',pixels);

  await pointCell(13,22,true);const ignoredPad=await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})');
  await evaluate(`(()=>{const pad={index:0,id:'ignored gamepad fixture',connected:true,axes:[.8,-.8],buttons:Array.from({length:16},()=>({pressed:true}))};
    Object.defineProperty(navigator,'getGamepads',{configurable:true,value:()=>[pad]});snailApp.input.pollController(performance.now(),0);delete navigator.getGamepads;})()`);
  await settled();assert.deepEqual(await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})'),ignoredPad);
  await key('2','Digit2');assert.equal(siteAt(await world(),13,22)?.level,2);await pointCell(13,22,true);
  const pendingBuild=await evaluate('snailApp.runtime.snapshot(1)');await key('Escape','Escape');assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),pendingBuild);
  await pointCell(13,22,true);await key('c','KeyC');assert.equal(siteAt(await world(),13,22),undefined);
  await key('e','KeyE');await until(async()=>(await local()).turnElapsed===300,'quarter-turn animation');
  await pointCell(12,20,true,.94);assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/extractor/i);
  await key('q','KeyQ');await until(async()=>(await local()).turnElapsed===300,'return rotation');
  await key('Escape','Escape');await key('h','KeyH');await until(async()=>!(await local()).homing,'home selects hub');
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/hub/i);
  const bank=(await world()).ore;await click('worker');assert.equal((await world()).ore,bank-25);assert.equal(await has('context'),true);await capture('-hub-hire');
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/hub/i);
  await key('Escape','Escape');const afterHire=await evaluate('snailApp.runtime.snapshot(1)');await key('f','KeyF');assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),afterHire);
  console.log('ok - gamepad input is unmapped; rotation preserves picking; Escape dismisses, C cancels, and hub hiring keeps its card open');

  await key('n','KeyN');assert.equal(await has('restart-dialog'),true);assert.equal((await world()).paused,1);
  await key('Escape','Escape');assert.equal(await has('restart-dialog'),false);assert.equal((await world()).paused,1);
  await click('pause');await key('n','KeyN');assert.equal((await world()).paused,1);await key('Escape','Escape');assert.equal((await world()).paused,0);await click('pause');
  const committed=await evaluate('snailApp.runtime.snapshot(1)');await evaluate('globalThis.fixtureReload=true');await call('Page.reload');
  await until(()=>evaluate('!globalThis.fixtureReload && !!globalThis.snailApp'),'durable reopen');await settled();
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),committed);
  await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:3,mobile:true});await pause(250);await settled();await command('center');
  await frameCell(12,20);await pointCell(12.4,20,true,.94);
  const mobile=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="pause"]').getBoundingClientRect(),card=document.querySelector('[data-ui-key="context"]').getBoundingClientRect();
    return{width:innerWidth,clientWidth:document.documentElement.clientWidth,scrollWidth:document.documentElement.scrollWidth,cssWidth:snailApp.canvas.getBoundingClientRect().width,canvasWidth:snailApp.canvas.width,canvasHeight:snailApp.canvas.height,
      buttonOnscreen:r.x>=0&&r.right<=innerWidth&&r.y>=0&&r.bottom<=innerHeight,cardOnscreen:card.x>=0&&card.right<=innerWidth&&card.y>=0&&card.bottom<=innerHeight};})()`);
  assert.ok(Math.abs(mobile.width-390)<=1);assert.equal(mobile.scrollWidth,mobile.clientWidth);assert.ok(Math.abs(mobile.cssWidth-mobile.width)<=1);assert.equal(mobile.canvasWidth,1170);assert.equal(mobile.canvasHeight,2532);assert.ok(mobile.buttonOnscreen&&mobile.cardOnscreen);
  await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:2});await key('Escape','Escape');
  await touchAt(await pointCell(13,22));assert.equal(await has('context'),true);assert.equal(siteAt(await world(),13,22),undefined);
  await touchControl('tower');assert.equal(siteAt(await world(),13,22)?.kind,3);
  await touchAt(await pointCell(13,22));await touchControl('cancel-build');assert.equal(siteAt(await world(),13,22),undefined);
  await key('Escape','Escape');const beforePinch=await evaluate('snailApp.runtime.snapshot(1)'),beforeScale=(await local()).scale;
  await call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:160,y:600},{id:2,x:230,y:600}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:125,y:600},{id:2,x:265,y:600}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await displayFrame();await settled();
  assert.ok((await local()).scale<beforeScale);assert.equal((await local()).chooser,false);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforePinch);
  await call('Emulation.setTouchEmulationEnabled',{enabled:false});await command('orbit');await command('orbit');await command('center');await frameCell(12,20);await pointCell(12.4,20,true,.94);
  await capture('-mobile');
  await call('Emulation.setDeviceMetricsOverride',{width:844,height:390,deviceScaleFactor:2,mobile:true});await pause(250);await settled();
  assert.ok(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="context"]').getBoundingClientRect();return r.x>=0&&r.right<=innerWidth&&r.y>=0&&r.bottom<=innerHeight;})()`));
  await capture('-landscape');
  await call('Emulation.clearDeviceMetricsOverride');await pause(250);await settled();await command('center');await frameCell(12,20);await pointCell(12.4,20,true,.94);
  await capture();
  console.log('ok - restart pause restoration, durable reopen, full native DPR, explicit touch actions and pinch without accidental selection',origin);
  await evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))");
  await until(()=>evaluate('snailApp.renderer.resources.closed && snailApp.renderer.resources.textures===0'),'page exit did not drain GPU resources');
  console.log('ok - page exit closes the browser session and disposes GPU resources');
} finally { ws.close();await fetch(`${devtools}/json/close/${target.id}`); }
