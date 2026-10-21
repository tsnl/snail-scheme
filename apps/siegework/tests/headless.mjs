// Runs the compiled game without a browser: a recording screen host, ticks,
// an order placed by pointing, and a save replayed through the application
// entry points.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const TICK = 11, PRESS = 9, RESIZE = 8, POINTER_UP = 5, POINTER_MOVE = 4, POINTER_DOWN = 3;

// Records each frame's batches and the latest HUD's texts.
function screen() {
  const frames = [];
  const host = {frames, text: [], imports: null};
  let frame = null, widget = null, field = null, texts = null;
  host.imports = {
    'frame-begin'() { frame = {batches: []}; },
    camera(...camera) { frame.camera = camera; },
    light() {},
    'batch-begin'(key, version) { frame.batches.push({key, version, items: 0}); return 0; },
    instance() { frame.batches.at(-1).items++; },
    'frame-end'() { frames.push(frame); },
    'hud-begin'() { texts = []; },
    'panel-begin'() {},
    'widget-begin'() { widget = {text: ''}; texts.push(widget); },
    field(which) { field = which; },
    'text-character'(code) { if (field === 4) widget.text += String.fromCodePoint(code); },
    'hud-end'() { host.text = texts.map(entry => entry.text); },
  };
  return host;
}

async function instantiate(path, host) {
  let exports;
  const view = () => new DataView(exports.memory.buffer);
  const wasi = {
    fd_write(fd, iovs, count, written) {
      let total = 0;
      for (let i = 0; i < count; i++) {
        const pointer = view().getUint32(iovs + 8 * i, true), length = view().getUint32(iovs + 8 * i + 4, true);
        process.stdout.write(Buffer.from(exports.memory.buffer, pointer, length));
        total += length;
      }
      view().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`exit ${code}`); },
    environ_get: () => 0, environ_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
    fd_close: () => 0, fd_prestat_get: () => 8, fd_prestat_dir_name: () => 8,
  };
  const {instance} = await WebAssembly.instantiate(await readFile(path), {wasi_snapshot_preview1: wasi, 'snail.screen': host.imports});
  exports = instance.exports;
  exports._initialize();
  exports.main();
  return exports;
}

const path = process.argv[2];
const host = screen();
const game = await instantiate(path, host);
game.app_init(7, 960, 640);
game.app_frame(0);
const first = host.frames.at(-1);
assert.deepEqual(first.batches.map(batch => batch.key), [1, 3, 5, 4, 6], 'terrain, structures, motion, shimmer and cursor');
assert.ok(first.batches[0].items > 200, 'the explored ground around the hub');
assert.ok(host.text.some(text => text.startsWith('Energy 160')), host.text.join(' | '));

// The camera looks at the hub, so the middle pixel picks the hub's cell.
game.app_input(POINTER_MOVE, 1, 480, 320, 0);
assert.ok(host.text.some(text => text.startsWith('Hub')), host.text.join(' | '));

// Find the starter crystal by hovering until the inspector names it, then
// order an extractor there and let the colony run for five minutes.
const text = () => host.text;
let crystal = null;
for (let y = 10; y < 640 && !crystal; y += 20)
  for (let x = 10; x < 960 && !crystal; x += 20) {
    game.app_input(POINTER_MOVE, 1, x, y, 0);
    if (text().some(line => line.startsWith('Crystal'))) crystal = [x, y];
  }
assert.ok(crystal, 'a crystal is in view');
game.app_input(PRESS, 1, 0, 0, 0);
game.app_input(POINTER_DOWN, 1, crystal[0], crystal[1], 0);
game.app_input(POINTER_UP, 1, crystal[0], crystal[1], 0);
for (let i = 0; i < 3000; i++) game.app_input(TICK, 0, 0, 0, 0);
game.app_frame(0.5);
console.log(text().slice(0, 5).join(' | '));

// Save, restore into a fresh instance, and compare what each draws.
const length = game.app_save();
const bytes = Uint8Array.from({length}, (_, i) => game.app_save_byte(i));
const other = screen();
const restored = await instantiate(path, other);
const started = performance.now();
restored.app_load_begin(bytes.length);
bytes.forEach((byte, index) => restored.app_load_byte(index, byte));
restored.app_load_end();
const elapsed = performance.now() - started;
restored.app_input(RESIZE, 960, 640, 0, 0);
restored.app_frame(0.5);
// The world is the same; selection and messages start afresh.
const world = texts => [...texts.slice(0, 4), texts.at(-1)];
assert.deepEqual(world(other.text), world(host.text));
console.log(`a journal of ${length} bytes replays the same frame in ${elapsed.toFixed(0)} ms`);
