// Runs the compiled game without a browser: a recording screen host, taps
// that select cells, an order given through the HUD's card, five minutes of
// play, and a save replayed through the application entry points.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const TICK = 11, PRESS = 9, RESIZE = 8, POINTER_UP = 5, POINTER_DOWN = 3;

// Records each frame's batches and the latest HUD's widgets.
function screen() {
  const host = {frames: [], widgets: [], imports: null};
  let frame = null, widget = null, field = null, widgets = null;
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption'];
  host.imports = {
    'frame-begin'() { frame = {batches: []}; },
    camera() {},
    light() {},
    'batch-begin'(key, version) { frame.batches.push({key, version, items: 0}); return 0; },
    instance() { frame.batches.at(-1).items++; },
    'frame-end'() { host.frames.push(frame); },
    'hud-begin'() { widgets = []; },
    'panel-begin'() { widget = {key: ''}; },
    'widget-begin'(kind, tone, action, argument, control) {
      widget = {kind, action, argument, control, key: '', icon: '', help: '', badge: '', text: '', caption: ''};
      widgets.push(widget);
    },
    field(which) { field = fields[which]; },
    'text-character'(code) { widget[field] += String.fromCodePoint(code); },
    'hud-end'() { host.widgets = widgets; },
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

const widget = (host, key) => host.widgets.find(entry => entry.key === key);
const tap = (game, x, y) => { game.app_input(POINTER_DOWN, 1, x, y, 0); game.app_input(POINTER_UP, 1, x, y, 0); };

const path = process.argv[2];
const host = screen();
const game = await instantiate(path, host);
game.app_init(7, 960, 640);
game.app_frame(0);
const first = host.frames.at(-1);
assert.deepEqual(first.batches.map(batch => batch.key), [1, 3, 5, 4, 6], 'terrain, structures, motion, shimmer and cursor');
assert.ok(first.batches[0].items > 200, 'the explored ground around the hub');
assert.equal(widget(host, 'energy').text, '160');
assert.equal(widget(host, 'nests').text, '☆☆☆');

// The camera looks at the hub, so a tap in the middle selects it.
tap(game, 480, 320);
assert.ok(widget(host, 'title').text.startsWith('Hub'), widget(host, 'title').text);

// Tap around until the card shows a crystal, then build an extractor there
// through the card's button.
let crystal = null;
for (let y = 10; y < 640 && !crystal; y += 20)
  for (let x = 10; x < 960 && !crystal; x += 20) {
    tap(game, x, y);
    if (widget(host, 'title')?.text.startsWith('Crystal')) crystal = widget(host, 'build-extractor');
  }
assert.ok(crystal, 'a crystal is in view');
game.app_input(PRESS, crystal.action, crystal.argument, 0, 0);
assert.equal(widget(host, 'energy').text, '135');
assert.ok(widget(host, 'queue-0'), 'the extractor is queued');
for (let i = 0; i < 3000; i++) game.app_input(TICK, 0, 0, 0, 0);
game.app_frame(0.5);
const readouts = h => ['energy', 'health', 'slots', 'threat', 'elapsed'].map(key => widget(h, key)?.text);
console.log(readouts(host).join(' | '));

// Save, restore into a fresh instance, and compare what each shows.
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
assert.deepEqual(readouts(other), readouts(host));
console.log(`a journal of ${length} bytes replays the same colony in ${elapsed.toFixed(0)} ms`);
