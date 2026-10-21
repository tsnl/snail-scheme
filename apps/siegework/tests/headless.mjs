// Runs the compiled game without a browser: a recording screen host, keys
// that pan, the opening's banner and pulsing crystals, taps that select
// cells, an order given through the HUD's card, five minutes of play, and a
// save replayed through the application entry points.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const ELAPSED = 11, PRESS = 9, RESIZE = 8, POINTER_UP = 5, POINTER_DOWN = 3, KEY_DOWN = 1, KEY_UP = 2;
const SUGGESTED = 5;

// Records each frame's batches, the camera's target, and the latest HUD's
// widgets.
function screen() {
  const host = {frames: [], widgets: [], target: null, imports: null};
  let frame = null, widget = null, field = null, widgets = null;
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption'];
  host.imports = {
    'frame-begin'() { frame = {batches: []}; },
    camera(ex, ey, ez, tx, ty, tz) { host.target = [tx, tz]; },
    light() {},
    'batch-begin'(key, version) { frame.batches.push({key, version, items: 0}); return 0; },
    instance() { frame.batches.at(-1).items++; },
    'frame-end'() { host.frames.push(frame); },
    'hud-begin'() { widgets = []; },
    'panel-begin'() { widget = {key: ''}; },
    'widget-begin'(kind, tone, action, argument, control) {
      widget = {kind, tone, action, argument, control, key: '', icon: '', help: '', badge: '', text: '', caption: ''};
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
game.app_frame();
const first = host.frames.at(-1);
assert.deepEqual(first.batches.map(batch => batch.key), [1, 3, 5, 8, 9, 6, 4, 10, 7],
                 'terrain, structures, motion, bars, links, cursor, shimmer, beacons and preview');
assert.ok(first.batches[7].items > 0, 'the crystals in sight pulse before the game begins');
assert.equal(widget(host, 'opening').text, 'Build an extractor to continue');
assert.ok(first.batches[0].items > 200, 'the explored ground around the hub');
assert.equal(widget(host, 'energy').text, '160');
assert.equal(widget(host, 'nests').text, '☆☆☆');

// Holding D for a second pans nine cells along the ground; holding W for a
// second pans eighteen, the ground being seen at 30 degrees.
const panned = (key, milliseconds, shift = 0) => {
  const [x, z] = host.target;
  game.app_input(KEY_DOWN, key, shift, 0, 0);
  for (let i = 0; i < milliseconds / 50; i++) game.app_input(ELAPSED, 50, 0, 0, 0);
  game.app_input(KEY_UP, key, 0, 0, 0);
  game.app_frame();
  const [x2, z2] = host.target;
  return Math.hypot(x2 - x, z2 - z);
};
assert.ok(Math.abs(panned(100, 1000) - 9) < 0.01, 'D pans nine cells a second');
assert.ok(Math.abs(panned(119, 1000) - 18) < 0.01, 'W pans eighteen cells of ground a second');
assert.ok(Math.abs(panned(100, 1000, 1) - 9) < 0.01, 'Shift+D pans as D does');
game.app_input(KEY_DOWN, 104, 0, 0, 0);
game.app_input(KEY_UP, 104, 0, 0, 0);
game.app_frame();

// The camera looks at the hub, so a tap in the middle selects it and the
// construction panel offers the hub's buttons.
tap(game, 480, 320);
assert.ok(widget(host, 'repair'), 'the hub can be repaired');

// Tap around until the construction panel offers an extractor, then build
// it through that button.
let crystal = null;
for (let y = 10; y < 640 && !crystal; y += 20)
  for (let x = 10; x < 960 && !crystal; x += 20) {
    tap(game, x, y);
    const button = widget(host, 'build-extractor');
    if (button && button.control === 0) crystal = button;
  }
assert.ok(crystal, 'a crystal is in view');
assert.equal(crystal.tone, SUGGESTED, 'the opening suggests the extractor');
game.app_input(PRESS, crystal.action, crystal.argument, 0, 0);
assert.equal(widget(host, 'energy').text, '135');
assert.ok(widget(host, 'scavenge'), 'the first extractor is ready at once');
assert.ok(!widget(host, 'opening'), 'the banner leaves once the game begins');
game.app_frame();
assert.ok(!host.frames.at(-1).batches.some(batch => batch.key === 10), 'and so do the pulsing crystals');
// Each tenth of a second advances the world a tick.
for (let i = 0; i < 3000; i++) game.app_input(ELAPSED, 100, 0, 0, 0);
game.app_frame();
const readouts = h => ['health', 'energy', 'threat', 'elapsed'].map(key => widget(h, key)?.text);
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
restored.app_frame();
assert.deepEqual(readouts(other), readouts(host));
console.log(`a journal of ${length} bytes replays the same colony in ${elapsed.toFixed(0)} ms`);
