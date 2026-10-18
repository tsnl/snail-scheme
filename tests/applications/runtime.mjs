import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, copyFileSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {colony, client, restoreColony, fixtureCall, at} from './colony-state.mjs';
import {checkColony} from './colony.mjs';
import {checkEncounters} from './colony-encounters.mjs';
import {checkLogistics} from './colony-logistics.mjs';
import {checkFocus} from './colony-focus.mjs';
import {checkWorld} from './colony-world.mjs';
import {checkVisibility} from './colony-visibility.mjs';
import {checkHub} from './colony-hub.mjs';
import {checkConstructionOrders} from './colony-construction.mjs';
import {checkDirectBuild} from './colony-direct-build.mjs';
import {checkCrowd} from './colony-crowd.mjs';
import {checkRetaliation} from './colony-retaliation.mjs';
import {checkDigging} from './colony-digging.mjs';
import {checkRanks} from './colony-ranks.mjs';
import {checkCarts} from './colony-carts.mjs';
import {checkTransport} from './colony-transport.mjs';
import {checkAsyncRuntime} from './async-runtime.mjs';
import {checkSnapshotCache} from './snapshot-cache.mjs';
import {checkBrowserEffects} from './browser-effects.mjs';
import {checkColonyMenus} from './colony-menu.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {packageApplication} from '../../src/browser/build.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const output = resolve(process.argv[2]), fixtures = resolve(process.argv[3]);
const artifacts = resolve(process.argv[4] ?? output);
const manifest = JSON.parse(readFileSync(join(output, 'manifest.json'))), bytes = readFileSync(join(output, manifest.module));
async function fresh() { const r = new ReducerRuntime(); await r.replace(r.prepare(bytes, manifest)); await r.initialize(1); await r.initialize(2); return r; }
const call = fixtureCall;
function fixture(name) { return readFileSync(join(fixtures, `${name}.wasm`)); }
let passed = 0;
async function test(name, run) { await run(); console.log(`ok ${++passed} - ${name}`); }

