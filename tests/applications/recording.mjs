// Packed retention and real Wasm commit/replay isolation. No alternative game.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {RunRecording, encodeChange, applyChange} from '../../src/application/recording.mjs';
import {SnapshotPlayback} from '../../src/application/playback.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {MAP_WIDTH,colony, colonyWords, at} from './colony-state.mjs';
import {analyzeRecording} from '../../apps/siegework/analyze-recording.mjs';

let count = 0;
async function test(name, run) { await run(); console.log(`ok ${++count} - ${name}`); }
const syntheticManifest = {version: 1, generation: 'test', settings: {id: 'recording-test', runMarker: 1}, applications: [
  {owner: 'match', schema: 11, handlers: [{id: 'advance', binding: 'advance', slot: 0, payload: []}]},
  {owner: 'client', schema: 1, handlers: []}]};
function synthetic(words = 25000, options) {
  const bank = new Int32Array(words); bank[0] = 11;
  const runtime = {manifest: syntheticManifest, stores: new Map([[1, bank]])};
  return {runtime, recording: RunRecording.start(runtime, options)};
}
function capture(runtime, recording, words) {
  runtime.stores.set(1, words);
  recording.capture(runtime, {kind: 'commit', command: {handler: 'advance', args: []}, effects: []});
}
async function roundTrip(recording) { return RunRecording.import(await recording.exportBlob().arrayBuffer()); }

await test('packed sparse and shifted word changes reconstruct exactly, including shrink and no-op', () => {
  let random = 17;
  const next = n => { random = (Math.imul(random, 1664525) + 1013904223) >>> 0; return random % n; };
  for (let trial = 0; trial < 1000; trial++) {
    const before = Int32Array.from({length: 1 + next(300)}, () => next(2000) - 1000);
    const after = Array.from(before);
    for (let edit = 0; edit < 5; edit++) after[next(after.length)] = next(10000);
    if (trial % 2) after.splice(next(after.length), next(8), 20, -34, 50);
    assert.deepEqual(applyChange(before, encodeChange(before, Int32Array.from(after))), Int32Array.from(after));
    assert.deepEqual(applyChange(before, encodeChange(before, before)), before);
  }
  assert.throws(() => applyChange(new Int32Array(4), {encoding: 2, data: Int32Array.of(4, 2, 8, 2, 9)}));
  assert.throws(() => applyChange(new Int32Array(4), {encoding: 1, data: Int32Array.of(2147483647, 0, 0)}));
});
await test('chunk eviction preserves a reconstructable tail under both byte and entry limits', async () => {
  const {runtime, recording} = synthetic(80, {bytes: 2000, entries: 12});
  for (let i = 1; i <= 80; i++) { const words = runtime.stores.get(1).slice(); words[2] = i; capture(runtime, recording, words); }
  assert.ok(recording.dropped > 0); assert.ok(recording.length <= 12); assert.ok(recording.bytes <= 2000);
  assert.equal(recording.snapshot(recording.last)[2], 80);
  const imported = await roundTrip(recording);
  for (let i = imported.first; i <= imported.last; i++) assert.deepEqual(imported.snapshot(i), recording.snapshot(i));
  assert.equal(imported.dropped, recording.dropped); assert.equal(imported.enabled, false);
});
await test('dump framing rejects truncation, trailing data and oversized decoded patches', async () => {
  const {runtime, recording} = synthetic(40); const words = runtime.stores.get(1).slice(); words[3] = 7; capture(runtime, recording, words);
  const dump = new Uint8Array(await recording.exportBlob().arrayBuffer());
  for (const length of [0, 11, 20, dump.length - 1]) assert.throws(() => RunRecording.import(dump.slice(0, length).buffer));
  const trailing = new Uint8Array(dump.length + 1); trailing.set(dump); assert.throws(() => RunRecording.import(trailing.buffer));
  const corrupt = dump.slice(), view = new DataView(corrupt.buffer), first = 12 + view.getUint32(8, true);
  view.setUint32(first + 4, 0xffffffff, true); assert.throws(() => RunRecording.import(corrupt.buffer));
});
await test('stop/resume marks a new checkpoint and exported Blobs cannot mutate retained history', async () => {
  const {runtime, recording} = synthetic(40); recording.stop();
  const words = runtime.stores.get(1).slice(); words[2] = 99; capture(runtime, recording, words);
  assert.equal(recording.length, 1); recording.resume(runtime);
  assert.equal(recording.entry(recording.last).kind, 'checkpoint'); assert.equal(recording.snapshot(recording.last)[2], 99);
  const blob = recording.exportBlob(), exported = new Uint8Array(await blob.arrayBuffer()); exported.fill(0);
  assert.equal(recording.snapshot(recording.last)[2], 99);
  assert.equal(RunRecording.import(await blob.arrayBuffer()).snapshot(recording.last)[2], 99);
});
await test('ten minutes of 100KB packed World changes stay bounded; account actual buffer bytes', () => {
  const {runtime, recording} = synthetic(), times = [];
  for (let tick = 1; tick <= 6000; tick++) {
    const words = runtime.stores.get(1).slice(); words[2] = tick;
    for (let i = 100; i < words.length; i += 101) words[i] = tick;
    const start = performance.now(); capture(runtime, recording, words); times.push(performance.now() - start);
  }
  assert.equal(recording.dropped, 0); assert.equal(recording.length, 6001);
  const stats = recording.stats(); assert.equal(stats.wordBytes + stats.metadataBytes + stats.framingBytes, recording.bytes);
  times.sort((a, b) => a - b);
  console.log(JSON.stringify({fixture: '100KB, 249 changed words per tick, 6000 ticks', ...stats,
    captureMedianMs: times[3000], captureP95Ms: times[5700], captureMaxMs: times.at(-1)}));
});

