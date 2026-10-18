// Owns static hosts, optional checkpoint service and a private Chromium profile.
import assert from 'node:assert/strict';
import {colony} from './colony-state.mjs';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdtempSync, cpSync, readFileSync, writeFileSync, readdirSync, existsSync, openSync, closeSync} from 'node:fs';
import {join, resolve, extname} from 'node:path';
import {tmpdir} from 'node:os';
import {packageApplication} from '../../src/browser/build.mjs';

const artifacts = resolve(process.argv[2]), root = resolve(import.meta.dirname, '../..');
const work = mkdtempSync(join(tmpdir(), 'snail-hosting-'));
const soloPort = Number(process.env.TEST_SOLO_PORT ?? 4282), syncedPort = Number(process.env.TEST_SYNCED_PORT ?? 4283);
const servicePort = Number(process.env.TEST_SAVE_PORT ?? 4294);
const debugPort = Number(process.env.TEST_CDP_PORT ?? 9346), devtools = `http://127.0.0.1:${debugPort}`;
const origin = `http://127.0.0.1:${soloPort}`, base = `${origin}/games/siegework/`, synced = `http://127.0.0.1:${syncedPort}`, serviceURL = `http://127.0.0.1:${servicePort}/saves/`;
cpSync(join(artifacts, 'solo'), join(work, 'solo'), {recursive: true});
await packageApplication(root, join(root, 'apps/siegework'), artifacts, {output: join(work, 'synced'), saveServiceURL: serviceURL});
const original = JSON.parse(readFileSync(join(work, 'solo/manifest.json'))), requests = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, message, milliseconds = 20000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) { const value = await check(); if (value) return value; await delay(50); }
  throw new Error(message);
}
async function reachable(url) { try { return (await fetch(url)).ok; } catch { return false; } }
async function requireFreePort(port) {
  const probe = createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(port, '127.0.0.1', resolve); });
  await new Promise(resolve => probe.close(resolve));
}
function child(command, args, env = {}) {
  const log = openSync(join(work, `${command.split('/').pop()}.log`), 'a');
  const process = spawn(command, args, {env: {...globalThis.process.env, ...env}, stdio: ['ignore', log, log]});
  closeSync(log); return process;
}
async function stop(process) {
  if (!process || process.exitCode !== null || process.signalCode !== null) return;
  const ended = once(process, 'exit'); process.kill('SIGTERM'); await ended;
}
function chromium() {
  return child(process.env.CHROMIUM ?? 'chromium', [...(process.env.DISPLAY ? [] : ['--headless=new']),
    '--no-sandbox', '--enable-unsafe-webgpu', '--disable-dev-shm-usage', '--no-first-run', '--window-size=1440,1200',
    '--enable-features=Vulkan', '--use-angle=vulkan', '--use-vulkan=swiftshader', '--use-webgpu-adapter=swiftshader',
    '--disable-vulkan-surface', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${join(work, 'profile')}`, 'about:blank']);
}
function serve(request, response, target = 'solo') {
  const path = new URL(request.url, origin).pathname; requests.push(path);
  if (path === '/fixture.html') { response.end('<!doctype html><title>Storage checks</title>'); return; }
  const relative = path.replace(/^\/(games|moved)\/siegework\//, ''), mounted = relative !== path;
  const file = path === '/test/indexeddb-browser.mjs' ? join(import.meta.dirname, 'indexeddb-browser.mjs')
    : mounted ? resolve(work, target, relative || 'index.html') : '';
  if (!file || !existsSync(file) || (mounted && !file.startsWith(join(work, target) + '/'))) {
    response.writeHead(404); response.end('not found'); return;
  }
  const type = {'.html':'text/html', '.mjs':'text/javascript', '.css':'text/css', '.json':'application/json', '.wasm':'application/wasm', '.wgsl':'text/plain'}[extname(file)];
  response.writeHead(200, {'content-type': type, 'cache-control': 'no-store'}); response.end(readFileSync(file));
}
async function page(url) {
  const target = await (await fetch(`${devtools}/json/new?${encodeURIComponent(url)}`, {method: 'PUT'})).json();
  const socket = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
  await once(socket, 'open');
  socket.onmessage = event => {
    const value = JSON.parse(event.data); if (value.id) { pending.get(value.id)?.(value); pending.delete(value.id); }
  };
  const call = (method, params) => new Promise((resolve, reject) => {
    const id = ++sequence, timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 20000);
    pending.set(id, value => { clearTimeout(timer); value.error ? reject(new Error(value.error.message)) : resolve(value.result); });
    socket.send(JSON.stringify({id, method, params}));
  });
  const evaluate = async expression => {
    const value = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
    if (value.exceptionDetails) throw new Error(value.exceptionDetails.exception?.description ?? value.exceptionDetails.text);
    return value.result.value;
  };
  const result = {evaluate, call, close: async () => { socket.close(); await fetch(`${devtools}/json/close/${target.id}`); }};
  await until(() => evaluate(`location.href === ${JSON.stringify(new URL(url).href)} && document.readyState === 'complete'`), 'page did not load');
  return result;
}
async function ready(page) {
  await until(async () => {
    const state = await page.evaluate("({ready: !!globalThis.snailApp, note: document.querySelector('[data-connection]')?.textContent})");
    if (state.note?.startsWith('Cannot start:')) throw new Error(state.note);
    return state.ready;
  }, 'application did not start');
}
async function gpuReady(page) {
  await until(() => page.evaluate('navigator.gpu.requestAdapter().then(adapter => !!adapter)'),
    'private Chromium WebGPU adapter did not become available');
}
async function paused(page) {
  if((await state(page)).paused===0)await page.evaluate("snailApp.local('pause-menu')");
  await until(async () => await page.evaluate('snailApp.localWork === 0') && (await state(page)).paused === 1, 'pause not committed');
}
const state = async page => colony(await page.evaluate('snailApp.runtime.snapshot(1)'));
async function startColony(page) {
  const before = await state(page); assert.equal(before.started, false); assert.equal(before.tick, 0);
  await page.evaluate("snailApp.local('resume')");
  await page.evaluate("snailApp.local('home')");
  await page.evaluate("snailApp.local('fabricate')");
  await until(async () => (await state(page)).started, 'paid worker order did not start the colony');
  const ordered = await state(page); assert.equal(ordered.ore, before.ore - 25);
  assert.equal(ordered.spent, before.spent + 25); assert.equal(ordered.bots.length, before.bots.length);
  await paused(page);
}
let browser;
const staticServer = createServer((req, res) => serve(req, res));
const syncedServer = createServer((req, res) => serve(req, res, 'synced'));
const saveProcess = child(process.execPath, [join(root, 'src/save/server.mjs'), join(work, 'saves.sqlite')],
  {PORT: String(servicePort), SAVE_ORIGIN: synced});
try {
  const syncedManifest = JSON.parse(readFileSync(join(work, 'synced/manifest.json')));
  assert.deepEqual(readFileSync(join(work, 'solo', original.module)), readFileSync(join(work, 'synced', syncedManifest.module)));
  assert.equal(original.target, 'solo'); assert.equal(syncedManifest.target, 'solo');
  assert.equal(original.saveService, undefined); assert.equal(syncedManifest.saveService.url, serviceURL);
  for (const target of ['solo', 'synced']) {
    for (const file of readdirSync(join(work, target), {recursive: true}).filter(file => file.endsWith('.mjs')))
      assert.doesNotMatch(readFileSync(join(work, target, file), 'utf8'), /(?:from\s+|import\s*)['"]node:/);
    for (const file of ['browser/server.mjs', 'browser/cloud.mjs', 'application/sqlite.mjs', 'application/authority.mjs'])
      assert.equal(existsSync(join(work, target, 'lib', file)), false);
  }
  assert.equal(existsSync(join(work, 'solo/lib/application/remote-saves.mjs')), false);
  assert.equal(existsSync(join(work, 'synced/lib/application/remote-saves.mjs')), true);
  console.log('ok - static packages share exact Wasm; local build omits remote saves and both omit server execution');
  await requireFreePort(debugPort);
  await new Promise(resolve => staticServer.listen(soloPort, '127.0.0.1', resolve));
  await new Promise(resolve => syncedServer.listen(syncedPort, '127.0.0.1', resolve));
  await until(async () => { try { return (await fetch(serviceURL + original.settings.id)).status === 404; } catch { return false; } }, 'save service did not start');
  browser = chromium(); await until(() => reachable(`${devtools}/json/version`), 'private Chromium did not start');
  const storage = await page(`${origin}/fixture.html`);
  const checks = await storage.evaluate(`import('/test/indexeddb-browser.mjs').then(m => m.checkIndexedDB(${JSON.stringify(base)}))`);
  for (const check of checks) console.log(`ok - ${check}`);
  await gpuReady(storage);
  await storage.close();

  const start = requests.length, a = await page(base); await ready(a); await paused(a);
  await startColony(a);
  await a.evaluate("snailApp.local('pan',[1,1])");
  await a.evaluate("snailApp.local('confirm')");
  const local = await a.evaluate('snailApp.runtime.snapshot(2)'), saved = await state(a);
  const savedRevision = await a.evaluate('snailApp.revision');
  const b = await page(base);
  await until(() => b.evaluate("document.querySelector('[data-connection]')?.textContent.includes('open in another tab')"), 'second writer was not rejected');
  assert.equal(await b.evaluate('!!globalThis.snailApp'), false);
  await a.evaluate('snailApp.session.close()'); await a.close();
  await b.call('Page.reload'); await ready(b);
  assert.deepEqual(await state(b), saved); assert.ok(await b.evaluate('snailApp.revision') >= savedRevision);
  assert.notDeepEqual(await b.evaluate('snailApp.runtime.snapshot(2)'), local);
  assert.equal(await b.evaluate("!!document.querySelector('[data-ui-key=resume]')"),true,'saved pause visibly offers Resume');
  console.log('ok - one solo tab owns the save; close releases lock; match/pause restore while local UI restarts');

  await b.evaluate(`(() => {
    const store = snailApp.session.store, commit = store.commit;
    globalThis.saveCalls = 0;
    store.commit = (...args) => {
      saveCalls++; return new Promise(resolve => { globalThis.releaseSave = () => { store.commit = commit; resolve(commit(...args)); }; });
    };
  })()`);
  await until(() => b.evaluate('!!globalThis.releaseSave'), 'clock did not reach deferred persistence');
  const pendingRevision = await b.evaluate('snailApp.revision'); await delay(500);
  assert.deepEqual(await b.evaluate('({calls: saveCalls, revision: snailApp.revision})'), {calls: 1, revision: pendingRevision});
  await b.evaluate('releaseSave(); undefined');
  await until(() => b.evaluate(`snailApp.revision > ${pendingRevision}`), 'deferred save did not complete');
  console.log('ok - slow solo persistence has one pending tick and exposes only the previous commit');

  // Abort only the next write. A successful explicit retry must restart the
  // clock instead of leaving a silently frozen simulation.
  await b.evaluate(`(() => {
    const put = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      const request = put.apply(this, args); IDBObjectStore.prototype.put = put;
      request.addEventListener('success', () => this.transaction.abort()); return request;
    };
  })()`);
  await until(() => b.evaluate('snailApp.session.faulted'), 'failed save did not stop solo clock');
  assert.match(await b.evaluate("document.querySelector('[data-connection]').textContent"), /Retry.*reload/);
  const revision = await b.evaluate('snailApp.revision'); await delay(250);
  assert.equal(await b.evaluate('snailApp.revision'), revision);
  await b.evaluate("snailApp.local('resume')");
  await until(async () => (await state(b)).tick > saved.tick, 'successful retry did not resume clock');
  const cover = await page(`${origin}/fixture.html`); await delay(200);
  assert.equal(await b.evaluate('document.hidden'), true);
  const hiddenTick = (await state(b)).tick; await delay(500); assert.equal((await state(b)).tick, hiddenTick);
  await b.call('Page.bringToFront');
  await until(async () => (await state(b)).tick > hiddenTick, 'visible solo did not resume');
  assert.ok((await state(b)).tick <= hiddenTick + 2); await cover.close();
  await paused(b);
  console.log('ok - aborted solo write stops clock; retry and visibility resume without catch-up');

  // Corrupt one staged result, not the committed save. This exercises the real
  // validator, runtime reproduction capture and browser's diagnostic write.
  const beforeFailure = await b.evaluate(`(() => {
    const runtime = snailApp.runtime, validate = runtime.validateReplacement;
    runtime.validateReplacement = function (instance, transaction) {
      if (transaction.owner === 1 && transaction.next) {
        runtime.validateReplacement = validate; transaction.next[0] = -1;
      }
      return validate.call(runtime, instance, transaction);
    };
    return snailApp.session.local.snapshot();
  })()`);
  await until(() => b.evaluate('snailApp.session.faulted'), 'invalid transition did not stop the browser clock');
  const failure = await until(() => b.evaluate('snailApp.session.store.failure()'), 'browser did not retain the failure reproduction');
  assert.equal(failure.owner, 1); assert.equal(failure.candidate[0], -1);
  assert.match(failure.message, /invalid schema/);
  assert.deepEqual(failure.command, await b.evaluate("snailApp.runtime.command('match','advance')"));
  assert.deepEqual(failure.snapshots.find(snapshot => snapshot.owner === 1).state, beforeFailure.state);
  assert.deepEqual(await b.evaluate('snailApp.session.local.snapshot()'), beforeFailure);
  assert.deepEqual(await b.evaluate('snailApp.session.store.load()'), beforeFailure);
  await b.call('Page.reload'); await ready(b);
  assert.deepEqual(await state(b), colony(beforeFailure.state));
  assert.deepEqual(await b.evaluate('snailApp.session.store.failure()'), failure);
  console.log('ok - rejected browser transition retains its exact reproduction and the prior save through reload');

  const beforeReload = {world: await state(b), local: await b.evaluate('snailApp.runtime.snapshot(2)')};
  await b.evaluate('globalThis.previousInstance = snailApp.runtime.instance');
  writeFileSync(join(work, 'solo/manifest.json'), JSON.stringify({...original, generation: 'compatible-static-reload'}));
  await until(() => b.evaluate("snailApp.generation === 'compatible-static-reload'"), 'static polling did not install compatible assets');
  assert.deepEqual({world: await state(b), local: await b.evaluate('snailApp.runtime.snapshot(2)')}, beforeReload);
  assert.equal(await b.evaluate('snailApp.runtime.instance !== previousInstance'), true);
  writeFileSync(join(work, 'solo/manifest.json'), JSON.stringify({...original, generation: 'incompatible-static-reload', settings: {...original.settings, runMarker: 24}}));
  await until(() => b.evaluate("document.querySelector('[data-connection]').textContent.includes('incompatible solo save contract')"), 'incompatible static update was not rejected');
  assert.equal(await b.evaluate('snailApp.generation'), 'compatible-static-reload');
  writeFileSync(join(work, 'solo/manifest.json'), JSON.stringify(original));
  console.log('ok - static hot reload preserves both owners; incompatible save policy keeps previous code');

  const restartedState = await state(b); await stop(browser); browser = undefined;
  browser = chromium(); await until(() => reachable(`${devtools}/json/version`), 'Chromium restart failed');
  const warmup = await page(`${origin}/fixture.html`); await gpuReady(warmup); await warmup.close();
  const reopened = await page(`${origin}/moved/siegework/`); await ready(reopened);
  assert.deepEqual(await state(reopened), restartedState);
  assert.ok(await reopened.evaluate('snailApp.revision') >= savedRevision);
  const soloRequests = requests.slice(start);
  assert.equal(soloRequests.some(path => /\/(session|command|events|presence|snapshot)$/.test(path)), false);
  assert.equal(soloRequests.some(path => /^\/(lib|manifest\.json|simulation\.|shader\.|style\.css)/.test(path)), false);
  console.log('ok - actual browser restart and moved static subpath reopen the paused save without application-server requests');

  await reopened.evaluate('snailApp.session.close()'); await reopened.close();
  writeFileSync(join(work, 'solo/manifest.json'), JSON.stringify({...original, settings: {...original.settings, runMarker: 24}}));
  const incompatible = await page(base);
  await until(() => incompatible.evaluate("document.querySelector('[data-connection]')?.textContent.includes('Saved game is incompatible')"), 'incompatible startup did not explain retained save');
  writeFileSync(join(work, 'solo/manifest.json'), JSON.stringify(original));
  const departing = await page(`${origin}/fixture.html`);
  await departing.call('Page.enable');
  await departing.call('Page.addScriptToEvaluateOnNewDocument', {source: `
    const request = navigator.locks.request.bind(navigator.locks);
    navigator.locks.request = (name, options, callback) => request(name, options, async lock => {
      if (!lock) return callback(lock);
      globalThis.lockAcquired = true;
      await new Promise(resolve => { globalThis.finishOpen = resolve; }); return callback(lock);
    });
    const requestDevice = GPUAdapter.prototype.requestDevice;
    GPUAdapter.prototype.requestDevice = async function (...args) {
      const device = await requestDevice.apply(this, args);
      device.lost.then(info => { globalThis.closedDevice = info.reason; }); return device;
    };`});
  await departing.call('Page.navigate', {url: base});
  await until(async () => {
    const state = await departing.evaluate("({locked: !!globalThis.lockAcquired, note: document.querySelector('[data-connection]')?.textContent})");
    if (state.note?.startsWith('Cannot start:')) throw new Error(state.note);
    return state.locked;
  }, 'failed startup retained its writer lock');
  await departing.evaluate("dispatchEvent(new PageTransitionEvent('pagehide')); finishOpen(); undefined");
  await until(() => departing.evaluate("globalThis.closedDevice === 'destroyed'"), 'leave-during-open did not close eventual GPU resources');
  assert.equal(await departing.evaluate('!!globalThis.snailApp'), false);
  assert.equal(await departing.evaluate('(async()=> (await navigator.locks.query()).held.length)()'), 0);
  await departing.close(); await incompatible.close();
  const recovered = await page(base); await ready(recovered); assert.deepEqual(await state(recovered), restartedState);
  console.log('ok - incompatible startup and leaving during open close resources, release ownership and retain the saved match');

  const remote = await page(`${synced}/games/siegework/`); await ready(remote); await paused(remote);
  await startColony(remote);
  await until(() => remote.evaluate('!!snailApp.session.saves'), 'online controls missing');
  const remoteState = await state(remote), remoteRevision = await remote.evaluate('snailApp.revision');
  await remote.evaluate('snailApp.session.saves.run(() => snailApp.session.saves.save())');
  assert.match(await remote.evaluate('snailApp.session.saves.status.textContent'), /saved online/);
  const uploaded = await (await fetch(serviceURL + original.settings.id)).json();
  assert.deepEqual(colony(uploaded.snapshot.state), remoteState);
  await remote.evaluate("snailApp.local('resume')");
  await remote.evaluate("snailApp.local('restart-seed',[42])"); await paused(remote);
  assert.notEqual((await state(remote)).seed, remoteState.seed);
  await remote.evaluate('globalThis.confirm = () => true; snailApp.session.saves.run(() => snailApp.session.saves.load())');
  assert.deepEqual(await state(remote), remoteState); assert.ok(await remote.evaluate('snailApp.revision') > remoteRevision);
  const current = await fetch(serviceURL + original.settings.id);
  await fetch(serviceURL + original.settings.id, {method: 'PUT', headers: {'if-match': current.headers.get('etag')}, body: JSON.stringify(uploaded)});
  const knownTag = await remote.evaluate('snailApp.session.saves.etag');
  await remote.evaluate('globalThis.confirm = () => false; snailApp.session.saves.run(() => snailApp.session.saves.load())');
  assert.equal(await remote.evaluate('snailApp.session.saves.etag'), knownTag);
  await remote.evaluate('snailApp.session.saves.run(() => snailApp.session.saves.save())');
  assert.match(await remote.evaluate('snailApp.session.saves.status.textContent'), /online save changed/);
  assert.deepEqual(await state(remote), remoteState);
  const latest = await fetch(serviceURL + original.settings.id);
  await fetch(serviceURL + original.settings.id, {method: 'PUT', headers: {'if-match': latest.headers.get('etag')},
    body: JSON.stringify({...uploaded, snapshot: {revision: 9, state: [99]}})});
  await remote.evaluate('globalThis.confirm = () => true; snailApp.session.saves.run(() => snailApp.session.saves.load())');
  assert.deepEqual(await state(remote), remoteState);
  assert.equal(await remote.evaluate('snailApp.session.saves.etag'), knownTag);
  assert.match(await remote.evaluate('snailApp.session.saves.status.textContent'), /invalid snapshot/i);
  await stop(saveProcess);
  const beforeOffline = await remote.evaluate('snailApp.revision');
  await remote.evaluate("snailApp.local('resume')");
  await until(() => remote.evaluate(`snailApp.revision > ${beforeOffline + 2}`), 'service outage stalled local simulation');
  await paused(remote);
  await remote.evaluate('snailApp.session.saves.run(() => snailApp.session.saves.save())');
  assert.match(await remote.evaluate('snailApp.session.saves.status.textContent'), /Local progress is saved/);
  const offlineState = await state(remote); await remote.call('Page.reload'); await ready(remote);
  assert.deepEqual(await state(remote), offlineState);
  console.log('ok - online checkpoint save/load, stale-write rejection, service outage and local reopen use real browser state');
  await recovered.evaluate('snailApp.session.close()'); await recovered.close();
  await remote.evaluate('snailApp.session.close()'); await remote.close();
  if (original.settings.renderer === 'scene3d') {
    for (const runner of ['persistence-browser.mjs', 'colony-browser.mjs']) {
      const test = child(process.execPath, [join(root, 'tests/draw3d', runner), base, devtools, join(work, 'static-playtest.png')]);
      const [code] = await once(test, 'exit');
      if (code !== 0) throw new Error(`Mouse/GPU test failed: ${runner}; see node.log`);
      console.log(`ok - ${runner}: actual static-game input and GPU checks`);
    }
  }
  console.log(JSON.stringify({work, browser: (await (await fetch(`${devtools}/json/version`)).json()).Browser,
    checks: checks.length + 9 + (original.settings.renderer === 'scene3d' ? 2 : 0)}));
} catch (error) { console.error(`Private test artifacts: ${work}`); throw error; }
finally {
  await stop(browser); await stop(saveProcess);
  staticServer.closeAllConnections(); await new Promise(resolve => staticServer.close(resolve));
  syncedServer.closeAllConnections(); await new Promise(resolve => syncedServer.close(resolve));
}