await test('Scheme and Lofi share the shader compiler; composition rejects stage/width errors', () => {
  for (const name of ['shader', 'shader-lofi']) { const i = instantiate(loadWasm(fixture(name))); assert.equal(invokeEntry(i, []), 1); closeInstance(i); }
});
await test('seeded terrain keeps legacy geography and reachable reproducible alternatives', () => {
  const i = instantiate(loadWasm(fixture('terrain'))); assert.equal(invokeEntry(i, []), 1); closeInstance(i);
});
await test('retained immutable Scheme records remain unchanged', () => {
  for (const [name, expected] of [['immutable', 1], ['state', 42]]) {
    const i = instantiate(loadWasm(fixture(name))); assert.equal(invokeEntry(i, []), expected); closeInstance(i);
  }
});
await test('Scheme and Lofi run the same typed lexical application API', () => {
  for (const name of ['counter', 'counter-lofi']) {
    const i = instantiate(loadWasm(fixture(name))); assert.equal(invokeEntry(i, []), 42); closeInstance(i);
  }
});
await test('direct Scheme handler tests initialize state and inspect effect variants', () => {
  const i = instantiate(loadWasm(fixture('testing')));
  assert.equal(invokeEntry(i, []), 42); closeInstance(i);
});
await test('immutable prior snapshots, automatic hauling, placement and pure view', async () => {
  const r = await fresh(), before = r.stores.get(1); await call(r, 'extract', [12, 20]);
  assert.equal(colony(r.snapshot(1)).ore, 120); assert.equal(colony(before).ore, 160);
  await call(r, 'extract', [18, 10]); assert.equal(colony(r.snapshot(1)).ore, 120);
  for (let tick = 0; tick < 120; tick++) await call(r, 'advance');
  assert.ok(colony(r.snapshot(1)).ore > 120); const snapshot = r.snapshot(1), view = r.view();
  assert.ok(view.scene.batches.some(batch => batch.vertices.length > 100)); assert.match(view.label, /ORE/); assert.deepEqual(r.snapshot(1), snapshot); await r.close();
});
await test('a selected deposit spends only on construction and unlocks after reply and settlement', async () => {
  const r = await fresh(), before = r.snapshot(1), local=(name,args=[])=>r.dispatch(2,r.command('client',name,args));
  assert.deepEqual((await local('confirm')).effects, []); assert.equal(client(r.snapshot(2)).chooser, true);
  assert.deepEqual(r.snapshot(1), before); assert.equal(colony(r.snapshot(1)).started,false);
  const selected=client(r.snapshot(2)),cell=selected.cursorX+selected.cursorY*384;
  const result=await local('confirm');assert.deepEqual(r.snapshot(1),before);
  assert.deepEqual(result.effects,[{kind:'send',owner:1,command:r.command('match','build-cell',[1,cell])},
    {kind:'send',owner:2,command:r.command('client','build-settled',[cell])}]);
  assert.equal(client(r.snapshot(2)).buildKind,1);
  const committed=await r.dispatch(1,r.effectCommand(result.effects[0]));assert.equal(colony(r.snapshot(1)).ore,120);
  assert.deepEqual(committed.effects,[{kind:'send',owner:2,command:r.command('client','build-result',[cell,1])}]);
  await r.dispatch(2,r.effectCommand(committed.effects[0]));assert.equal(client(r.snapshot(2)).buildKind,1);
  await r.dispatch(2,r.effectCommand(result.effects[1]));
  assert.equal(client(r.snapshot(2)).buildKind,0);assert.equal(client(r.snapshot(2)).chooser,false);await r.close();
});
await test('worker hiring requires the selected hub and retains its dialog for another paid order',async()=>{
  const r=await fresh(),local=(name,args=[])=>r.dispatch(2,r.command('client',name,args));
  assert.deepEqual((await local('fabricate')).effects,[]); await local('confirm');
  assert.deepEqual((await local('fabricate')).effects,[]); assert.equal(colony(r.snapshot(1)).ore,160);
  await local('nudge',[-4,2]); await local('confirm');
  for(const expected of [135,110]) {
    const requested=await local('fabricate'); assert.equal(requested.effects.length,1);
    assert.equal(client(r.snapshot(2)).chooser,true); await r.dispatch(1,r.effectCommand(requested.effects[0]));
    assert.equal(colony(r.snapshot(1)).ore,expected); assert.equal(colony(r.snapshot(1)).bots.length,3);
  }
  assert.equal(colony(r.snapshot(1)).bots.filter(bot=>bot.job===6).length,2); await r.close();
});
await test('dismiss closes a selected project while explicit cancellation owns its refund',async()=>{
  const r=await fresh(),local=(name,args=[])=>r.dispatch(2,r.command('client',name,args));
  await local('nudge',[-2,2]);await local('confirm');
  const selected=await local('choose',[1]),committed=await r.dispatch(1,r.effectCommand(selected.effects[0]));
  await r.dispatch(2,r.effectCommand(committed.effects[0]));await r.dispatch(2,r.effectCommand(selected.effects[1]));
  assert.equal(colony(r.snapshot(1)).ore,135);
  await local('confirm'); assert.deepEqual((await local('dismiss')).effects,[]);
  assert.equal(client(r.snapshot(2)).chooser,false); assert.equal(colony(r.snapshot(1)).buildings.length,1);
  await local('confirm'); const cancelled=await local('cancel'); assert.equal(cancelled.effects.length,1);
  assert.equal(colony(r.snapshot(1)).ore,135); await r.dispatch(1,r.effectCommand(cancelled.effects[0]));
  assert.equal(colony(r.snapshot(1)).ore,160); assert.equal(colony(r.snapshot(1)).buildings.length,0); await r.close();
});
await test('pause menu stops time; restart cancellation stays paused and Resume unpauses',async()=>{
  const r=await fresh(),local=(name,args=[])=>r.dispatch(2,r.command('client',name,args));
  const apply=async result=>{for(const effect of result.effects){
    await apply(await r.dispatch(effect.owner,r.effectCommand(effect)));
    if(effect.owner===1&&effect.command.handler===r.command('match','new-run').handler)await local('reset-presentation');
  }};
  await call(r,'fabricate-worker');await apply(await local('pause-menu'));assert.equal(client(r.snapshot(2)).dialog,1);
  const paused=r.snapshot(1);for(let i=0;i<10;i++)await call(r,'advance');assert.deepEqual(r.snapshot(1),paused);
  await apply(await local('restart'));assert.equal(client(r.snapshot(2)).dialog,2);
  assert.deepEqual((await local('dismiss-restart')).effects,[]);assert.equal(client(r.snapshot(2)).dialog,1);assert.equal(colony(r.snapshot(1)).paused,1);
  await apply(await local('resume'));assert.equal(colony(r.snapshot(1)).paused,0);
  await call(r,'pause-colony',[1]);await local('reset-presentation');assert.equal(client(r.snapshot(2)).dialog,1);
  await apply(await local('resume'));assert.equal(colony(r.snapshot(1)).paused,0);
  const marker=colony(r.snapshot(1)).runMarker;await apply(await local('pause-menu'));await apply(await local('restart'));await apply(await local('accept-restart'));
  const restarted=colony(r.snapshot(1));assert.equal(restarted.runMarker,marker+1);assert.equal(restarted.started,false);
  assert.equal(restarted.tick,0);assert.equal(restarted.ore,160);assert.equal(restarted.paused,0);assert.equal(client(r.snapshot(2)).dialog,0);await r.close();
});
await test('compatible 3D reload preserves both models without consuming a tick', async () => {
  const r = await fresh(); await call(r, 'extract', [12, 20]); for (let i = 0; i < 700; i++) await call(r, 'advance');
  await r.dispatch(2, r.command('client', 'pan', [1, 1]));
  const world = r.snapshot(1), local = r.snapshot(2), old = r.instance;
  await r.replace(r.prepare(bytes, manifest)); await r.initialize(1); await r.initialize(2);
  assert.notEqual(r.instance, old); assert.deepEqual(r.snapshot(1), world); assert.deepEqual(r.snapshot(2), local);
  const incompatible = structuredClone(manifest); incompatible.applications[0].schema++;
  assert.throws(() => r.prepare(bytes, incompatible), /endpoint contract|schema mismatch/);
  const bad = world.slice(); bad[0]++; await assert.rejects(() => r.restore(1, bad), /schema/); await r.close();
});
await test('derived colony snapshots reject legacy layouts, marker disagreement and invalid values', async () => {
  const r = await fresh(), committed = r.snapshot(1);
  for (const schema of [4,5,6,7,8,9]) {
    const legacy = Array(schema === 4 ? 6144 : 10240).fill(0); legacy[0] = schema;
    await assert.rejects(() => r.restore(1, legacy), /schema/);
  }
  const mismatched = committed.slice(); mismatched[1]++;
  await assert.rejects(() => r.restore(1, mismatched), WebAssembly.RuntimeError);
  for (const change of [world => world.tick = -1, world => world.seed = 0,
    world => world.bots[0].hp = 0, world => world.surveys[0].radius = 11]) {
    const world = colony(committed); change(world);
    await assert.rejects(() => restoreColony(r, world), WebAssembly.RuntimeError);
  }
  assert.deepEqual(r.snapshot(1), committed); await r.close();
});
await test('invalid transition output fails before durable state or revision publication', async () => {
  const r=new ReducerRuntime(), contract={version:1,applications:[
    {owner:'match',schema:1,handlers:[{binding:'change',id:'change',slot:0,payload:[]}]},
    {owner:'client',schema:1,handlers:[]} ]};
  await r.replace(r.prepare(fixture('invalid-output'),contract)); await r.initialize(1); await r.initialize(2);
  let writes=0,published=0; const local=new LocalState(r,{commit:()=>writes++,publish:()=>published++});
  const before=local.snapshot(), command=r.command('match','change'); let failure;
  await assert.rejects(() => local.submit(command),error=>{failure=error;return error instanceof RangeError;});
  assert.deepEqual(local.snapshot(),before); assert.equal(writes,0); assert.equal(published,0);
  assert.equal(failure.reproduction,r.lastFailure); assert.deepEqual(r.lastFailure.command,command);
  assert.equal(r.lastFailure.owner,1); assert.match(r.lastFailure.message,/code point/i);
  assert.deepEqual(r.lastFailure.snapshots.find(value=>value.owner===1).state,before.state);
  assert.deepEqual(r.lastFailure.candidate,[1,1]);
  await r.close();
});
await test('packaging rejects invalid simulation bytes before publishing a manifest', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'snail-preflight-')), root = resolve(import.meta.dirname, '../..');
  for (const name of ['shader.wasm', 'application.syntax.json']) copyFileSync(join(artifacts, name), join(directory, name));
  writeFileSync(join(directory, 'simulation.wasm'), new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]));
  writeFileSync(join(directory, 'manifest.json'), 'previous manifest');
  await assert.rejects(() => packageApplication(root, join(root, 'apps/siegework'), directory), /application startup check failed/);
  assert.equal(readFileSync(join(directory, 'manifest.json'), 'utf8'), 'previous manifest');
  rmSync(directory, {recursive: true});
});
await test('local submissions serialize, publish only durable state, and resume from old browser saves', async () => {
  const r = await fresh(); let durable, published = 0;
  await call(r, 'fabricate-worker');
  const local = new LocalState(r, {commit: (snapshot, expected) => {
    assert.equal(snapshot.revision, expected + 1); durable = structuredClone(snapshot);
  }, publish: () => { assert.deepEqual(local.snapshot(), durable); published++; }});
  await Promise.all(Array.from({length: 40}, () => local.submit(r.command('match', 'advance'))));
  assert.equal(colony(r.snapshot(1)).tick, 40); assert.equal(local.revision, 40); assert.equal(published, 40);
  const copy = await fresh(), restored = await LocalState.open(copy, {saved: {...durable, epoch: 'legacy', clients: {solo: {sequence: 40}}}});
  assert.deepEqual(restored.snapshot(), local.snapshot());
  await restored.submit(copy.command('match', 'pause-colony', [1])); assert.equal(restored.revision, 41);
  assert.equal(colony(copy.snapshot(1)).paused, 1); await r.close(); await copy.close();
});
await test('failed local persistence leaves state, revision and effects unchanged', async () => {
  const r = await fresh(), before = r.snapshot(1); let published = 0;
  const local = new LocalState(r, {commit: () => { throw new Error('disk failure'); }, publish: () => published++});
  const point=at(colony(before),12,20);
  await assert.rejects(() => local.submit(r.command('match', 'extract', [point.x,point.y])), /disk failure/);
  assert.deepEqual(r.snapshot(1), before); assert.equal(local.revision, 0); assert.equal(published, 0); await r.close();
});
await test('unprotected run loses; supplied defenders kill threats without generating ore', async () => {
  const r = await fresh(); await call(r,'fabricate-worker'); for (let i = 0; i < 4800; i++) await call(r, 'advance');
  assert.equal(colony(r.snapshot(1)).outcome, 1); await call(r, 'new-run-seed', [1]);
  const supplied = colony(r.snapshot(1)); supplied.produced += 500; supplied.delivered += 500; supplied.ore += 500;
  await restoreColony(r, supplied); await call(r, 'extract', [12,20]);
  await call(r, 'fortify', [15,20]); await call(r, 'observe', [16,21]);
  const sites = [[12,22],[12,24],[10,24],[10,22],[9,24],[8,25],[7,24],[10,20],[11,21]];
  let next = 0, sawKill = false;
  for (let i = 0; i < 4800 && colony(r.snapshot(1)).outcome === 0; i++) {
    const before = colony(r.snapshot(1));
    if (before.ore >= 50 && next < sites.length) {
      await call(r, 'fortify', sites[next]); if (colony(r.snapshot(1)).notice === 10) next++;
    }
    await call(r, 'advance');
    const after = colony(r.snapshot(1));
    assert.equal(after.ore, 160 + after.delivered + after.localSpent - after.spent, 'ore comes only from deliveries');
    if (after.kills > before.kills) sawKill = true;
  }
  assert.ok(sawKill); await r.close();
});
await checkColony(test, fresh, call);
await checkEncounters(test, fresh, call);
await checkLogistics(test, fresh, call);
await checkFocus(test, fresh, call);
await checkWorld(test, fresh);
await checkVisibility(test, fresh);
await checkHub(test, fresh, bytes);
await checkConstructionOrders(test, fresh);
await checkDirectBuild(test, fresh);
await checkCrowd(test, fresh, bytes);
await checkRetaliation(test, fresh, bytes);
await checkDigging(test, fresh);
await checkRanks(test, fresh);
await checkCarts(test, fresh);
await checkTransport(test, fresh);
await checkAsyncRuntime(test, fixture);
await checkSnapshotCache(test, fixture);
await checkBrowserEffects(test, fixture);
await checkColonyMenus(test, fresh);
console.log(`${passed} application integration checks passed`);
