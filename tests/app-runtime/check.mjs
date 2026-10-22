// Real static and dynamically linked Wasm: suspension, fencing and recovery.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {applicationEntry, createEventQueue, createRuntime, FRAME, HIDDEN, RELOAD} from '../../src/app/runtime.mjs';
import {screenImports} from '../../src/app/host.mjs';
import {createWasi, instantiate, linkProgram, runProgram} from '../../src/app/load.mjs';

const path = resolve(process.argv[2]);
const turn = () => new Promise(setImmediate);
const PRESS = 9, RESIZE = 8, MOVE = 4;

async function checkQueue() {
  const queue = createEventQueue();
  queue.push(MOVE, 1, 10); queue.push(MOVE, 1, 20);
  queue.push(PRESS, 1); queue.push(MOVE, 1, 30);
  queue.push(MOVE, 2, 40); queue.push(RESIZE, 10, 20); queue.push(RESIZE, 30, 40);
  assert.deepEqual(Array.from({length: 5}, () => queue.poll()),
                   [[MOVE, 1, 20], [PRESS, 1], [MOVE, 1, 30], [MOVE, 2, 40], [RESIZE, 30, 40]]);
  const waiting = queue.wait();
  queue.push(PRESS, 2);
  await waiting;
  await queue.wait(); // An already queued event cannot lose its wakeup.
  queue.reload();
  assert.equal(queue.push(PRESS, 3), false);
  assert.deepEqual([queue.poll(), queue.poll(), queue.poll()], [[PRESS, 2], [RELOAD], undefined]);
  queue.close();
  await assert.rejects(queue.wait(), /stopped/);
}

function checkFrames() {
  let next = 0;
  const scheduled = new Map(), cancelled = [];
  const queue = createEventQueue({request: callback => { scheduled.set(++next, callback); return next; },
                                  cancel: ticket => { cancelled.push(ticket); scheduled.delete(ticket); }});
  queue.push(FRAME, 0);
  assert.deepEqual(queue.poll(), [FRAME, 0]);
  assert.equal(scheduled.size, 1);
  const [ticket, callback] = [...scheduled][0];
  scheduled.delete(ticket); callback(performance.now() + 1000);
  queue.push(FRAME, 12); // A slow consumer keeps only one queued tick.
  assert.deepEqual(queue.poll(), [FRAME, 250]);
  assert.equal(queue.poll(), undefined);
  assert.equal(scheduled.size, 1);
  queue.reload();
  assert.equal(scheduled.size, 0);
  assert.equal(cancelled.length, 1);
  callback(performance.now()); // A stale RAF cannot cross the reload fence.
  assert.deepEqual(queue.poll(), [RELOAD]);
  assert.equal(queue.poll(), undefined);
  queue.close();
}

async function application(options = {}) {
  const observed = {count: null, frames: 0, failFrame: false, errors: [], warnings: []};
  const runtime = createRuntime({...options, reportError: error => observed.errors.push(error), warn: text => observed.warnings.push(text)});
  const screen = screenImports({hasBatch: () => false, draw() {
    if (observed.failFrame) throw new Error('a deliberate presentation trap');
    observed.frames++;
  }}, {has: () => true}, {update: panels => {
    observed.count = panels.flatMap(panel => panel.widgets).find(widget => widget.key === 'count')?.text;
  }});
  const wasi = createWasi({print() {}});
  const imports = {...runtime.imports, 'snail.screen': screen, 'snail.test': {marker: () => -9}};
  let program;
  if (path.endsWith('.json')) {
    program = await linkProgram(file => readFile(resolve(dirname(path), file)), path, wasi, imports);
    runProgram(program);
  } else {
    program = await instantiate(await WebAssembly.compile(await readFile(path)), {...wasi.getImportObject(), ...imports});
    wasi.initialize(program); program.exports.main();
  }
  const entry = applicationEntry(program), initialHandlers = entry.handlers.map(global => global.value);
  function settled() {
    assert.deepEqual(entry.handlers.map(global => global.value), initialHandlers, 'all dynamic handlers return to their entry values');
    assert.equal(entry.exports.marker(), -9, 'the private reset handler has been removed');
  }
  return {observed, runtime, entry, settled};
}

async function checkSuspension() {
  const loaded = Promise.withResolvers(), stored = Promise.withResolvers();
  let saves = 0;
  const app = await application({load: () => loaded.promise, store: async () => { if (++saves === 1) await stored.promise; }});
  const {runtime, entry, observed} = app;
  const run = runtime.start(entry);
  runtime.send(PRESS, 1); runtime.send(PRESS, 1);
  await turn();
  const installed = entry.handlers.map(global => global.value);
  assert.ok(installed.some(value => value !== null), 'reset stays installed while loading');
  assert.equal(observed.frames, 0);
  assert.throws(() => runtime.start(entry), /overlap/);
  loaded.resolve(undefined);
  assert.equal(await run.ready.promise, 2);
  await turn();
  assert.equal(observed.count, '2', 'input received during startup follows initial presentation');
  assert.deepEqual(entry.handlers.map(global => global.value), installed, 'the same handler survives storage and event suspension');
  runtime.send(HIDDEN);
  await turn();
  assert.equal(saves, 1);
  runtime.send(PRESS, 1);
  const stopping = runtime.stop();
  runtime.send(PRESS, 1); // Arrives beyond the fence, for the next invocation.
  await turn();
  assert.equal(runtime.execution.queue.closed, false, 'reload waits for storage instead of abandoning a stack');
  assert.equal(observed.count, '2');
  stored.resolve();
  const handover = await stopping;
  assert.equal(entry.exports.count(handover.state), 3n, 'the accepted prefix completes before Reload');
  assert.ok(handover.saved.length);
  app.settled();
  assert.equal(await runtime.start(entry, handover.state).ready.promise, 0);
  await turn();
  assert.equal(observed.count, '4', 'transition input is delivered once after adoption');
  await runtime.stop();
  app.settled();
}

