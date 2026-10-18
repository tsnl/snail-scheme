// Disposable saves only. Real Chromium/WebGPU, pointer, keyboard and controller
// input verify Scheme onboarding on the same cloud and solo simulation module.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {colony, client} from '../applications/colony-state.mjs';
const [origin, devtools = 'http://127.0.0.1:9452', screenshots, fixture] = process.argv.slice(2);
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(), errors = []; let sequence = 0;
await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
ws.onmessage = event => {
  const data = JSON.parse(event.data);
  if (data.method === 'Runtime.exceptionThrown') errors.push(data.params.exceptionDetails);
  if (data.id) { pending.get(data.id)?.(data); pending.delete(data.id); }
};
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence, timeout = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 30000);
    pending.set(id, data => { clearTimeout(timeout); data.error ? reject(new Error(data.error.message)) : resolve(data.result); });
    ws.send(JSON.stringify({id, method, params}));
  });
}
async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function until(test, message, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { if (await test()) return; await pause(100); }
  throw new Error(message);
}
const world = async () => colony(await evaluate('snailApp.runtime.snapshot(1)'));
const local = async () => client(await evaluate('snailApp.runtime.snapshot(2)'));
const settled = () => until(() => evaluate('!snailApp.localWork && !snailApp.dirty && !snailApp.session.sending && !snailApp.pending.length'), 'input did not settle');
const has = key => evaluate(`!!document.querySelector('[data-ui-key="${key}"]')`);
const title = () => evaluate('document.querySelector("[data-ui-key=context-title]").textContent');
async function ready() {
  await until(async () => { try { return await evaluate('!globalThis.onboardingReload && !!globalThis.snailApp?.session && !snailApp.closing'); } catch { return false; } }, '3D startup');
  await settled();
}
async function reload() { await evaluate('globalThis.onboardingReload=true'); await call('Page.reload'); await ready(); }
async function capture(suffix) {
  if (!screenshots) return;
  const shot = await call('Page.captureScreenshot', {format: 'png'});
  writeFileSync(`${screenshots}-${suffix}.png`, Buffer.from(shot.data, 'base64'));
}
async function press(position) {
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...position, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...position, button: 'left', clickCount: 1}); await settled();
}
async function click(key) {
  const position = await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await press(position);
}
async function point(x, y, z = 0) {
  const position = await evaluate(`(()=>{const m=snailApp.runtime.view().scene.uniforms,r=snailApp.canvas.getBoundingClientRect();
    return{x:r.x+(m[0]*${x}-m[4]*${y}+m[8]*${z}+m[12]+1)*r.width/2,y:r.y+(1-(m[1]*${x}-m[5]*${y}+m[9]*${z}+m[13]))*r.height/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', ...position}); await settled(); return position;
}
async function key(key, code) {
  await evaluate('document.activeElement?.blur()');
  const windowsVirtualKeyCode = key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code, windowsVirtualKeyCode});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code, windowsVirtualKeyCode}); await settled();
}
async function visibleTarget() {
  const tip = await point(11.8, 20, .63);
  assert.equal(await evaluate(`document.elementFromPoint(${tip.x},${tip.y})===snailApp.canvas`), true, 'card covers crystal target');
  const state = await local(); assert.equal(state.cursorX, 12); assert.equal(state.cursorY, 20);
  assert.equal(await title(), 'START: BUILD AN EXTRACTOR');
  return tip;
}
async function markerPixels() {
  return evaluate(`(async()=>{const frame=snailApp.runtime.view(),m=frame.scene.uniforms,c=snailApp.canvas;
    const pixels=await snailApp.renderer.readPixels(frame.scene),x=Math.round((m[0]*12.61-m[4]*20+m[8]*.115+m[12]+1)*c.width/2),
      y=Math.round((1-(m[1]*12.61-m[5]*20+m[9]*.115+m[13]))*c.height/2);let bright=0;
    for(let dy=-2;dy<=2;dy++)for(let dx=-2;dx<=2;dx++){const i=(y+dy)*pixels.bytesPerRow+(x+dx)*4,
      r=pixels.bytes[i+(pixels.format.startsWith('bgra')?2:0)],g=pixels.bytes[i+1],b=pixels.bytes[i+(pixels.format.startsWith('bgra')?0:2)];
      if(r>220&&g>205&&b>95&&b<205)bright++;}return bright;})()`);
}
try {
  await call('Runtime.enable'); await call('Network.enable'); await call('Network.setCacheDisabled', {cacheDisabled: true});
  await call('Emulation.setDeviceMetricsOverride', {width: 1100, height: 760, deviceScaleFactor: 1, mobile: false});
  await call('Page.navigate', {url: origin}); await call('Page.bringToFront'); await ready();
  if (fixture) {
    if (await evaluate('snailApp.target==="solo"')) {
      const saved = JSON.parse(readFileSync(fixture));
      await evaluate(`(async()=>{const manifest=snailApp.manifest;await snailApp.session.close();
        const {openStore}=await import('./lib/application/indexeddb.mjs'),store=await openStore(manifest),prior=await store.load();
        await store.commit({...${JSON.stringify(saved)},revision:(prior?.revision??0)+1},prior?.revision??0);store.close();})()`);
      await reload();
    }
    assert.equal((await world()).outcome, 1); assert.equal(await has('onboarding'), false);
    assert.equal(await title(), 'COLONY LOST'); assert.equal(await has('result'), true);
    assert.equal(await evaluate('document.querySelector("[data-ui-key=restart]").disabled'), false);
    await capture('defeated'); await reload(); assert.equal(await title(), 'COLONY LOST');
    await click('restart'); assert.equal((await world()).outcome, 0); assert.equal(await has('onboarding'), true);
    console.log('ok - defeated durable save explicitly shows COLONY LOST and working restart', origin);
  } else {
    await evaluate('snailApp.local("restart-seed",[1])'); await settled(); await click('pause');
    assert.equal((await world()).buildings.length, 0); assert.equal(await has('onboarding'), true);
    await point(8,22); assert.ok(await markerPixels() > 3, 'persistent deposit ring missing from GPU output');
    await visibleTarget(); await capture('fresh');
    await reload(); await visibleTarget(); assert.equal(await has('onboarding'), true);
    await evaluate('snailApp.local("pan",[25,-25])'); await settled(); await key('h', 'KeyH'); await visibleTarget();
    await evaluate('snailApp.local("pan",[-25,25])'); await settled();
    await evaluate(`(()=>{globalThis.testPad={index:0,id:'onboarding fixture',connected:true,axes:[0,0],buttons:Array.from({length:16},()=>({pressed:false}))};
      Object.defineProperty(navigator,'getGamepads',{configurable:true,value:()=>[testPad]});snailApp.input.pollController(performance.now(),0);
      testPad.buttons[8].pressed=true;snailApp.input.pollController(performance.now(),0);})()`); await settled();
    await evaluate('delete navigator.getGamepads'); await visibleTarget();
    for (const [width,height] of [[390,844],[390,600],[844,390],[640,390]]) {
      await call('Emulation.setDeviceMetricsOverride', {width,height,deviceScaleFactor:1,mobile:true}); await pause(250); await settled();
      if (width === 640 || height === 600) await reload();
      await visibleTarget();
      await key('h','KeyH'); await visibleTarget();
      assert.ok(await evaluate('document.documentElement.scrollWidth<=innerWidth'));
      await capture(`${width < height ? 'portrait' : 'landscape'}-${width}x${height}`);
    }
    await call('Emulation.setDeviceMetricsOverride', {width:1100,height:760,deviceScaleFactor:1,mobile:false}); await pause(250); await settled();
    await press(await visibleTarget()); assert.equal((await world()).buildings[0].kind, 1); assert.equal(await has('onboarding'), false);
    assert.equal(await markerPixels(), 0, 'first order must dismiss the deposit marker');
    await reload(); assert.equal(await has('onboarding'), false); assert.notEqual((await world()).buildings[0].stage, 2);
    await point(11.8,20,.63); await click('cancel-build'); assert.equal(await has('onboarding'), true);
    await press(await visibleTarget()); assert.equal(await has('onboarding'), false);
    await click('pause'); await until(async () => (await world()).buildings[0]?.stage===2, 'extractor completion', 45000);
    await click('pause'); await reload(); assert.equal(await has('onboarding'), false);
    assert.ok((await world()).surveys.some(s=>s.x===12&&s.y===20));
    await point(12,20,.94); await capture('established');
    console.log('ok - prompt and GPU ring, pre-order reload, H/Back, responsive card, crystal tip, cancel/rebuild and completed-save reload', origin);
  }
  assert.deepEqual(errors, []);
} finally { ws.close(); await fetch(`${devtools}/json/close/${target.id}`); }
