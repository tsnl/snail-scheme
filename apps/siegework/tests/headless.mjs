// Runs the compiled game without a browser: a recording screen host, ticks,
// a click, and a save and restore through the application entry points.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const TICK = 9, PRESS = 8, POINTER_DOWN = 4, POINTER_MOVE = 3;

function screen() {
  const frames = [];
  let frame = null, widget = null;
  return {frames, imports: {
    'frame-begin'(...camera) { frame = {camera, batches: [], text: []}; },
    'batch-begin'(key, version) { frame.batches.push({key, version, items: 0}); return 0; },
    instance() { frame.batches.at(-1).items++; },
    'panel-begin'() {},
    'widget-begin'() { widget = ''; frame.text.push(widget); },
    'text-character'(code) { frame.text[frame.text.length - 1] += String.fromCodePoint(code); },
    'frame-end'() { frames.push(frame); },
  }};
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
assert.equal(first.batches.length, 3);
assert.equal(first.batches[0].items, 1600, 'one item per map cell');
assert.ok(first.text.some(text => text.startsWith('Ore 60')), first.text.join(' | '));

// Choose the extractor tool and click the middle of the screen.
game.app_input(PRESS, 1, 0, 0);
game.app_input(POINTER_MOVE, 480, 320, 0);
game.app_input(POINTER_DOWN, 480, 320, 0);
for (let i = 0; i < 200; i++) game.app_input(TICK, 0, 0, 0);
game.app_frame(0.5);
console.log(host.frames.at(-1).text.slice(0, 5).join(' | '));

// Save, restore into a fresh instance, and compare what each draws.
const length = game.app_save();
const bytes = Uint8Array.from({length}, (_, i) => game.app_save_byte(i));
const other = screen();
const restored = await instantiate(path, other);
restored.app_load_begin(bytes.length);
bytes.forEach((byte, index) => restored.app_load_byte(index, byte));
restored.app_load_end();
restored.app_frame(0.5);
assert.deepEqual(other.frames.at(-1).text, host.frames.at(-1).text);
console.log(`save of ${length} bytes restores the same frame`);
