// Real Chromium CDP integration; no browser automation package is required.
// Start the packaged server and Chromium with a local DevTools port first.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, renameSync} from 'node:fs';
import {join, resolve} from 'node:path';
const directory = resolve(process.argv[2]), origin = process.argv[3] ?? 'http://127.0.0.1:4173';
const devtools = process.argv[4] ?? 'http://127.0.0.1:9336';
const original = JSON.parse(readFileSync(join(directory, 'manifest.json')));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, message, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { const value = await check(); if (value) return value; await pause(100); }
  throw new Error(message);
}
async function page() {
  const target = await (await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`, {method: 'PUT'})).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let id = 0;
  await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
  ws.onmessage = event => { const value = JSON.parse(event.data); if (value.id) { pending.get(value.id)?.(value); pending.delete(value.id); } };
  const call = (method, params) => new Promise((resolve, reject) => {
    const key = ++id; pending.set(key, value => value.error ? reject(new Error(value.error.message)) : resolve(value.result));
    ws.send(JSON.stringify({id: key, method, params}));
  });
  const evaluate = async expression => {
    const value = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
    if (value.exceptionDetails) throw new Error(value.exceptionDetails.exception?.description ?? value.exceptionDetails.text);
    return value.result.value;
  };
  await until(() => evaluate('!!globalThis.snailApp'), 'browser app did not start');
  return {evaluate, call, close: async () => { ws.close(); await fetch(`${devtools}/json/close/${target.id}`); }};
}
function publish(manifest) {
  writeFileSync(join(directory, 'manifest.test.json'), JSON.stringify(manifest));
  renameSync(join(directory, 'manifest.test.json'), join(directory, 'manifest.json'));
}
const pages = [];
try {
  const a = await page(), b = await page(); pages.push(a, b);
  const clients = await Promise.all(pages.map(p => p.evaluate('snailApp.session.client')));
  assert.notEqual(clients[0], clients[1]);
  await a.evaluate("snailApp.local('restart')"); await until(() => a.evaluate('snailApp.pending.length===0'), 'restart not acknowledged');
  await a.evaluate("snailApp.local('choose',[1]);snailApp.local('move',[8,3]);snailApp.local('confirm')");
  await until(() => a.evaluate('snailApp.pending.length===0'), 'extractor not acknowledged');
  await b.evaluate("snailApp.local('choose',[2]);snailApp.local('move',[7,7]);snailApp.local('confirm')");
  await until(() => b.evaluate('snailApp.pending.length===0'), 'artillery not acknowledged');
  for (const client of clients) await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client,visible:false})});
  await pause(250);
  const worlds = await Promise.all(pages.map(p => p.evaluate('snailApp.runtime.snapshot(1)')));
  assert.deepEqual(worlds[0], worlds[1]); assert.equal(worlds[0][9], 1); assert.equal(worlds[0][15], 1);
  assert.equal(worlds[0][3], 35);
  const pixels = await a.evaluate(`(async()=>{
    const frame=snailApp.runtime.view(), image=await snailApp.renderer.readPixels(frame.quads,960,560);
    const sample=(x,y)=>Array.from(image.bytes.slice(y*image.bytesPerRow+x*4,y*image.bytesPerRow+x*4+4));
    return {background:sample(10,10),hub:sample(140,300),deposit:sample(340,140)};
  })()`);
  assert.notDeepEqual(pixels.background,pixels.hub); assert.notDeepEqual(pixels.background,pixels.deposit);
  console.log('ok - real WebGPU pixel readback contains the Scheme-authored world');
  console.log('ok - two browsers execute Scheme and converge on one purchased world');
  assert.equal(await a.evaluate(`(()=>{
    const before=JSON.stringify(snailApp.runtime.snapshot(1)), local=JSON.stringify(snailApp.runtime.snapshot(2));
    const stale=snailApp.runtime.snapshot(1);stale[3]=9999;
    snailApp.acceptSnapshot({revision:snailApp.revision-1,epoch:'old',state:stale});
    return JSON.stringify(snailApp.runtime.snapshot(1))===before && JSON.stringify(snailApp.runtime.snapshot(2))===local;
  })()`),true);
  console.log('ok - stale authoritative snapshots cannot rewind the world or local selection');


  await a.evaluate("snailApp.local('choose',[2]);snailApp.local('move',[13,7]);globalThis.realFetch=fetch;globalThis.releaseCommand=undefined;globalThis.fetch=(...args)=>args[0]==='/command'?new Promise(resolve=>{globalThis.releaseCommand=()=>resolve(realFetch(...args))}):realFetch(...args);snailApp.local('confirm')");
  const before = await a.evaluate('({world:snailApp.runtime.snapshot(1),local:snailApp.runtime.snapshot(2),pending:JSON.stringify(snailApp.pending)})');
  assert.equal(JSON.parse(before.pending).length, 1);
  const compatible = {...original, generation: `qa-compatible-${Date.now()}`}; publish(compatible);
  await until(() => a.evaluate(`snailApp.generation===${JSON.stringify(compatible.generation)}`), 'compatible reload not activated');
  const after = await a.evaluate('({world:snailApp.runtime.snapshot(1),local:snailApp.runtime.snapshot(2),pending:JSON.stringify(snailApp.pending)})');
  assert.deepEqual(after, before);
  await a.evaluate('globalThis.fetch=realFetch;releaseCommand()');
  await until(() => a.evaluate('snailApp.pending.length===0'), 'preserved request not acknowledged');
  console.log('ok - live Wasm replacement preserves world, cursor, tool and exact pending envelope');

  writeFileSync(join(directory, 'invalid.test.wgsl'), '@vertex definitely not valid WGSL');
  publish({...compatible, generation: `qa-bad-shader-${Date.now()}`, shader: 'invalid.test.wgsl'});
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.includes('Reload rejected')"), 'invalid shader was not visibly rejected');
  assert.equal(await a.evaluate('snailApp.generation'), compatible.generation);
  assert.ok(await a.evaluate('(async()=>{const f=snailApp.runtime.view();const image=await snailApp.renderer.readPixels(f.quads,960,560);return image.bytes.length>0})()'));
  console.log('ok - invalid WGSL keeps previous code and GPU pipeline alive');

  const badSchema = structuredClone(original); badSchema.generation = `qa-schema-${Date.now()}`; badSchema.applications[0].schema++;
  publish(badSchema);
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.includes('endpoint contract')"), 'incompatible schema was not rejected');
  assert.equal(await a.evaluate('snailApp.generation'), compatible.generation);
  publish({...original, generation:`qa-restored-${Date.now()}`});
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.startsWith('LIVE')"), 'valid generation failed to recover');
  const screenshot = await a.call('Page.captureScreenshot', {format:'png'});
  writeFileSync(join(directory, 'browser-check.png'), Buffer.from(screenshot.data, 'base64'));
  const browser = await (await fetch(`${devtools}/json/version`)).json();
  console.log(JSON.stringify({browser:browser.Browser,origin,clients:2,gpu:await a.evaluate('({vendor:snailApp.renderer.adapter?.vendor,architecture:snailApp.renderer.adapter?.architecture,device:snailApp.renderer.adapter?.device,description:snailApp.renderer.adapter?.description})')},null,2));
  console.log('ok - incompatible schema leaves match alive; valid reload recovers');
} catch (error) {
  for (const page of pages) console.error(await page.evaluate("({generation:snailApp.generation,connection:document.querySelector('[data-connection]').textContent,pending:snailApp.pending})"));
  throw error;
} finally {
  publish(original);
  for (const page of pages) await page.close();
}
