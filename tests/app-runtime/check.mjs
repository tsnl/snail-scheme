// Real static and dynamically linked Wasm: a scene script's main as a
// `snail-scheme` task, its saves, and how a run ends.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {applicationEntry, createEventQueue, createRuntime, FRAME, HIDDEN} from '../../host/browser/runtime.mjs';
import {screenImports} from '../../host/browser/host.mjs';
import {createWasi, instantiate, linkedFileImports, linkProgram, wasmImports} from '../../host/browser/load.mjs';

const path = resolve(process.argv[2]);
const turn = () => new Promise(setImmediate);
const PRESS = 9, RESIZE = 8, MOVE = 4;
const live = run => run.tasks.live();

// Waits up to a hundred turns of the event loop for `condition`.
async function until(condition) {
  for (let count = 0; count < 100 && !condition(); count++) await turn();
  assert.ok(condition());
}

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
  queue.close();
  assert.equal(queue.push(PRESS, 3), false);
  assert.equal(queue.poll(), undefined, 'closing drops the unread input');
  await assert.rejects(queue.wait(), /stopped/);
  const abortable = createEventQueue(), controller = new AbortController();
  const cancelled = abortable.wait(controller.signal);
  controller.abort();
  await assert.rejects(cancelled, {name: 'AbortError'});
  abortable.push(PRESS, 7); await abortable.wait();
  assert.deepEqual(abortable.poll(), [PRESS, 7], 'cancellation does not consume input');
  abortable.close();
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
  queue.close();
  assert.equal(scheduled.size, 0);
  assert.equal(cancelled.length, 1);
  callback(performance.now()); // A stale RAF cannot reach a closed queue.
  assert.equal(queue.poll(), undefined);
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
  const imports = {...runtime.imports, 'snail.runtime.browser.screen': screen};
  let program;
  if (path.endsWith('.manifest.datum')) {
    program = await linkProgram(file => readFile(resolve(dirname(path), file)), path, wasi, imports);

  } else {
    const module = await WebAssembly.compile(await readFile(path));
    program = await instantiate(module, {...wasi.getImportObject(), ...imports, ...portable(module)});
    wasi.initialize(program);
  }
  const entry = applicationEntry(program);
  return {observed, runtime, entry};
}

// Input sent during startup is delivered after the first frame; hiding
// saves, and a later run boots from that save.
async function checkStartup() {
  const loaded = Promise.withResolvers();
  const saves = [];
  const app = await application({load: () => loaded.promise, store: async bytes => { saves.push(bytes); }});
  const {runtime, entry, observed} = app;
  const run = runtime.start(entry);
  runtime.send(PRESS, 1); runtime.send(PRESS, 1);
  await turn();
  assert.equal(live(run), 2, 'the scene and its sleeping child both remain live');
  assert.equal(observed.frames, 0);
  assert.throws(() => runtime.start(entry), /overlap/);
  loaded.resolve(undefined);
  assert.equal(await run.ready.promise, 2, 'a page without a save starts fresh');
  await until(() => observed.count === '2');
  runtime.send(HIDDEN);
  await until(() => saves.length === 1);
  runtime.close();
  assert.equal(live(run), 0, 'closing discards every task');
  const later = await application({load: async () => saves[0]});
  assert.equal(await later.runtime.start(later.entry).ready.promise, 1, 'a page with a save restores it');
  assert.equal(later.observed.count, '2', 'the restored count, shown on the first Resize');
  later.runtime.send(PRESS, 1);
  await until(() => later.observed.count === '3');
  later.runtime.close();
}

// A trap in any task ends the run, reported once, and the page keeps its
// last save.
async function checkTraps() {
  const app = await application(), {runtime, entry, observed} = app;
  const run = runtime.start(entry);
  await run.ready.promise;
  observed.failFrame = true;
  runtime.send(FRAME, 5);
  assert.match((await run.done).error.message, /presentation trap/);
  assert.equal(observed.errors.length, 1);
  assert.equal(runtime.execution.queue.closed, true);
  const update = await application(), started = update.runtime.start(update.entry);
  await started.ready.promise;
  update.runtime.send(PRESS, 2);
  assert.ok((await started.done).error, 'a snail-scheme panic ends the run');
}

// A save the scene cannot read traps before boot, as application.mjs's
// startCold expects; a run without it then starts fresh.
async function checkUnreadableSave() {
  const app = await application({load: async () => new Uint8Array([255, 255, 255])});
  const run = app.runtime.start(app.entry);
  await assert.rejects(run.ready.promise);
  await run.done;
  assert.equal(run.boot, null);
  assert.ok(run.loaded);
  assert.equal(await app.runtime.start(app.entry, {fresh: true}).ready.promise, 2);
  app.runtime.close();
}

async function checkStartupFailures() {
  const rejected = await application({load: async () => { throw new Error('load failed'); }});
  const loading = rejected.runtime.start(rejected.entry);
  await assert.rejects(loading.ready.promise, /load failed/);
  await loading.done;
  const trapped = await application();
  trapped.observed.failFrame = true;
  const first = trapped.runtime.start(trapped.entry);
  await assert.rejects(first.ready.promise, /presentation trap/);
  await first.done;
}

async function checkStorageFailure() {
  const app = await application({store: async () => { throw new Error('disk full'); }});
  await app.runtime.start(app.entry).ready.promise;
  app.runtime.send(HIDDEN);
  await until(() => app.observed.warnings.length === 1);
  assert.match(app.observed.warnings[0], /disk full/);
  assert.equal(app.runtime.execution.queue.closed, false, 'a failed save leaves the page running');
  app.runtime.close();
}

// A library may not take a name the host provides: the program's modules
// would import that library in place of the host's interface.
async function checkReservedName() {
  if (!path.endsWith('.manifest.datum')) return;
  const renamed = async file => {
    const bytes = await readFile(resolve(dirname(path), file));
    if (resolve(dirname(path), file) !== path) return bytes;
    return new TextEncoder().encode(new TextDecoder().decode(bytes).replace(/\(module "[^"]+"/, '(module "snail.runtime.wasm"'));
  };
  await assert.rejects(linkProgram(renamed, path, createWasi({print() {}}), {}),
    /no library may be linked as snail\.runtime\.wasm, which the host provides/);
}

await checkQueue();
checkFrames();
await checkStartup();
await checkTraps();
await checkUnreadableSave();
await checkStartupFailures();
await checkStorageFailure();
await checkReservedName();
console.log('app runtime: the scene as a task, storage by ticket, queued input, inherited handlers and saves passed');

// The imports of the capabilities the target installs and this test leaves
// unused: the files a program links and the host's WebAssembly.
function portable(module) {
  const unread = file => { throw new Error(`this test reads no linked file ${file}`); };
  return {...linkedFileImports(unread, module), 'snail.runtime.wasm': wasmImports(() => null)};
}
