// Tutorial checkpoints execute compiled Scheme and the real snapshot/SQLite path.
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {ReducerRuntime, endpoint} from '../../src/application/runtime.mjs';
import {Authority} from '../../src/application/authority.mjs';
import {openStore} from '../../src/application/sqlite.mjs';
import {snapshotValue} from './snapshots.mjs';

const output = resolve(process.argv[2]);
for (const name of ['counter', 'inventory', 'testing']) {
  const instance = instantiate(loadWasm(readFileSync(join(output, `${name}.wasm`))));
  try { assert.equal(invokeEntry(instance, []), 42); }
  finally { closeInstance(instance); }
  console.log(`ok - ${name} tutorial checkpoint returns 42`);
}

const directory = join(output, 'marker-board/cloud');
const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json')));
const bytes = readFileSync(join(directory, manifest.module));
async function fresh() {
  const runtime = new ReducerRuntime();
  await runtime.replace(runtime.prepare(bytes, manifest));
  await runtime.initialize(1); await runtime.initialize(2);
  return runtime;
}
function position(runtime, owner) {
  const {x, y} = snapshotValue(runtime.snapshot(owner));
  return [x, y];
}
function call(runtime, owner, binding, args = []) {
  return runtime.dispatch(owner === 'match' ? 1 : 2, runtime.command(owner, binding, args));
}

const runtime = await fresh();
try {
  assert.equal(runtime.view().label, 'Marker 0,0 | Cursor 0,0');
  const before = runtime.snapshot(1);
  await call(runtime, 'client', 'move', [3, 2]);
  const sent = await call(runtime, 'client', 'confirm');
  assert.deepEqual(runtime.snapshot(1), before);
  assert.equal(sent.effects.length, 1);
  assert.deepEqual(position(runtime, 2), [3, 2]);
  await runtime.dispatch(1, runtime.effectCommand(sent.effects[0]));
  assert.deepEqual(position(runtime, 1), [3, 2]);
  assert.equal(snapshotValue(before).x, 0);
  console.log('ok - local selection emits a request; explicit delivery moves the shared marker');

  for (const coordinates of [[-1, 0], [8, 0], [0, -1], [0, 6]]) {
    await call(runtime, 'match', 'place', coordinates);
    await call(runtime, 'client', 'move', coordinates);
    assert.deepEqual(position(runtime, 1), [3, 2]);
    assert.deepEqual(position(runtime, 2), [3, 2]);
  }
  await call(runtime, 'match', 'place', [7, 5]);
  assert.deepEqual(position(runtime, 1), [7, 5]);
  const world = runtime.snapshot(1), local = runtime.snapshot(2);
  const view = runtime.view();
  assert.equal(view.label, 'Marker 7,5 | Cursor 3,2');
  assert.deepEqual(view.quads, [[0, 0, 320, 240, 1055781, 255],
    [282, 202, 36, 36, 16753920, 255], [122, 82, 36, 36, 16777215, 90]]);
  assert.deepEqual(runtime.snapshot(1), world);
  await call(runtime, 'match', 'idle');
  assert.deepEqual(runtime.snapshot(1), world);
  await runtime.replace(runtime.prepare(bytes, manifest));
  await runtime.initialize(1); await runtime.initialize(2);
  assert.deepEqual(runtime.snapshot(1), world);
  assert.deepEqual(runtime.snapshot(2), local);
  const incompatible = structuredClone(manifest);
  incompatible.applications[0].schema++;
  assert.throws(() => runtime.prepare(bytes, incompatible), /endpoint contract|schema/);
  assert.deepEqual(runtime.snapshot(1), world);
  const malformed = world.slice(0, -1);
  await assert.rejects(() => runtime.restore(1, malformed), WebAssembly.RuntimeError);
  assert.deepEqual(runtime.snapshot(1), world);
  console.log('ok - bounds, pure view, idle clock, compatible reload and invalid snapshots');

  const reset = await call(runtime, 'client', 'restart');
  await runtime.dispatch(1, runtime.effectCommand(reset.effects[0]));
  assert.deepEqual(position(runtime, 1), [0, 0]);
  assert.deepEqual(position(runtime, 2), [3, 2]);
} finally { await runtime.close(); }

// Reopen an actual SQLite file and restore into a fresh Wasm instance.
const savedDirectory = mkdtempSync(join(tmpdir(), 'marker-board-tutorial-'));
let store, first, restored;
try {
  store = openStore(join(savedDirectory, 'match.sqlite'));
  first = await fresh();
  const authority = new Authority(first, {commit: (snapshot, expected) => store.commit(snapshot, expected),
    resetHandler: endpoint(manifest, 'match', 'clear').id});
  await call(first, 'client', 'move', [5, 4]);
  const request = {client: 'tutorial', sequence: 1, epoch: authority.epoch,
    command: first.command('match', 'place', [6, 1])};
  await authority.submit(request);
  const committed = authority.snapshot();
  await first.close(); first = undefined; store.close(); store = undefined;

  store = openStore(join(savedDirectory, 'match.sqlite'));
  restored = await fresh();
  const restarted = await Authority.open(restored, {saved: store.load(),
    commit: (snapshot, expected) => store.commit(snapshot, expected)});
  assert.deepEqual(restarted.snapshot(), committed);
  assert.deepEqual(position(restored, 1), [6, 1]);
  assert.deepEqual(position(restored, 2), [0, 0]);
  assert.equal((await restarted.submit(request)).duplicate, true);
  assert.equal(restarted.revision, committed.revision);
  console.log('ok - SQLite restart preserves shared position and retry receipt; local cursor starts fresh');
} finally {
  await first?.close(); await restored?.close(); store?.close();
  rmSync(savedDirectory, {recursive: true, force: true});
}
