// Disposable saves only. Real Chromium/WebGPU and explicit pointer actions
// verify first-extractor guidance on the compiled browser simulation module.
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
const local = async () => {
  const value=client(await evaluate('snailApp.runtime.snapshot(2)')),hub=(await world()).surveys.find(s=>s.radius===9);
  return {...value,cursorX:value.cursorX<0?-1:value.cursorX-hub.x+8,cursorY:value.cursorY<0?-1:value.cursorY-hub.y+22};
};
const settled = () => until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');
const has = key => evaluate(`!!document.querySelector('[data-ui-key="${key}"]')`);
const title = () => evaluate('document.querySelector("[data-ui-key=context-title]").textContent');
const command=async(binding,args=[])=>{await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`);await settled();};
async function home(){await key('h','KeyH');await until(async()=>!(await local()).homing,'smooth hub home');}
async function frameDeposit(){
  const hub=(await world()).surveys.find(s=>s.radius===9);
  await command('inspect-attack',[hub.x+4,hub.y-2]);await until(async()=>!(await local()).homing,'deposit framing');
}
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
  const hub=(await world()).surveys.find(s=>s.radius===9); x+=hub.x-8; y+=hub.y-22;
  const position = await evaluate(`(()=>{const scene=snailApp.runtime.view().scene,m=scene.uniforms,r=snailApp.canvas.getBoundingClientRect(),v=scene.viewport??[0,0,r.width,r.height];
    return{x:r.x+v[0]+(m[0]*${x}-m[4]*${y}+m[8]*${z}+m[12]+1)*v[2]/2,y:r.y+v[1]+(1-(m[1]*${x}-m[5]*${y}+m[9]*${z}+m[13]))*v[3]/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', ...position}); await settled(); return position;
}
async function key(key, code) {
  await evaluate('document.activeElement?.blur()');
  const windowsVirtualKeyCode = key==='Escape'?27:key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code, windowsVirtualKeyCode});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code, windowsVirtualKeyCode}); await settled();
}
async function visibleTarget() {
  const tip = await point(11.8, 20, .63);
  assert.equal(await evaluate(`document.elementFromPoint(${tip.x},${tip.y})===snailApp.canvas`), true, 'card covers crystal target');
  const state = await local(); assert.equal(state.cursorX, 12); assert.equal(state.cursorY, 20);
  assert.equal(await has('context'),false);
  return tip;
}
async function markerPixels() {
  const hub=(await world()).surveys.find(s=>s.radius===9),wx=hub.x+4.61,wy=hub.y-2;
  return evaluate(`(async()=>{const frame=snailApp.runtime.view(),m=frame.scene.uniforms,c=snailApp.canvas;
    const pixels=await snailApp.renderer.readPixels(frame.scene),x=Math.round((m[0]*${wx}-m[4]*${wy}+m[8]*.115+m[12]+1)*c.width/2),
      y=Math.round((1-(m[1]*${wx}-m[5]*${wy}+m[9]*.115+m[13]))*c.height/2);let bright=0;
    for(let dy=-2;dy<=2;dy++)for(let dx=-2;dx<=2;dx++){const i=(y+dy)*pixels.bytesPerRow+(x+dx)*4,
      r=pixels.bytes[i+(pixels.format.startsWith('bgra')?2:0)],g=pixels.bytes[i+1],b=pixels.bytes[i+(pixels.format.startsWith('bgra')?0:2)];
      if(r>220&&g>205&&b>95&&b<205)bright++;}return bright;})()`);
}
async function checkAttackToasts() {
  await command('resume');await evaluate('snailApp.session.stopClock()');await command('dismiss');
  const saved=await evaluate('snailApp.runtime.snapshot(1)');
  for(const[width,height]of[[1100,760],[390,844],[844,390]]){
    await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:2,mobile:width<900});await pause(250);await settled();
    const count=3; // This fixture has three alerts and each viewport fits three 88px cards.
    const frame=await evaluate(`(()=>{const scene=snailApp.runtime.view().scene;return{insets:scene.insets.map(view=>({key:view.key,rect:view.rect})),
      resources:snailApp.renderer.resources,cards:[...document.querySelectorAll('[data-ui-key^="attack-toast-"]')].map(e=>e.getBoundingClientRect().toJSON())};})()`);
    assert.equal(frame.cards.length,count);assert.equal(frame.insets.length,count);assert.equal(frame.resources.insets,count);assert.equal(frame.resources.textures,1+2*count);
    assert.equal(frame.resources.insetPixels,32*24*count);
    for(const rect of frame.cards)assert.ok(rect.x>=0&&rect.y>=0&&rect.right<=width+1&&rect.bottom<=height+1);
    for(const{rect:[x,y,w,h]}of frame.insets){assert.deepEqual([w,h],[64,48]);assert.ok(x>=0&&y>=0&&x+w<=width&&y+h<=height);}
    const colors=await evaluate(`(async()=>{const scene=snailApp.runtime.view().scene,p=await snailApp.renderer.readPixels(scene),[x,y,w,h]=scene.insets[0].rect;
      const sx=snailApp.canvas.width/snailApp.viewport[0],sy=snailApp.canvas.height/snailApp.viewport[1];
      const colors=new Set();for(let py=Math.ceil(y*sy);py<(y+h)*sy;py++)for(let px=Math.ceil(x*sx);px<(x+w)*sx;px++){
        const i=py*p.bytesPerRow+px*4;colors.add(Array.from(p.bytes.subarray(i,i+3)).join(','));}return colors.size;})()`);
    assert.ok(colors>12,'live thumbnail must contain rendered world geometry');await capture(`attacks-${width}x${height}`);
  }
  const first=(await world()).alerts[0];const key=await evaluate(`document.querySelector('[data-ui-key^="attack-toast-"]').dataset.uiKey`);
  await click(key);await until(async()=>!(await local()).homing,'attack camera travel');
  const state=await local();assert.equal(state.cameraX,first.x*1000);assert.equal(state.cameraY,first.y*1000);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),saved);
  console.log('ok - bounded attack cards show rendered live insets at desktop, portrait and landscape sizes; inspection only moves the camera',origin);
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
    if((await world()).outcome===0)await checkAttackToasts();
    else {
      assert.equal((await world()).outcome,1);assert.equal(await has('onboarding'),false);
      assert.match(await title(),/colony lost/i);assert.equal(await has('result'),true);
      assert.equal(await evaluate('document.querySelector("[data-ui-key=restart]").disabled'),false);
      await capture('defeated');await reload();assert.match(await title(),/colony lost/i);
      await click('restart');assert.equal((await world()).outcome,1);assert.equal(await has('restart-dialog'),true);
      await click('accept-restart');assert.equal((await world()).outcome,0);assert.equal(await has('context'),false);
      console.log('ok - defeated durable save renders a zero-worker HUD and explicitly confirms restart',origin);
    }
  } else {
    await command('resume');await command('restart-seed',[1]);await evaluate('snailApp.session.stopClock()');await command('center');
    assert.equal((await world()).buildings.length,0);assert.equal(await has('onboarding'),false);assert.equal(await has('context'),false);
    await point(8,22);assert.ok(await markerPixels()>3,'persistent deposit ring missing from GPU output');
    await visibleTarget();await capture('fresh');await reload();await visibleTarget();
    await command('pan',[25,-25]);await home();assert.match(await title(),/hub/i);
    await key('Escape','Escape');await command('center');await visibleTarget();
    for(const[width,height]of[[390,844],[390,600],[844,390],[640,390]]){
      await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:true});await pause(250);await settled();
      if(width===640||height===600)await reload();
      await command('center');await press(await visibleTarget());assert.match(await title(),/deposit/i);
      assert.equal((await world()).buildings.length,0);
      assert.ok(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key=context]').getBoundingClientRect();
        return r.left>=0&&r.top>=0&&r.right<=innerWidth&&r.bottom<=innerHeight&&document.documentElement.scrollWidth<=innerWidth;})()`));
      await capture(`${width<height?'portrait':'landscape'}-${width}x${height}`);
      await key('Escape','Escape');await home();assert.match(await title(),/hub/i);await key('Escape','Escape');
    }
    await call('Emulation.setDeviceMetricsOverride',{width:1100,height:760,deviceScaleFactor:1,mobile:false});await pause(250);await settled();
    await command('center');await press(await visibleTarget());assert.equal((await world()).buildings.length,0);await click('extractor');
    assert.equal((await world()).buildings[0].kind,1);assert.equal(await has('context'),false);
    assert.equal(await markerPixels(),0,'first order must dismiss the deposit marker');
    await reload();assert.notEqual((await world()).buildings[0].stage,2);await frameDeposit();
    await press(await point(11.8,20,.63));await click('cancel-build');assert.equal((await world()).buildings.length,0);
    await command('center');await press(await visibleTarget());await click('extractor');
    await click('pause');await until(async()=>(await world()).buildings[0]?.stage===2,'extractor completion',45000);
    await click('pause');await reload();assert.equal(await has('context'),false);
    const w=await world(),hub=w.surveys.find(s=>s.radius===9);assert.ok(w.surveys.some(s=>s.x===hub.x+4&&s.y===hub.y-2));
    await command('center');assert.equal((await local()).cursorX,8);assert.equal((await local()).cursorY,22);
    await frameDeposit();await press(await point(12,20,.94));assert.match(await title(),/extractor/i);await capture('established');
    console.log('ok - GPU guidance marker, responsive explicit cards, H hub selection, crystal tip, cancel/rebuild and completed-save reload',origin);
  }
  assert.deepEqual(errors,[]);
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
