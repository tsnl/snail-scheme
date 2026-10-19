// Disposable browser profile/origin only. Exercises actual IndexedDB aborts,
// page reload, host controls and isolated Wasm playback through Chromium CDP.
import assert from 'node:assert/strict';
import {colony, colonyWords, client} from '../applications/colony-state.mjs';
const [origin, devtools = 'http://127.0.0.1:9543'] = process.argv.slice(2);
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
const socket = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
socket.onmessage = event => {
  const value = JSON.parse(event.data); if (value.id) { pending.get(value.id)?.(value); pending.delete(value.id); }
};
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence, timer = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 30000);
    pending.set(id, value => { clearTimeout(timer); value.error ? reject(new Error(value.error.message)) : resolve(value.result); });
    socket.send(JSON.stringify({id, method, params}));
  });
}
async function evaluate(expression) {
  const value = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (value.exceptionDetails) throw new Error(value.exceptionDetails.exception?.description ?? value.exceptionDetails.text);
  return value.result.value;
}
async function until(expression) {
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    if (await evaluate(expression)) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Browser did not settle: ${expression}`);
}
async function ready() {
  await until('!!globalThis.snailApp?.recording && !globalThis.fixtureReload');
  await evaluate('snailApp.session.stopping=true;clearTimeout(snailApp.session.timer);clearTimeout(snailApp.session.reloading);snailApp.drainUpdates()');
  await until('!snailApp.localWork && !snailApp.dirty');
}
async function click(key) {
  const point = await evaluate(`(()=>{const r=document.querySelector('[data-recording="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', button: 'left', clickCount: 1, ...point});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', button: 'left', clickCount: 1, ...point});
}
try {
  await call('Network.enable'); await call('Network.setCacheDisabled', {cacheDisabled: true});
  await call('Page.navigate', {url: origin}); await call('Page.bringToFront'); await ready();
  assert.equal(await evaluate('snailApp.renderer.resources.lost || snailApp.renderer.resources.closed'), false);
  assert.equal(await evaluate('snailApp.recording.recording.length >= 1'), true);
  const failure = await evaluate(`(async()=>{
    const a=snailApp,r=a.recording.recording,before=a.runtime.snapshot(1),revision=a.revision,last=r.last;
    const put=IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put=function(value,key){if(key==='match')throw new DOMException('recording test quota','QuotaExceededError');return put.call(this,value,key)};
    let message;try{await a.session.local.submit(a.runtime.command('match','pause-colony',[1]))}catch(error){message=error.message}finally{IDBObjectStore.prototype.put=put}
    return{message,unchanged:JSON.stringify(before)===JSON.stringify(a.runtime.snapshot(1)),revision:a.revision===revision,recorded:r.last===last};
  })()`);
  assert.match(failure.message, /recording test quota/); assert.ok(failure.unchanged && failure.revision && failure.recorded);
  await evaluate(`(async()=>{await snailApp.local('resume');await snailApp.drainUpdates();await snailApp.local('restart-seed',[1]);await snailApp.drainUpdates();
    const a=snailApp; await a.session.local.submit(a.runtime.command('match','advance'));
    await a.local('pause-menu');await a.drainUpdates()})()`);
  await until('!snailApp.localWork && !snailApp.dirty && !snailApp.recording.root.hidden');
  await call('Emulation.setDeviceMetricsOverride', {width: 568, height: 320, deviceScaleFactor: 1, mobile: false});
  await until('snailApp.viewport[0]===568 && !snailApp.localWork && !snailApp.dirty');
  assert.equal(await evaluate(`(()=>{const a=snailApp.recording.root.getBoundingClientRect(),b=document.querySelector('[data-ui-key="pause-dialog"]').getBoundingClientRect();return a.right<=b.left||a.left>=b.right||a.bottom<=b.top||a.top>=b.bottom})()`), true);
  await call('Emulation.clearDeviceMetricsOverride'); await until('!snailApp.localWork && !snailApp.dirty');
  await evaluate(`(async()=>{const a=snailApp;await a.prepareGeneration({...a.manifest,generation:a.generation+'-compatible'},++a.reloadTicket)})()`);
  assert.equal(await evaluate('snailApp.recording.recording.entry(snailApp.recording.recording.last).kind'), 'generation');
  const before = await evaluate('(async()=>({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2),revision:snailApp.revision,saved:await snailApp.session.store.load()}))()');
  await click('replay'); await until('!!snailApp.recording.playback && !snailApp.dirty');
  await evaluate('snailApp.recording.seek(snailApp.recording.playback.recording.first)');
  await evaluate('snailApp.local("pan",[2,1])');
  await evaluate('snailApp.local("restart")');
  await until('!snailApp.localWork && !snailApp.dirty');
  assert.equal(await evaluate('snailApp.recording.playback.sequence===snailApp.recording.playback.recording.first'), true);
  const during = await evaluate('(async()=>({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2),revision:snailApp.revision,saved:await snailApp.session.store.load()}))()');
  assert.deepEqual(during, before);
  assert.equal(await evaluate('snailApp.ui.root.inert'), true);
  const pixels = await evaluate('(async()=>{const pixels=await snailApp.renderer.readPixels(snailApp.presentationRuntime.view().scene);return pixels.bytes.length})()');
  assert.ok(pixels > 100000);
  const imported = await evaluate(`(async()=>{const {RunRecording}=await import('./lib/application/recording.mjs');
    const a=snailApp,dump=await a.recording.recording.exportBlob().arrayBuffer();
    const recording=RunRecording.import(dump);await a.recording.replay(recording);return{length:recording.length,enabled:recording.enabled}})()`);
  assert.ok(imported.length >= 3); assert.equal(imported.enabled, false);
  await click('close'); await until('!snailApp.recording.replaying && !snailApp.dirty');
  assert.equal(await evaluate('snailApp.ui.root.inert'), false);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'), before.world);
  const settledClient = await evaluate(`(async()=>{
    const a=snailApp,commit=a.session.store.commit.bind(a.session.store);let release,entered;
    const gate=new Promise(resolve=>release=resolve),ready=new Promise(resolve=>entered=resolve);
    a.session.store.commit=async(...args)=>{entered();await gate;return commit(...args)};
    const resume=a.local('resume');await ready;const replay=a.recording.replay();release();
    await Promise.all([resume,replay]);a.session.store.commit=commit;return a.runtime.snapshot(2);
  })()`);
  assert.equal(client(settledClient).dialogPending, 0, 'durable reverse replies settle in live Client before replay opens');
  await evaluate(`(async()=>{const r=snailApp.recording;await r.seek(r.playback.recording.first);r.play();r.pause();r.play();r.pause();await snailApp.drainUpdates()})()`);
  const stoppedAt = await evaluate('snailApp.recording.playback.sequence');
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(await evaluate('snailApp.recording.playback.sequence'), stoppedAt, 'old Play work cannot schedule another timer after Stop');
  await evaluate('snailApp.recording.exit()');
  assert.equal(await evaluate(`(async()=>{const a=snailApp,original=fetch;let release,entered;
    const gate=new Promise(resolve=>release=resolve),ready=new Promise(resolve=>entered=resolve);
    globalThis.fetch=async(...args)=>{if(String(args[0]).endsWith('.wasm')){entered();await gate}return original(...args)};
    try{const open=a.recording.replay();await ready;const exit=a.recording.exit();release();await Promise.all([open,exit]);return !a.recording.replaying&&!a.recording.playback}
    finally{globalThis.fetch=original}})()`), true, 'Exit cancels an in-flight replay open');
  const finished = colony(before.world); Object.assign(finished, {started: true, outcome: 1, hull: 0, tick: 42});
  const finishedWords = colonyWords(finished);
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(finishedWords)})`);
  const finishedRevision = await evaluate('snailApp.revision');
  await evaluate('globalThis.fixtureReload=true'); await call('Page.reload'); await ready();
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'), finishedWords);
  const after = await evaluate('({first:snailApp.recording.recording.entry(0),length:snailApp.recording.recording.length,revision:snailApp.revision})');
  assert.equal(after.first.kind, 'checkpoint'); assert.equal(after.first.revision, finishedRevision);
  assert.ok(after.length < imported.length); assert.equal(after.revision, finishedRevision);
  assert.deepEqual(await evaluate('Array.from(snailApp.recording.recording.snapshot(0))'), finishedWords);
  console.log('ok - actual IndexedDB failure records nothing; generation boundary retained; replay/camera/import/gameplay keys preserve live owners/save; reload records only the finished saved checkpoint');
} finally {
  await evaluate('snailApp.session.close()').catch(() => {});
  socket.close(); await fetch(`${devtools}/json/close/${target.id}`);
}