async function checkReloadDuringBoot() {
  const loaded = Promise.withResolvers();
  const app = await application({load: () => loaded.promise}), {runtime, entry, observed} = app;
  const first = runtime.start(entry);
  await turn();
  runtime.send(PRESS, 1);
  const stopping = runtime.stop();
  loaded.resolve(undefined);
  await first.ready.promise;
  const handover = await stopping;
  assert.equal(entry.exports.count(handover.state), 0n, 'input beyond a startup fence waits for the next run');
  app.settled();
  await runtime.start(entry, handover.state).ready.promise;
  await turn();
  assert.equal(observed.count, '1', 'accepting a fenced startup never discards pending input');
  await runtime.stop();
  app.settled();
}

async function checkTrap() {
  const app = await application(), {runtime, entry, observed} = app;
  const run = runtime.start(entry);
  await run.ready.promise;
  runtime.send(PRESS, 1);
  await turn();
  observed.failFrame = true;
  runtime.send(FRAME, 5); runtime.send(PRESS, 1); runtime.send(PRESS, 1);
  const failed = await run.done;
  assert.match(failed.error.message, /presentation trap/);
  assert.equal(entry.exports.count(failed.state), 1n, 'the partially rendered candidate never becomes a checkpoint');
  assert.equal(observed.errors.length, 1);
  app.settled();
  const frames = observed.frames;
  const handover = await runtime.stop();
  assert.equal(handover.error, null);
  assert.equal(observed.frames, frames, 'checkpoint extraction does not replay the failing view');
  assert.equal(entry.exports.count(handover.state), 1n);
  assert.ok(handover.saved.length);
  app.settled();
  observed.failFrame = false;
  await runtime.start(entry, handover.state).ready.promise;
  await turn();
  assert.equal(observed.count, '3', 'unread actions survive a trap and are consumed once');
  await runtime.stop();
  app.settled();
}

async function checkUpdateTrap() {
  const app = await application(), {runtime, entry, observed} = app;
  const run = runtime.start(entry);
  await run.ready.promise;
  runtime.send(PRESS, 1);
  await turn();
  runtime.send(PRESS, 2); runtime.send(PRESS, 1);
  const failure = await run.done;
  assert.ok(failure.error, 'a Lofi panic rejects the JSPI entry');
  assert.equal(entry.exports.count(failure.state), 1n);
  app.settled();
  const handover = await runtime.stop();
  await runtime.start(entry, handover.state).ready.promise;
  await turn();
  assert.equal(observed.count, '2', 'the trapping action is consumed and the following action survives');
  await runtime.stop();
  app.settled();
}

async function checkRefusal() {
  const app = await application(), {runtime, entry, observed} = app;
  await runtime.start(entry).ready.promise;
  const previous = await runtime.stop();
  const foreign = entry.exports.other();
  const refused = runtime.start(entry, foreign, {restore: null});
  runtime.send(PRESS, 1);
  await assert.rejects(refused.ready.promise, /could not take over/);
  assert.equal((await refused.done).state, null);
  app.settled();
  await runtime.start(entry, previous.state).ready.promise;
  await turn();
  assert.equal(observed.count, '1');
  const rollback = await runtime.stop();
  assert.equal(entry.exports.resizes(rollback.state), 2, 'a rejected candidate cannot donate its synthetic Resize to rollback');
  app.settled();
}

async function checkStartupFailures() {
  const loadError = new Error('load failed');
  const rejected = await application({load: async () => { throw loadError; }});
  const loading = rejected.runtime.start(rejected.entry);
  await assert.rejects(loading.ready.promise, /load failed/);
  assert.equal((await loading.done).state, null, 'a preboot failure cannot invent a checkpoint');
  rejected.settled();
  const trapped = await application();
  trapped.observed.failFrame = true;
  const first = trapped.runtime.start(trapped.entry);
  await assert.rejects(first.ready.promise, /presentation trap/);
  assert.equal(trapped.entry.exports.count((await first.done).state), 0n, 'the boot checkpoint survives a first-frame trap');
  trapped.settled();
  trapped.observed.failFrame = false;
  const saved = await trapped.runtime.stop();
  await trapped.runtime.start(trapped.entry, saved.state).ready.promise;
  await trapped.runtime.stop();
  trapped.settled();
}

async function checkStorageFailure() {
  const app = await application({store: async () => { throw new Error('disk full'); }});
  await app.runtime.start(app.entry).ready.promise;
  const handover = await app.runtime.stop();
  assert.equal(handover.error, null);
  assert.ok(handover.saved.length, 'migration keeps an owned save even if persistence fails');
  assert.match(app.observed.warnings[0], /disk full/);
  app.settled();
}

await checkQueue();
checkFrames();
await checkSuspension();
await checkReloadDuringBoot();
await checkTrap();
await checkUpdateTrap();
await checkRefusal();
await checkStartupFailures();
await checkStorageFailure();
console.log('app runtime: suspended storage, queued input, handler restoration and checkpoint recovery passed');
