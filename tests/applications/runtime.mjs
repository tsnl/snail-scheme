import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, copyFileSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {colony, client, restoreColony} from './colony-state.mjs';
import {checkColony} from './colony.mjs';
import {checkEncounters} from './colony-encounters.mjs';
import {checkLogistics} from './colony-logistics.mjs';
import {checkFocus} from './colony-focus.mjs';
import {checkAsyncRuntime} from './async-runtime.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {Authority} from '../../src/application/authority.mjs';
import {openStore} from '../../src/application/sqlite.mjs';
import {packageApplication} from '../../src/browser/build.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const output = resolve(process.argv[2]), fixtures = resolve(process.argv[3]);
const artifacts = resolve(process.argv[4] ?? output);
const manifest = JSON.parse(readFileSync(join(output, 'manifest.json'))), bytes = readFileSync(join(output, manifest.module));
async function fresh() { const r = new ReducerRuntime(); await r.replace(r.prepare(bytes, manifest)); await r.initialize(1); await r.initialize(2); return r; }
function call(r, binding, args = []) { return r.dispatch(1, r.command('match', binding, args)); }
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
  assert.ok(view.quads.length > 40); assert.match(view.label, /ore/); assert.deepEqual(r.snapshot(1), snapshot); await r.close();
});
await test('effects are descriptions; local selection does not directly spend world resources', async () => {
  const r = await fresh(), before = r.snapshot(1);
  const result = await r.dispatch(2, r.command('client', 'confirm'));
  assert.deepEqual(r.snapshot(1), before); assert.equal(result.effects.length, 1);
  await r.dispatch(1, r.effectCommand(result.effects[0])); assert.equal(colony(r.snapshot(1)).ore, 120); await r.close();
});
await test('compatible reload preserves authoritative and local state and consumes no tick', async () => {
  const r = await fresh(); await call(r, 'extract', [12, 20]); for (let i = 0; i < 700; i++) await call(r, 'advance');
  await r.dispatch(2, r.command('client', 'choose', [2])); await r.dispatch(2, r.command('client', 'move', [13, 7]));
  const world = r.snapshot(1), local = r.snapshot(2); assert.ok(colony(world).delivered > 0); assert.ok(colony(world).enemies.length > 0);
  await r.replace(r.prepare(fixture('compatible'), manifest)); await r.initialize(1); await r.initialize(2);
  assert.deepEqual(r.snapshot(1), world); assert.deepEqual(r.snapshot(2), local);
  await r.dispatch(2, r.command('client', 'choose', [1])); assert.equal(client(r.snapshot(2)).tool, 2);
  await call(r, 'advance'); await r.close();
});
await test('invalid candidate, incompatible schema and bad snapshot preserve installed code/state', async () => {
  const r = await fresh(), instance = r.instance, world = r.snapshot(1);
  assert.throws(() => r.prepare(fixture('invalid-candidate'), manifest), /write outside/);
  assert.throws(() => r.prepare(fixture('invalid-view'), manifest), WebAssembly.RuntimeError);
  const incompatible = structuredClone(manifest); incompatible.applications[0].schema++;
  assert.throws(() => r.prepare(bytes, incompatible), /endpoint contract|schema mismatch/);
  const bad = world.slice(); bad[0]++; await assert.rejects(() => r.restore(1, bad), /schema/);
  assert.equal(r.instance, instance); assert.deepEqual(r.snapshot(1), world); await r.close();
});
await test('derived colony snapshots reject legacy layouts, marker disagreement and invalid values', async () => {
  const r = await fresh(), committed = r.snapshot(1);
  for (const schema of [4,5,6]) {
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
await test('failed and discarded first candidates reserve no state or shape', async () => {
  const r = new ReducerRuntime();
  assert.throws(() => r.prepare(fixture('invalid-candidate'), manifest), /write outside/);
  assert.equal(r.stores.size, 0);
  const abandoned = r.prepare(fixture('invalid-initial'), manifest);
  assert.equal(r.stores.size, 0); r.discard(abandoned);
  const stale = r.prepare(fixture('invalid-initial'), manifest);
  await r.replace(r.prepare(bytes, manifest)); await r.initialize(1); await r.initialize(2);
  const world = r.snapshot(1), instance = r.instance;
  await assert.rejects(() => r.replace(stale), /incompatible state shape/); r.discard(stale);
  assert.deepEqual(r.snapshot(1), world); assert.equal(r.instance, instance); await r.close();
});
await test('candidate installation revalidates state advanced after preparation', async () => {
  const r = await fresh(), candidate = r.prepare(fixture('current-state'), manifest), instance = r.instance;
  await call(r, 'extract', [12, 20]); const world = r.snapshot(1);
  await assert.rejects(() => r.replace(candidate), /incompatible state schema/); r.discard(candidate);
  assert.deepEqual(r.snapshot(1), world); assert.equal(r.instance, instance); await r.close();
});
await test('trap after staged writes/effects rolls back and restores previous compatible module', async () => {
  const r = await fresh(), world = r.snapshot(1), previous = r.instance;
  await r.replace(r.prepare(fixture('trap'), manifest));
  await assert.rejects(() => call(r, 'extract', [12, 20]), WebAssembly.RuntimeError);
  assert.deepEqual(r.snapshot(1), world); assert.equal(r.instance, previous);
  await call(r, 'extract', [12, 20]); assert.equal(colony(r.snapshot(1)).ore, 120); await r.close();
});
await test('an invalid encoded replacement cannot become committed or durable state', async () => {
  const r = await fresh(), world = r.snapshot(1), previous = r.instance; let committed = false;
  await r.replace(r.prepare(fixture('invalid-state'), manifest));
  await assert.rejects(() => r.dispatch(1, r.command('match', 'extract', [12, 20]), {persist: () => committed = true}), WebAssembly.RuntimeError);
  assert.equal(committed, false); assert.deepEqual(r.snapshot(1), world); assert.equal(r.instance, previous); await r.close();
});
await test('invalid transition output fails before durable state or epoch publication', async () => {
  const r=new ReducerRuntime(), contract={version:1,applications:[
    {owner:'match',schema:1,handlers:[{binding:'change',id:'change',slot:0,payload:[]}]},
    {owner:'client',schema:1,handlers:[]} ]};
  await r.replace(r.prepare(fixture('invalid-output'),contract)); await r.initialize(1); await r.initialize(2);
  let writes=0,published=0; const authority=new Authority(r,{runMarker:1,commit:()=>writes++,publish:()=>published++});
  const before=authority.snapshot();
  await assert.rejects(() => authority.submit({client:'one',sequence:1,epoch:authority.epoch,command:r.command('match','change')}),RangeError);
  assert.deepEqual(authority.snapshot(),before); assert.equal(writes,0); assert.equal(published,0);
  assert.deepEqual(authority.clients,{}); await r.close();
});
await test('packaging catches a declared/encoded size mismatch before publishing a manifest', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'snail-preflight-')), root = resolve(import.meta.dirname, '../..');
  for (const name of ['shader.wasm', 'application.syntax.json']) copyFileSync(join(artifacts, name), join(directory, name));
  writeFileSync(join(directory, 'simulation.wasm'), fixture('invalid-initial'));
  writeFileSync(join(directory, 'manifest.json'), 'previous manifest');
  await assert.rejects(() => packageApplication(root, join(root, 'apps/siegework'), directory), /application startup check failed/);
  assert.equal(readFileSync(join(directory, 'manifest.json'), 'utf8'), 'previous manifest');
  rmSync(directory, {recursive: true});
});
await test('serial concurrent submissions, consumed retries and after-commit observation', async () => {
  const r = await fresh(); const authority = new Authority(r, {publish: value => {
    if (value.type === 'snapshot') assert.deepEqual(value.state, r.snapshot(1));
  }});
  const epoch = authority.epoch;
  await Promise.all(Array.from({length: 40}, (_, i) => authority.submit({
    client: 'one', sequence: i + 1, epoch, command: r.command('match', 'advance')})));
  assert.equal(colony(r.snapshot(1)).tick, 40); assert.equal(authority.revision, 40);
  assert.equal((await authority.submit({client: 'one', sequence: 40, epoch, command: r.command('match', 'advance')})).duplicate, true);
  assert.equal(colony(r.snapshot(1)).tick, 40);
  await assert.rejects(() => authority.submit({client: 'one', sequence: 40, epoch, command: r.command('match', 'new-run')}), /identity reused/); await r.close();
});
await test('failed durable commit publishes neither state nor revision nor effects', async () => {
  const r = await fresh(), before = r.snapshot(1); let published = 0;
  const authority = new Authority(r, {commit: () => { throw new Error('disk failure'); }, publish: () => published++});
  await assert.rejects(() => authority.submit({client: 'one', sequence: 1, epoch: authority.epoch,
    command: r.command('match', 'extract', [12, 20])}), /disk failure/);
  assert.deepEqual(r.snapshot(1), before); assert.equal(authority.revision, 0); assert.equal(published, 0); await r.close();
});
await test('observer failure after commit retains the receipt and never repeats the handler', async () => {
  const r = await fresh(); let published = 0;
  const authority = new Authority(r, {publish: () => { published++; throw new Error('observer unavailable'); }});
  const command = {client: 'one', sequence: 1, epoch: authority.epoch, command: r.command('match', 'extract', [12, 20])};
  await assert.rejects(() => authority.submit(command), /observer unavailable/);
  assert.equal(authority.revision, 1); assert.equal(colony(r.snapshot(1)).ore, 120);
  const retry = await authority.submit(command);
  assert.equal(retry.duplicate, true); assert.equal(retry.receipt.revision, 1);
  assert.equal(published, 1); assert.equal(colony(r.snapshot(1)).ore, 120); await r.close();
});
await test('concurrent purchases from distinct players cannot spend the same resources', async () => {
  const r = await fresh(); await call(r, 'extract', [12, 20]); await call(r, 'observe', [10, 16]); await call(r, 'observe', [14, 20]);
  const authority = new Authority(r);
  await Promise.all([[10,20], [10,24]].map((site, index) => authority.submit({
    client: `player-${index}`, sequence: 1, epoch: authority.epoch, command: r.command('match', 'fortify', site)})));
  const world = colony(r.snapshot(1));
  assert.equal(world.ore, 20); assert.equal(world.buildings.filter(b => b.kind === 2).length, 1);
  assert.equal(authority.revision, 2); await r.close();
});
await test('SQLite restart recovers unacknowledged commit and deduplicates retry', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'snail-durable-')), path = join(directory, 'match.sqlite');
  let db = openStore(path), r = await fresh(), authority = new Authority(r, {commit: (s, rev) => db.commit(s, rev)});
  await authority.submit({client:'one', sequence:1, epoch:authority.epoch, command:r.command('match','pause-colony',[1])});
  const command = {client: 'one', sequence: 2, epoch: authority.epoch, command: r.command('match', 'extract', [12, 20])};
  await authority.submit(command); const accepted = authority.snapshot(); db.close(); await r.close();
  db = openStore(path); r = await fresh(); authority = await Authority.open(r, {saved: db.load(), commit: (s, rev) => db.commit(s, rev)});
  assert.deepEqual(authority.snapshot(), accepted); assert.equal((await authority.submit(command)).duplicate, true);
  assert.equal(colony(r.snapshot(1)).ore, 120); assert.equal(colony(r.snapshot(1)).paused, 1);
  await call(r, 'advance'); assert.deepEqual(authority.snapshot(), accepted);
  db.close(); await r.close(); rmSync(directory, {recursive: true});
});
await test('unprotected run loses; a fortified colony reaches a successful finale without kill income', async () => {
  const r = await fresh(); for (let i = 0; i < 4800; i++) await call(r, 'advance');
  assert.equal(colony(r.snapshot(1)).outcome, 1); await call(r, 'new-run-seed', [1]); await call(r, 'extract', [12,20]);
  await call(r, 'fortify', [15,20]); await call(r, 'observe', [16,21]);
  const sites = [[16,22],[15,24],[12,24],[16,18],[13,17],[18,20],[18,22],[19,18]];
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
  assert.ok(sawKill); assert.ok([2,3].includes(colony(r.snapshot(1)).outcome)); await r.close();
});
await test('Scheme run markers atomically bind accepted restarts, epochs and retry receipts', async () => {
  const r = await fresh(); let durable, rejectCommit = false;
  const authority = new Authority(r, {runMarker:1, commit:snapshot => {
    if (rejectCommit) throw new Error('disk unavailable'); durable=structuredClone(snapshot);
  }});
  const envelope = (client, sequence, command, epoch=authority.epoch) => ({client,sequence,epoch,command});
  const oldEpoch=authority.epoch, first=envelope('a',1,r.command('match','new-run-seed',[1]));
  await authority.submit(first); assert.notEqual(authority.epoch,oldEpoch); assert.equal(colony(r.snapshot(1)).runMarker,1);
  const accepted=authority.snapshot(), receipt=structuredClone(authority.clients.a);
  assert.equal((await authority.submit(first)).duplicate,true); assert.deepEqual(authority.snapshot(),accepted);
  assert.deepEqual(authority.clients.a,receipt);
  await assert.rejects(() => authority.submit(envelope('b',1,r.command('match','extract',[12,20]),oldEpoch)),/stale match epoch/);
  const beforeInvalid=authority.snapshot(); await authority.submit(envelope('a',2,r.command('match','new-run-seed',[65536])));
  assert.equal(authority.epoch,beforeInvalid.epoch); const unchanged=colony(beforeInvalid.state); unchanged.notice=16;
  assert.deepEqual(colony(r.snapshot(1)),unchanged);
  const beforeFailure=authority.snapshot(), oldClients=structuredClone(authority.clients), oldDurable=durable;
  const next=envelope('a',3,r.command('match','new-run-seed',[1])); rejectCommit=true;
  await assert.rejects(() => authority.submit(next),/disk unavailable/); assert.deepEqual(authority.snapshot(),beforeFailure);
  assert.deepEqual(authority.clients,oldClients); assert.deepEqual(durable,oldDurable);
  rejectCommit=false; await authority.submit(next); assert.notEqual(authority.epoch,beforeFailure.epoch);
  const copy=await fresh(), recovered=await Authority.open(copy,{saved:durable,runMarker:1});
  assert.deepEqual(recovered.snapshot(),authority.snapshot()); assert.equal((await recovered.submit(next)).duplicate,true);
  for (const runMarker of [0,-1,1.5,r.snapshot(1).length]) assert.throws(()=>new Authority(r,{runMarker}),/run marker/);
  await r.close(); await copy.close();
});
await checkColony(test, fresh, call);
await checkEncounters(test, fresh, call);
await checkLogistics(test, fresh, call);
await checkFocus(test, fresh, call);
await checkAsyncRuntime(test, fixture);
console.log(`${passed} application integration checks passed`);
