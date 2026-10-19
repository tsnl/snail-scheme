// Run against a disposable static game: this test starts a fresh colony.
// Real Chromium clicks cover local construction and durable reload.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony, client, siteAt} from '../applications/colony-state.mjs';
const origin = process.argv[2], devtools = process.argv[3] ?? 'http://127.0.0.1:9452';
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
const trace = [];
ws.onmessage = event => { const data = JSON.parse(event.data);
  if (data.method?.startsWith('Network.') || data.method === 'Runtime.exceptionThrown') trace.push(data); if (data.id) { pending.get(data.id)?.(data); pending.delete(data.id); } };
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
async function settled() {
  await evaluate('snailApp.drainUpdates()');
  await until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');
}
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
const acknowledged = settled;
async function ready() { await until(() => evaluate('!globalThis.fixtureReload && !!globalThis.snailApp'), '3D startup'); await settled(); }
async function reload() { await evaluate('globalThis.fixtureReload=true');await call('Page.reload');await ready(); }
async function capture(suffix) {
  if (!process.argv[4]) return;
  const shot = await call('Page.captureScreenshot', {format: 'png'});
  writeFileSync(process.argv[4].replace('.png', suffix+'.png'), Buffer.from(shot.data, 'base64'));
}
async function complete(kind, x, y) {
  await until(async () => { const site=siteAt(await world(),x,y);
    return site?.kind===kind && site.stage===2; }, 'construction did not complete', 45000);
}
async function carrying(site, cost) {
  await until(async () => (await world()).bots.some(bot=>bot.job===3 && bot.target===site.id && bot.cargo===cost),
    'builder did not pick up the construction kit');
}
try {
  await call('Network.enable'); await call('Runtime.enable');
  await call('Network.setCacheDisabled', {cacheDisabled:true}); await call('Page.navigate', {url:origin});
  await call('Page.bringToFront'); await ready();

  if((await world()).paused===1){await evaluate('snailApp.local("resume")');await acknowledged();}
  await evaluate('snailApp.local("restart-seed",[1])'); await acknowledged();
  await pointCell(10,21,true);
  assert.equal((await local()).chooser,true);
  assert.equal(await evaluate('document.querySelector("[data-ui-key=tower]")?.disabled'),true);
  assert.equal((await world()).ore,160);assert.equal((await world()).started,false);
  await click('close-context');await pointCell(12,20,true);
  assert.equal(await evaluate('document.querySelector("[data-ui-key=extractor]")?.disabled'),false);
  assert.equal((await world()).buildings.length,0);await capture('-selected');await click('extractor');await acknowledged();
  const ordered=await world();assert.equal(ordered.ore,120);assert.equal(ordered.spent,40);assert.equal(ordered.started,true);
  const extractor=siteAt(ordered,12,20);assert.equal(extractor?.kind,1);assert.equal(ordered.buildings.length,1);
  assert.equal((await local()).buildKind,0);assert.equal((await local()).chooser,false);
  await carrying(extractor,40);await complete(1,12,20);await reload();await acknowledged();
  const restoredExtractor=siteAt(await world(),12,20);
  assert.equal(restoredExtractor?.id,extractor.id);assert.equal(restoredExtractor.kind,1);assert.equal(restoredExtractor.stage,2);
  assert.equal((await world()).paused,0);

  const beforeTower=await world();await pointCell(10,21,true);
  assert.equal((await world()).buildings.length,beforeTower.buildings.length);
  assert.equal((await local()).chooser,true);
  assert.equal(await evaluate('document.querySelector("[data-ui-key=tower]")?.disabled'),false);
  await click('tower');await acknowledged();
  const building=await world();assert.equal(building.spent,beforeTower.spent+25);
  assert.equal(building.ore,160+building.delivered+building.localSpent-building.spent);
  const tower=siteAt(building,10,21);assert.equal(tower?.kind,3);assert.equal(building.buildings.length,2);
  assert.equal((await local()).buildKind,0);assert.equal((await local()).chooser,false);
  await carrying(tower,25);await complete(3,10,21);
  const completed=await world(); await reload(); await acknowledged(); const reopened=await world();
  assert.deepEqual(reopened.buildings.map(b=>[b.id,b.kind,b.x,b.y,b.stage]),completed.buildings.map(b=>[b.id,b.kind,b.x,b.y,b.stage]));
  assert.equal(reopened.spent,completed.spent); assert.equal(reopened.paused,0); assert.ok(reopened.tick>=completed.tick);
  await until(async()=> (await world()).tick>reopened.tick, 'reopened colony clock did not resume');
  await pointCell(10,21,true,1.35); await capture('');

  const errors=trace.filter(e=>e.method==='Runtime.exceptionThrown'); assert.equal(errors.length,0);
  console.log('ok - actual mouse selection is free; Extractor then Tower buttons order kits, workers complete them, and active reload persists', {origin,spent:reopened.spent,buildings:reopened.buildings.length,tick:reopened.tick});
} finally {
  if(process.argv[4])writeFileSync(process.argv[4].replace('.png','-trace.json'),JSON.stringify(trace,null,2));
  ws.close(); await fetch(`${devtools}/json/close/${target.id}`);
}
