// Real Chromium CDP integration; no browser automation package is required.
// Start the packaged server and Chromium with a local DevTools port first.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, renameSync, copyFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {colony} from './colony-state.mjs';
const directory = resolve(process.argv[2]), origin = process.argv[3] ?? 'http://127.0.0.1:4173';
const devtools = process.argv[4] ?? 'http://127.0.0.1:9336';
const fixtures = resolve(process.argv[5] ?? join(import.meta.dirname, '../../build/application-tests'));
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
    const key = ++id, timeout = setTimeout(() => {
      pending.delete(key); reject(new Error(`DevTools timed out: ${method}`));
    }, 15000);
    pending.set(key, value => {
      clearTimeout(timeout); value.error ? reject(new Error(value.error.message)) : resolve(value.result);
    });
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
  async function seedForm(value) {
    await a.call('Page.bringToFront');
    await a.evaluate("document.querySelector('#next-run-seed').focus();document.querySelector('#next-run-seed').select()");
    await a.call('Input.insertText',{text:value});
    await a.call('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,text:'\r'});
    await a.call('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
    await until(()=>a.evaluate('snailApp.pending.length===0'),'seed form not acknowledged');
  }
  await a.evaluate("snailApp.local('suspend',[1])"); await until(()=>a.evaluate('snailApp.pending.length===0'),'pause not acknowledged');
  const untouched={world:await a.evaluate('snailApp.runtime.snapshot(1)'),epoch:(await (await fetch(origin+'/snapshot')).json()).epoch};
  await seedForm('0'); const invalid=await a.evaluate('snailApp.runtime.snapshot(1)');
  untouched.world[17]=16; assert.deepEqual(invalid,untouched.world);
  assert.equal((await (await fetch(origin+'/snapshot')).json()).epoch,untouched.epoch);
  await seedForm('43'); await until(()=>b.evaluate('snailApp.runtime.snapshot(1)[19]===43'),'seed restart did not reach second client');
  const firstMarker=await a.evaluate('snailApp.runtime.snapshot(1)[23]');
  await seedForm('43'); assert.equal(await a.evaluate('snailApp.runtime.snapshot(1)[23]'),firstMarker+1);
  await seedForm('1'); await until(()=>b.evaluate('snailApp.runtime.snapshot(1)[19]===1'),'seed reset did not converge');
  console.log('ok - native seed form reaches Scheme, rejects invalid range and restarts both clients exactly once');
  async function place(client, key, x, y) {
    await client.call('Page.bringToFront');
    await client.evaluate('document.querySelector("canvas").focus()');
    await client.call('Input.dispatchKeyEvent', {type:'keyDown',key});
    await client.call('Input.dispatchKeyEvent', {type:'keyUp',key});
    const point = await client.evaluate(`(()=>{const r=document.querySelector('canvas').getBoundingClientRect();return {x:r.left+(${x}+.5)*r.width/24,y:r.top+(${y}+.5)*r.height/16}})()`);
    await client.call('Input.dispatchMouseEvent', {type:'mouseMoved',...point});
    await client.call('Input.dispatchMouseEvent', {type:'mousePressed',button:'left',clickCount:1,...point});
    await client.call('Input.dispatchMouseEvent', {type:'mouseReleased',button:'left',clickCount:1,...point});
    await until(() => client.evaluate('snailApp.pending.length===0'), 'placement not acknowledged');
  }
  await place(a, '1', 12, 6);
  await place(b, '2', 15, 6);
  await place(b, '3', 16, 7);
  for (const client of clients) await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client,visible:false})});
  await pause(250);
  const worlds = await Promise.all(pages.map(p => p.evaluate('snailApp.runtime.snapshot(1)')));
  assert.deepEqual(worlds[0], worlds[1]); assert.equal(colony(worlds[0]).buildings.length, 3);
  assert.equal(colony(worlds[0]).ore, 45);
  const pixels = await a.evaluate(`(async()=>{
    const frame=snailApp.runtime.view(), image=await snailApp.renderer.readPixels(frame.quads,960,640);
    const sample=(x,y)=>Array.from(image.bytes.slice(y*image.bytesPerRow+x*4,y*image.bytesPerRow+x*4+4));
    return {background:sample(10,10),hub:sample(340,340),deposit:sample(500,260)};
  })()`);
  assert.notDeepEqual(pixels.background,pixels.hub); assert.notDeepEqual(pixels.background,pixels.deposit);
  console.log('ok - real keys/pointer place shared projects; WebGPU readback contains the Scheme-authored world');
  const concurrentShaders = await a.evaluate(`(async()=>{
    const source=await (await fetch(${JSON.stringify('/' + original.shader)})).text();
    const results=await Promise.allSettled([snailApp.renderer.prepare('invalid WGSL'),snailApp.renderer.prepare(source)]);
    return results.map(result=>result.status);
  })()`);
  assert.deepEqual(concurrentShaders, ['rejected', 'fulfilled']);
  console.log('ok - concurrent shader candidates keep validation scopes isolated');
  console.log('ok - two browsers execute Scheme and converge on one purchased world');
  assert.equal(await a.evaluate(`(()=>{
    const before=JSON.stringify(snailApp.runtime.snapshot(1)), local=JSON.stringify(snailApp.runtime.snapshot(2));
    const stale=snailApp.runtime.snapshot(1);stale[3]=9999;
    snailApp.acceptSnapshot({revision:snailApp.revision-1,epoch:'old',state:stale});
    return JSON.stringify(snailApp.runtime.snapshot(1))===before && JSON.stringify(snailApp.runtime.snapshot(2))===local;
  })()`),true);
  console.log('ok - stale authoritative snapshots cannot rewind the world or local selection');

  await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client:clients[0],visible:true})});
  await until(async () => {
    const world = colony(await a.evaluate('snailApp.runtime.snapshot(1)'));
    return world.tick >= 800 && world.enemies.length > 0 && world.bots.some(bot => bot.job === 2 && bot.cargo > 0);
  }, 'match did not reach combat with a delivery in transit', 110000);
  await a.evaluate("document.querySelector('[data-handler=suspend][data-args=\"[1]\"]').click()");
  await until(async () => (await Promise.all(pages.map(p => p.evaluate('snailApp.runtime.snapshot(1)[18]')))).every(value => value === 1), 'shared pause not accepted');
  const combatWords = await a.evaluate('snailApp.runtime.snapshot(1)'), combat = colony(combatWords);
  assert.ok(combat.delivered > 0); assert.ok(combat.enemies.length > 0);
  assert.ok(combat.bots.some(bot => bot.job === 2 && bot.cargo > 0));
  await pause(400); assert.deepEqual(await b.evaluate('snailApp.runtime.snapshot(1)'), combatWords);
  for (const client of clients) await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client,visible:false})});
  await pause(200);
  await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client:clients[0],visible:true})});
  await pause(300); assert.deepEqual(await a.evaluate('snailApp.runtime.snapshot(1)'), combatWords);
  await b.evaluate("snailApp.local('suspend',[1])");
  await until(() => b.evaluate('snailApp.pending.length===0'), 'repeated pause not acknowledged');
  assert.equal(await a.evaluate('snailApp.runtime.snapshot(1)[18]'), 1);
  for (const client of clients) await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client,visible:false})});
  await pause(250);
  console.log('ok - shared pause freezes combat and hauling across visibility changes and repeated pause requests');
  await a.evaluate("snailApp.local('pan',[-100,-100]);snailApp.local('choose',[2]);snailApp.local('move',[5,5]);globalThis.realFetch=fetch;globalThis.releaseCommand=undefined;globalThis.fetch=(...args)=>args[0]==='/command'?new Promise(resolve=>{globalThis.releaseCommand=()=>resolve(realFetch(...args))}):realFetch(...args);snailApp.local('fabricate')");
  const before = await a.evaluate('({world:snailApp.runtime.snapshot(1),local:snailApp.runtime.snapshot(2),pending:JSON.stringify(snailApp.pending)})');
  assert.equal(JSON.parse(before.pending).length, 1);
  assert.deepEqual(before.local.slice(4), [-120000,-120000]);
  assert.equal(colony(before.world).paused, 1);
  copyFileSync(join(fixtures, 'compatible.wasm'), join(directory, 'compatible.test.wasm'));
  const compatible = {...original, generation: `qa-compatible-${Date.now()}`, module: 'compatible.test.wasm'}; publish(compatible);
  await until(() => a.evaluate(`snailApp.generation===${JSON.stringify(compatible.generation)}`), 'compatible reload not activated');
  const after = await a.evaluate('({world:snailApp.runtime.snapshot(1),local:snailApp.runtime.snapshot(2),pending:JSON.stringify(snailApp.pending)})');
  assert.deepEqual(after, before);
  await a.evaluate("snailApp.local('choose',[1])");
  assert.equal(await a.evaluate('snailApp.runtime.snapshot(2)[1]'), 2);
  await a.evaluate('globalThis.fetch=realFetch;releaseCommand()');
  await until(() => a.evaluate('snailApp.pending.length===0'), 'preserved request not acknowledged');
  console.log('ok - changed Wasm behavior activates while paused colony, overscrolled camera, cursor, tool and pending envelope survive');
  await until(async () => JSON.stringify(await a.evaluate('snailApp.runtime.snapshot(1)')) === JSON.stringify(await b.evaluate('snailApp.runtime.snapshot(1)')), 'clients did not converge after pending delivery');

  publish({...compatible, generation:`qa-marker-${Date.now()}`, settings:{...compatible.settings,runMarker:24}});
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.includes('incompatible run marker')"), 'changed run marker was not rejected');
  assert.equal(await a.evaluate('snailApp.generation'),compatible.generation);
  publish(compatible);
  console.log('ok - incompatible run-marker offset is rejected before activation');

  writeFileSync(join(directory, 'invalid.test.wgsl'), '@vertex definitely not valid WGSL');
  publish({...compatible, generation: `qa-bad-shader-${Date.now()}`, shader: 'invalid.test.wgsl'});
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.includes('Reload rejected')"), 'invalid shader was not visibly rejected');
  assert.equal(await a.evaluate('snailApp.generation'), compatible.generation);
  assert.ok(await a.evaluate('(async()=>{const f=snailApp.runtime.view();const image=await snailApp.renderer.readPixels(f.quads,960,640);return image.bytes.length>0})()'));
  console.log('ok - invalid WGSL keeps previous code and GPU pipeline alive');

  const badSchema = structuredClone(original); badSchema.generation = `qa-schema-${Date.now()}`; badSchema.applications[0].schema++;
  publish(badSchema);
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.includes('endpoint contract')"), 'incompatible schema was not rejected');
  assert.equal(await a.evaluate('snailApp.generation'), compatible.generation);
  publish({...original, generation:`qa-restored-${Date.now()}`});
  await until(() => a.evaluate("document.querySelector('[data-connection]').textContent.startsWith('LIVE')"), 'valid generation failed to recover');
  if (process.env.SCREENSHOT === '1') {
    const screenshot = await a.call('Page.captureScreenshot', {format:'png'});
    writeFileSync(join(directory, 'browser-check.png'), Buffer.from(screenshot.data, 'base64'));
  }
  const boundaryPixels = await a.evaluate(`(async()=>{
    const f=snailApp.runtime.view(), image=await snailApp.renderer.readPixels(f.quads,960,640);
    const pixel=(x,y)=>Array.from(image.bytes.slice(y*image.bytesPerRow+x*4,y*image.bytesPerRow+x*4+4));
    return {margin:pixel(50,180),edge:pixel(120,180),field:pixel(140,180),mapFrame:pixel(802,20)};
  })()`);
  assert.notDeepEqual(boundaryPixels.margin,boundaryPixels.edge);
  assert.notDeepEqual(boundaryPixels.margin,boundaryPixels.field);
  assert.notDeepEqual(boundaryPixels.margin,boundaryPixels.mapFrame);
  await a.evaluate("snailApp.local('move',[0,0]);snailApp.local('confirm')");
  await until(() => a.evaluate('snailApp.pending.length===0'), 'margin click not acknowledged');
  assert.equal(colony(await a.evaluate('snailApp.runtime.snapshot(1)')).notice, 15);
  await b.evaluate("snailApp.local('suspend',[0])");
  await until(() => b.evaluate('snailApp.pending.length===0'), 'resume not acknowledged');
  await fetch(`${origin}/presence`, {method:'POST',body:JSON.stringify({client:clients[1],visible:true})});
  await until(() => b.evaluate(`snailApp.runtime.snapshot(1)[1]>${combat.tick}`), 'resume did not restart the colony clock');
  console.log('ok - visible map/minimap frames, rejected margin placement and shared Resume');
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