if (process.argv[2]) {
  const directory = resolve(process.argv[2]), manifest = JSON.parse(readFileSync(join(directory, 'manifest.json')));
  const bytes = readFileSync(join(directory, manifest.module));
  async function fresh() {
    const runtime = new ReducerRuntime(); await runtime.replace(runtime.prepare(bytes, manifest));
    await runtime.initialize(1); await runtime.initialize(2); return runtime;
  }
  await test('idle clock polls preserve a small real-Wasm history and keep durable revision gaps', async () => {
    const runtime = await fresh(), local = new LocalState(runtime);
    const recording = runtime.recording = RunRecording.start(runtime, {entries: 8, revision: () => local.revision});
    const order = (binding, args = []) => local.submit(runtime.command('match', binding, args));
    const idle = async label => {
      const stats = recording.stats(), bank = runtime.stores.get(1), revision = local.revision;
      for (let i = 0; i < 64; i++) await order(manifest.settings.tick);
      assert.equal(runtime.stores.get(1), bank, `${label} polls leave the encoded World unchanged`);
      assert.deepEqual(recording.stats(), stats, `${label} polls must not consume or evict recording entries`);
      assert.equal(local.revision, revision + 64, 'skipping capture does not change durable publication');
    };
    await idle('unstarted');
    await order('new-run-seed', [1]); const point = at(colony(runtime.snapshot(1)), 12, 20);
    await order('extract', [point.x, point.y]); await order(manifest.settings.tick); await order(manifest.settings.tick);
    assert.equal(colony(runtime.snapshot(1)).tick, 2, 'active simulation ticks remain recorded');
    await order('pause-colony', [1]); await idle('paused');
    const finished = colony(runtime.snapshot(1)); Object.assign(finished, {started: true, outcome: 1, hull: 0});
    await local.restore(colonyWords(finished)); await idle('finished');
    const previous = recording.entry(recording.last), bank = runtime.stores.get(1);
    await order('set-focus', [0]);
    assert.equal(runtime.stores.get(1), bank, 'this user command is also effect-free and unchanged');
    assert.equal(recording.length, 8); assert.equal(recording.dropped, 0);
    assert.equal(recording.entry(recording.last).revision, previous.revision + 65);
    assert.equal(recording.entry(recording.last).command.handler, runtime.command('match', 'set-focus', [0]).handler);
    const imported = await roundTrip(recording);
    for (let sequence = recording.first; sequence <= recording.last; sequence++) {
      assert.deepEqual(imported.entry(sequence), recording.entry(sequence));
      assert.deepEqual(imported.snapshot(sequence), recording.snapshot(sequence));
    }
    await runtime.close();
  });
  await test('an unchanged configured clock command still records its emitted effects', async () => {
    const runtime = await fresh(), local = new LocalState(runtime);
    await runtime.replace(runtime.prepare(bytes, {...manifest, settings: {...manifest.settings, tick: 'pause-colony'}}));
    const recording = runtime.recording = RunRecording.start(runtime), bank = runtime.stores.get(1);
    await local.submit(runtime.command('match', 'pause-colony', [colony(runtime.snapshot(1)).paused]));
    assert.equal(runtime.stores.get(1), bank); assert.equal(recording.length, 2);
    assert.equal(recording.entry(recording.last).effects.length, 1);
    await runtime.close();
  });
  await test('clock filtering follows the current manifest and preserves unchanged boundaries', async () => {
    const runtime = await fresh(), local = new LocalState(runtime);
    const recording = runtime.recording = RunRecording.start(runtime);
    await local.submit(runtime.command('match', manifest.settings.tick)); assert.equal(recording.length, 1);
    const next = {...manifest, generation: 'changed-clock', settings: {...manifest.settings, tick: 'set-focus'}};
    await runtime.replace(runtime.prepare(bytes, next));
    assert.equal(recording.entry(recording.last).kind, 'generation'); assert.equal(recording.length, 2);
    await local.submit(runtime.command('match', manifest.settings.tick)); assert.equal(recording.length, 3);
    await local.submit(runtime.command('match', 'set-focus', [0])); assert.equal(recording.length, 3);
    await local.restore(runtime.snapshot(1));
    assert.equal(recording.entry(recording.last).kind, 'restore'); assert.equal(recording.length, 4);
    recording.stop(); recording.resume(runtime);
    assert.equal(recording.entry(recording.last).kind, 'checkpoint'); assert.equal(recording.length, 5);
    await runtime.close();
  });
  await test('only successful published World commits record; failed storage and observer errors cannot duplicate effects', async () => {
    const runtime = await fresh(); let published = 0, save;
    const local = new LocalState(runtime, {commit: () => save, publish: () => published++});
    const recording = runtime.recording = RunRecording.start(runtime, {revision: () => local.revision});
    let reject, entered; const ready = new Promise(resolve => entered = resolve);
    local.commit = () => { entered(); return new Promise((_, no) => reject = no); };
    const pending = local.submit(runtime.command('match', 'pause-colony', [1])), failed = assert.rejects(pending, /failed save/);
    await ready; assert.equal(recording.length, 1); reject(new Error('failed save')); await failed;
    assert.equal(recording.length, 1); assert.equal(local.revision, 0); assert.equal(published, 0);
    local.commit = () => {}; await local.submit(runtime.command('match', 'pause-colony', [1]));
    assert.equal(recording.length, 2); assert.equal(recording.entry(recording.last).effects.length, 1);
    assert.equal(recording.entry(recording.last).revision, 1); assert.equal(recording.entry(recording.last).persisted, true); assert.equal(published, 1);
    await runtime.dispatch(2, runtime.command('client', 'pan', [1, 0])); assert.equal(recording.length, 2);
    let release; const admitted = new Promise(resolve => entered = resolve);
    local.commit = () => { entered(); return new Promise(resolve => release = resolve); };
    const input = runtime.command('match', 'pause-colony', [1]);
    const handled = runtime.message(dispatch => dispatch(1, input, local.transaction()));
    await admitted; input.args[0] = 0; release(); await handled;
    assert.deepEqual(recording.entry(recording.last).command.args, [1], 'capture the handled arguments before asynchronous persistence');
    local.commit = () => {};
    runtime.recording = {capture() { throw new Error('recorder failed'); }, fail() { throw new Error('also failed'); }};
    await local.submit(runtime.command('match', 'pause-colony', [0]));
    assert.equal(local.revision, 3); assert.equal(published, 3); assert.equal(runtime.recordingError, 'recorder failed');
    await runtime.close();
  });
  await test('real Wasm snapshots, restore/reset/code boundaries and read-only playback survive binary round-trip', async () => {
    const runtime = await fresh(), local = new LocalState(runtime);
    const recording = runtime.recording = RunRecording.start(runtime, {revision: () => local.revision}), snapshots = [runtime.snapshot(1)];
    const order = async (name, args = []) => { await local.submit(runtime.command('match', name, args)); snapshots.push(runtime.snapshot(1)); };
    await order('new-run-seed', [1]); const point = at(colony(runtime.snapshot(1)), 12, 20);
    await order('extract', [point.x, point.y]);
    for (let tick = 0; tick < 35; tick++) await order('advance');
    await order('pause-colony', [1]); await local.restore(runtime.snapshot(1)); snapshots.push(runtime.snapshot(1));
    await runtime.replace(runtime.prepare(bytes, {...manifest, generation: 'compatible-test-generation'})); snapshots.push(runtime.snapshot(1));
    const imported = await roundTrip(recording);
    for (const [sequence, words] of snapshots.entries()) assert.deepEqual(Array.from(imported.snapshot(sequence)), words);
    assert.equal(imported.entry(imported.last).kind, 'generation');
    const liveWorld = runtime.snapshot(1), liveClient = runtime.snapshot(2), liveRevision = local.revision;
    const playback = await SnapshotPlayback.open(bytes, manifest, imported, liveClient);
    const inspected = playback.inspect(); assert.equal(inspected.tick, 35); assert.equal(inspected.extractors, 1);
    await playback.seek(0); assert.equal(playback.inspect().tick, 0);
    await playback.camera(playback.runtime.command('client', 'restart')); // Gameplay endpoints are never admitted.
    await playback.camera(playback.runtime.command('client', 'pan', [2, 1]));
    assert.deepEqual(runtime.snapshot(1), liveWorld); assert.deepEqual(runtime.snapshot(2), liveClient); assert.equal(local.revision, liveRevision);
    await playback.close();
    const analysis = await analyzeRecording(imported, bytes, manifest); assert.ok(analysis.segments.length >= 3);
    assert.ok(analysis.segments.some(run => run.orders.some(order => order.binding === 'extract')));
    await runtime.close();
  });
  await test('finite reserve exhaustion and individual nest clears survive recording projection and analysis', async () => {
    const runtime=await fresh(),local=new LocalState(runtime),point=at(colony(runtime.snapshot(1)),12,20);
    await local.submit(runtime.command('match','extract',[point.x,point.y]));
    for(let tick=0;tick<40;tick++)await local.submit(runtime.command('match','advance'));
    const world=colony(runtime.snapshot(1)),deposit=world.deposits.find(site=>site.cell===point.x+point.y*MAP_WIDTH);
    world.produced+=deposit.remaining-2;world.lostOre+=deposit.remaining-2;deposit.remaining=2;world.tick=49;
    Object.assign(world.bots[0],{x:point.x*40+20,y:point.y*40+20,job:8,target:world.buildings[0].id,cargo:0,path:[]});
    const nest=world.nests[0];nest.hp=6;const x=nest.x,y=nest.y+4;
    world.buildings.push({id:world.nextId++,kind:2,x,y,level:1,hp:100,stock:0,stage:2,cooldown:0,
      aimX:x*40+20,aimY:y*40+20,armed:0,source:0,moveX:-1,moveY:-1});
    world.surveys.push({x,y,radius:6});world.spent+=50;world.ore-=50;
    await local.restore(colonyWords(world));const recording=runtime.recording=RunRecording.start(runtime);
    await local.submit(runtime.command('match','advance'));
    const playback=await SnapshotPlayback.open(bytes,manifest,await roundTrip(recording)),observed=playback.inspect();
    assert.equal(observed.nestsAlive,2);assert.equal(observed.nestHp,1800);assert.equal(observed.nest0Hp,0);
    assert.equal(observed.depositsDepleted,1);assert.equal(observed.produced,world.produced+2);
    assert.equal(observed.oreRemaining,world.deposits.reduce((sum,site)=>sum+site.remaining,0)-2);
    await playback.close();const analysis=await analyzeRecording(recording,bytes,manifest);
    assert.equal(analysis.format,'siegework-observations-v2');assert.deepEqual(analysis.segments[0].nestClears,[{front:0,tick:50,sequence:1}]);
    assert.deepEqual(analysis.segments[0].depositExhaustions,[{tick:50,sequence:1,count:1}]);await runtime.close();
  });
  await test('an oversized committed World stops capture while preserving the durable publication and valid recording prefix', async () => {
    const runtime = await fresh(), local = new LocalState(runtime), before = runtime.stores.get(1);
    const recording = runtime.recording = RunRecording.start(runtime, {bytes: before.byteLength + 512});
    const dense = colony(runtime.snapshot(1)); dense.started = true;
    for (let i = 0; i < 64; i++) dense.enemies.push({id: dense.nextId++, x: dense.bots[0].x, y: dense.bots[0].y,
      hp: 80, kind: 0, rank: 0, burrower: false, target: 0, path: []});
    await local.restore(colonyWords(dense));
    assert.equal(local.revision, 1); assert.equal(colony(runtime.snapshot(1)).enemies.length, 64);
    assert.equal(recording.enabled, false); assert.equal(recording.length, 1); assert.match(recording.reason, /memory limit/);
    assert.deepEqual(recording.snapshot(0), before); await runtime.close();
  });
}
console.log(`${count} recording checks passed`);
