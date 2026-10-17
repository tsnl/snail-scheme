import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {Authority} from '../../src/application/authority.mjs';
import {openStore} from '../../src/application/sqlite.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/execute.mjs';

const output = resolve(process.argv[2]), fixtures = resolve(process.argv[3]);
const manifest = JSON.parse(readFileSync(join(output, 'manifest.json'))), bytes = readFileSync(join(output, manifest.module));
function fresh() { const r = new ReducerRuntime(); r.replace(r.prepare(bytes, manifest)); r.initialize(1); r.initialize(2); return r; }
function call(r, binding, args = []) { return r.dispatch(1, r.command('match', binding, args)); }
function fixture(name) { return readFileSync(join(fixtures, `${name}.wasm`)); }
let passed = 0;
async function test(name, run) { await run(); console.log(`ok ${++passed} - ${name}`); }

await test('Scheme and Lofi share the shader compiler; composition rejects stage/width errors', () => {
  for (const name of ['shader', 'shader-lofi']) { const i = instantiate(loadWasm(fixture(name))); assert.equal(invokeEntry(i, []), 1); closeInstance(i); }
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
await test('immutable prior snapshots, automatic hauling, placement and pure view', () => {
  const r = fresh(), before = r.stores.get(1); call(r, 'extract', [8, 3]);
  assert.equal(r.snapshot(1)[3], 80); assert.equal(before[3], 110);
  call(r, 'extract', [18, 10]); assert.equal(r.snapshot(1)[3], 80);
  for (let tick = 0; tick < 120; tick++) call(r, 'advance');
  assert.ok(r.snapshot(1)[3] > 80); const snapshot = r.snapshot(1), view = r.view();
  assert.ok(view.quads.length > 40); assert.match(view.label, /ore/); assert.deepEqual(r.snapshot(1), snapshot); r.close();
});
await test('effects are descriptions; local selection does not directly spend world resources', () => {
  const r = fresh(), before = r.snapshot(1);
  const result = r.dispatch(2, r.command('client', 'confirm'));
  assert.deepEqual(r.snapshot(1), before); assert.equal(result.effects.length, 1);
  r.dispatch(1, r.effectCommand(result.effects[0])); assert.equal(r.snapshot(1)[3], 80); r.close();
});
await test('compatible reload preserves authoritative and local state and consumes no tick', () => {
  const r = fresh(); call(r, 'extract', [8, 3]); for (let i = 0; i < 55; i++) call(r, 'advance');
  r.dispatch(2, r.command('client', 'choose', [2])); r.dispatch(2, r.command('client', 'move', [13, 7]));
  const world = r.snapshot(1), local = r.snapshot(2); assert.ok(world[13] > 0);
  r.replace(r.prepare(fixture('compatible'), manifest)); r.initialize(1); r.initialize(2);
  assert.deepEqual(r.snapshot(1), world); assert.deepEqual(r.snapshot(2), local);
  r.dispatch(2, r.command('client', 'choose', [1])); assert.equal(r.snapshot(2)[1], 2);
  call(r, 'advance'); r.close();
});
await test('invalid candidate, incompatible schema and bad snapshot preserve installed code/state', () => {
  const r = fresh(), instance = r.instance, world = r.snapshot(1);
  assert.throws(() => r.prepare(fixture('invalid-candidate'), manifest), /write outside/);
  assert.throws(() => r.prepare(fixture('invalid-view'), manifest), WebAssembly.RuntimeError);
  const incompatible = structuredClone(manifest); incompatible.applications[0].schema++;
  assert.throws(() => r.prepare(bytes, incompatible), /endpoint contract|schema mismatch/);
  const bad = world.slice(); bad[0]++; assert.throws(() => r.restore(1, bad), /schema/);
  assert.equal(r.instance, instance); assert.deepEqual(r.snapshot(1), world); r.close();
});
await test('trap after staged writes/effects rolls back and restores previous compatible module', () => {
  const r = fresh(), world = r.snapshot(1), previous = r.instance;
  r.replace(r.prepare(fixture('trap'), manifest));
  assert.throws(() => call(r, 'extract', [8, 3]), WebAssembly.RuntimeError);
  assert.deepEqual(r.snapshot(1), world); assert.equal(r.instance, previous);
  call(r, 'extract', [8, 3]); assert.equal(r.snapshot(1)[3], 80); r.close();
});
await test('serial concurrent submissions, consumed retries and after-commit observation', async () => {
  const r = fresh(); const authority = new Authority(r, {publish: value => {
    if (value.type === 'snapshot') assert.deepEqual(value.state, r.snapshot(1));
  }});
  const epoch = authority.epoch;
  await Promise.all(Array.from({length: 40}, (_, i) => Promise.resolve().then(() => authority.submit({
    client: 'one', sequence: i + 1, epoch, command: r.command('match', 'advance')}))));
  assert.equal(r.snapshot(1)[1], 40); assert.equal(authority.revision, 40);
  assert.equal(authority.submit({client: 'one', sequence: 40, epoch, command: r.command('match', 'advance')}).duplicate, true);
  assert.equal(r.snapshot(1)[1], 40);
  assert.throws(() => authority.submit({client: 'one', sequence: 40, epoch, command: r.command('match', 'new-run')}), /identity reused/); r.close();
});
await test('failed durable commit publishes neither state nor revision nor effects', () => {
  const r = fresh(), before = r.snapshot(1); let published = 0;
  const authority = new Authority(r, {commit: () => { throw new Error('disk failure'); }, publish: () => published++});
  assert.throws(() => authority.submit({client: 'one', sequence: 1, epoch: authority.epoch,
    command: r.command('match', 'extract', [8, 3])}), /disk failure/);
  assert.deepEqual(r.snapshot(1), before); assert.equal(authority.revision, 0); assert.equal(published, 0); r.close();
});
await test('concurrent purchases from distinct players cannot spend the same resources', async () => {
  const r = fresh(); call(r, 'extract', [8, 3]); const authority = new Authority(r);
  await Promise.all([[7, 7], [7, 4]].map((site, index) => Promise.resolve().then(() => authority.submit({
    client: `player-${index}`, sequence: 1, epoch: authority.epoch, command: r.command('match', 'fortify', site)}))));
  assert.equal(r.snapshot(1)[3], 35); assert.equal(r.snapshot(1)[15], 1); assert.equal(authority.revision, 2); r.close();
});
await test('SQLite restart recovers unacknowledged commit and deduplicates retry', () => {
  const directory = mkdtempSync(join(tmpdir(), 'snail-durable-')), path = join(directory, 'match.sqlite');
  let db = openStore(path), r = fresh(), authority = new Authority(r, {commit: (s, rev) => db.commit(s, rev)});
  const command = {client: 'one', sequence: 1, epoch: authority.epoch, command: r.command('match', 'extract', [8, 3])};
  authority.submit(command); const accepted = authority.snapshot(); db.close(); r.close();
  db = openStore(path); r = fresh(); authority = new Authority(r, {saved: db.load(), commit: (s, rev) => db.commit(s, rev)});
  assert.deepEqual(authority.snapshot(), accepted); assert.equal(authority.submit(command).duplicate, true);
  assert.equal(r.snapshot(1)[3], 80); db.close(); r.close(); rmSync(directory, {recursive: true});
});
await test('unprotected run loses; a fortified economy reaches a successful finale', () => {
  const r = fresh(); for (let i = 0; i < 1200; i++) call(r, 'advance');
  assert.equal(r.snapshot(1)[2], 1); call(r, 'new-run'); call(r, 'extract', [8, 3]);
  const sites = [[7,7],[7,4],[7,10],[11,7],[11,4],[11,10],[15,7],[15,4]];
  let next = 0;
  for (let i = 0; i < 1200 && r.snapshot(1)[2] === 0; i++) {
    const state = r.snapshot(1);
    if (state[3] >= 45 && next < sites.length) call(r, 'fortify', sites[next++]);
    if (state[4] < 65 && state[3] >= 30) call(r, 'repair');
    call(r, 'advance');
  }
  assert.ok([2,3].includes(r.snapshot(1)[2]), `expected victory, got ${r.snapshot(1).slice(0,17)}`); r.close();
});
console.log(`${passed} application integration checks passed`);
