// Chromium input, WebGPU readback and durable reopen for either 3D package.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony} from '../applications/colony-state.mjs';
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
const settled = () => until(() => evaluate('!snailApp.localWork && !snailApp.dirty && !snailApp.session.sending && !snailApp.pending.length'), 'input did not settle');
async function press(position) {
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...position, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...position, button: 'left', clickCount: 1}); await settled();
}
async function click(key) {
  const position = await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await press(position);
}
async function pointCell(x, y, click = false, z = 0) {
  const position = await evaluate(`(()=>{const m=snailApp.runtime.view().scene.uniforms,r=snailApp.canvas.getBoundingClientRect();
    return{x:r.x+(m[0]*${x}-m[4]*${y}+m[8]*${z}+m[12]+1)*r.width/2,y:r.y+(1-(m[1]*${x}-m[5]*${y}+m[9]*${z}+m[13]))*r.height/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', ...position}); await settled();
  if (click) await press(position);
  return position;
}
async function touchAt(position) {
  await call('Input.dispatchTouchEvent', {type:'touchStart',touchPoints:[{...position,id:1}]});
  await call('Input.dispatchTouchEvent', {type:'touchEnd',touchPoints:[]}); await settled();
}
async function touchControl(key) {
  await touchAt(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`));
}
async function key(key, code) {
  const windowsVirtualKeyCode=key==='Enter'?13:key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code,windowsVirtualKeyCode,...(key==='Enter'?{text:'\r'}:{})});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code,windowsVirtualKeyCode}); await settled();
}
try {
  await call('Network.enable'); await call('Network.setCacheDisabled', {cacheDisabled:true});
  await call('Page.navigate', {url:origin});
  await call('Page.bringToFront'); await until(() => evaluate('!!globalThis.snailApp'), '3D startup');
  await evaluate('snailApp.local("restart-seed",[1])'); await settled();
  await click('pause'); assert.equal((await world()).paused, 1); assert.equal((await world()).buildings.length, 0);
  await key('Enter','Enter'); assert.equal((await world()).paused,0); assert.equal((await world()).buildings.length,0);
  await key(' ','Space'); assert.equal((await world()).paused,1); assert.equal((await world()).buildings.length,0);
  await pointCell(12, 20);
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'), /BUILD EXTRACTOR/);
  await pointCell(12, 20, true); await until(async () => (await world()).buildings.length === 1, 'deposit click did not create mine');
  await click('pause'); await until(async () => (await world()).buildings[0].stage === 2, 'mine completion');
  await pointCell(12, 20, true, .94); await until(async () => (await world()).buildings[0].level === 2, 'mine roof click did not upgrade');
  await pointCell(12, 21, true); await pointCell(13, 21); await key('1', 'Digit1');
  await until(async () => (await world()).buildings.some(value => value.kind === 3 && value.x === 12 && value.y === 21 && value.stage === 2), 'locked tower choice');
  await until(async () => (await world()).rails.some(value => value.cargo > 0), 'visible loaded rail shuttle', 45000);
  const pixels = await evaluate(`(async()=>{const frame=snailApp.runtime.view(),pixels=await snailApp.renderer.readPixels(frame.scene);
    return{vertices:frame.scene.vertices.length/10,indices:frame.scene.indices.length,bytes:pixels.bytes.length,
      colors:new Set(Array.from(pixels.bytes).filter((_,i)=>i%4!==3)).size};})()`);
  assert.ok(pixels.colors > 30 && pixels.vertices > 1000);
  console.log('ok - real pointer/key contextual mine, upgrade, locked tower, moving freight and WebGPU scene', pixels);
  await click('pause'); await pointCell(12, 21, false, 2.1); await click('move-structure');
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'), /MOVE STRUCTURE/);
  await pointCell(12, 22); const beforeMove = (await world()).ore; await click('confirm-move');
  await until(async () => (await world()).buildings.find(value => value.kind === 3).moveY === 22, 'queued move');
  await pointCell(12, 21, false, 2.1); await click('cancel-build');
  assert.equal((await world()).buildings.find(value => value.kind === 3).moveX, -1); assert.equal((await world()).ore, beforeMove);
  await pointCell(13, 22, true);
  await evaluate(`(()=>{globalThis.testPad={index:0,id:'3D fixture',connected:true,axes:[0,0],buttons:Array.from({length:16},()=>({pressed:false}))};
    Object.defineProperty(navigator,'getGamepads',{configurable:true,value:()=>[testPad]});snailApp.input.pollController(performance.now(),0);
    testPad.buttons[3].pressed=true;snailApp.input.pollController(performance.now(),0);})()`); await settled();
  await until(async () => (await world()).buildings.some(value=>value.kind===2&&value.x===13&&value.y===22), 'controller Y artillery choice');
  await evaluate('delete navigator.getGamepads'); await pointCell(13,22); await click('cancel-build');
  const committed = await evaluate('snailApp.runtime.snapshot(1)');
  await call('Page.reload'); await until(() => evaluate('!!globalThis.snailApp'), 'durable reopen');
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'), committed);
  await call('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
  await pause(250); await settled(); await pointCell(12.4, 20, false, .94);
  assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'), /EXTRACTOR/);
  const mobile = await evaluate(`(()=>{const button=document.querySelector('[data-ui-key="pause"]'),r=button.getBoundingClientRect();
    const card=document.querySelector('[data-ui-key="context"]').getBoundingClientRect();
    return{width:innerWidth,scrollWidth:document.documentElement.scrollWidth,canvasWidth:snailApp.canvas.width,buttonOnscreen:r.x>=0&&r.right<=innerWidth&&r.y>=0&&r.bottom<=innerHeight,
      cardOnscreen:card.x>=0&&card.right<=innerWidth&&card.y>=0&&card.bottom<=innerHeight};})()`);
  assert.ok(Math.abs(mobile.width - 390) <= 1); assert.ok(mobile.scrollWidth <= mobile.width);
  assert.equal(mobile.canvasWidth, 390); assert.ok(mobile.buttonOnscreen && mobile.cardOnscreen);
  await call('Emulation.setTouchEmulationEnabled', {enabled:true,maxTouchPoints:1});
  await touchAt(await pointCell(13,22)); await touchControl('tower');
  await until(async () => (await world()).buildings.some(value=>value.kind===3&&value.x===13&&value.y===22), 'touch tower choice');
  await touchAt(await pointCell(13,22)); await touchControl('cancel-build'); await pointCell(12.4,20,false,.94);
  await call('Emulation.setTouchEmulationEnabled', {enabled:false});
  if (process.argv[4]) { const shot = await call('Page.captureScreenshot', {format: 'png'}); writeFileSync(process.argv[4].replace('.png','-mobile.png'), Buffer.from(shot.data, 'base64')); }
  await call('Emulation.setDeviceMetricsOverride', {width:844,height:390,deviceScaleFactor:1,mobile:true}); await pause(250); await settled();
  assert.ok(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="context"]').getBoundingClientRect();return r.y>=0&&r.bottom<=innerHeight})()`));
  if (process.argv[4]) { const shot = await call('Page.captureScreenshot', {format: 'png'}); writeFileSync(process.argv[4].replace('.png','-landscape.png'), Buffer.from(shot.data, 'base64')); }
  await call('Emulation.clearDeviceMetricsOverride'); await pause(250); await settled();
  await pointCell(12.4,20,false,.94);
  assert.ok(await evaluate(`Array.from(document.querySelectorAll('[data-ui-key="modes"] .snail-ui-button-label')).every(label=>label.scrollWidth<=label.clientWidth)`));
  if (process.argv[4]) { const shot = await call('Page.captureScreenshot', {format: 'png'}); writeFileSync(process.argv[4], Buffer.from(shot.data, 'base64')); }
  console.log('ok - pause without click-through, move/cancel, injected controller Y, touch choice, saved reopen and responsive HUD', origin);
  await evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))");
  await until(() => evaluate('snailApp.renderer.resources.closed && snailApp.renderer.resources.textures===0'), 'page exit did not drain GPU resources');
  console.log('ok - page exit closes the browser session and disposes its GPU resources');
} finally { ws.close(); await fetch(`${devtools}/json/close/${target.id}`); }
