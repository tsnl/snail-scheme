// Runs the compiled game without a browser: a recording screen host, keys
// that pan, the opening's banner and pulsing crystals, taps that select
// cells, an order given through the HUD's card, five minutes of play, a drag
// of the camera, and a save replayed through the application entry points.
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import assert from 'node:assert/strict';
import {screenImports} from '../../../src/app/host.mjs';
import {createWasi, instantiate, linkProgram, programExports, runProgram} from '../../../src/app/load.mjs';

const ELAPSED = 11, PRESS = 9, RESIZE = 8, POINTER_UP = 5, POINTER_MOVE = 4, POINTER_DOWN = 3, KEY_DOWN = 1, KEY_UP = 2;
const SUGGESTED = 5;

// The browser host's screen with a renderer that records each frame and
// holds no batch, a picture store that has every picture, and a HUD that
// keeps the latest widgets.
function screen() {
  const host = {frames: [], widgets: [], imports: null};
  host.imports = screenImports({hasBatch: () => false, draw: frame => host.frames.push(frame)}, {has: () => true},
                               {update: panels => { host.widgets = panels.flatMap(panel => panel.widgets); }});
  return host;
}

// Where the camera looked in the last frame, on the ground.
const target = host => [host.frames.at(-1).camera.target[0], host.frames.at(-1).camera.target[2]];

// A linked module, or a modules.json naming the game's library modules,
// which link to a runtime instance of their own (src/app/load.mjs).
async function instantiateGame(path, host) {
  const wasi = createWasi({print: (fd, line) => console.log(line)});
  if (path.endsWith('.json')) {
    const program = await linkProgram(file => readFile(resolve(dirname(path), file)), path, wasi, {'snail.screen': host.imports});
    runProgram(program);
    return programExports(program);
  }
  const instance = await instantiate(await WebAssembly.compile(await readFile(path)), {...wasi.getImportObject(), 'snail.screen': host.imports});
  wasi.initialize(instance);
  instance.exports.main();
  return instance.exports;
}

const widget = (host, key) => host.widgets.find(entry => entry.key === key);
const tap = (game, x, y) => { game.app_input(POINTER_DOWN, 1, x, y, 0); game.app_input(POINTER_UP, 1, x, y, 0); };

const path = resolve(process.argv[2]);
const host = screen();
const game = await instantiateGame(path, host);
game.app_init(7, 960, 640);
game.app_frame();
const first = host.frames.at(-1);
assert.deepEqual(first.batches.map(batch => batch.key), [1, 3, 5, 8, 9, 6, 4, 10, 7],
                 'terrain, structures, motion, bars, links, cursor, shimmer, beacons and preview');
assert.ok(first.batches[7].items.length > 0, 'the crystals in sight pulse before the game begins');
assert.equal(widget(host, 'opening-title').text, 'Siegework');
const spoken = key => widget(host, key).spans.map(span => span.strong ? `*${span.words}*` : span.words).join('');
assert.equal(spoken('opening-crystal'), 'Click the *glowing crystal*');
assert.match(widget(host, 'how-to-play').url, /games\/siegework\.html$/);
assert.ok(first.batches[0].items.length > 200, 'the explored ground around the hub');
assert.equal(widget(host, 'energy').text, '160');
assert.equal(widget(host, 'nests').text, '☆☆☆');
// The camera opens on the starter crystal: a tap in the middle offers the
// suggested extractor.
tap(game, 480, 320);
assert.equal(widget(host, 'build-extractor').control, 0, 'the starter crystal is in the middle');
assert.equal(widget(host, 'build-extractor').tone, SUGGESTED);
game.app_input(KEY_DOWN, 53, 0, 0, 0);
game.app_input(KEY_UP, 53, 0, 0, 0);

// Holding D for a second pans nine cells along the ground; holding W for a
// second pans eighteen, the ground being seen at 30 degrees.
const panned = (key, milliseconds, shift = 0) => {
  const [x, z] = target(host);
  game.app_input(KEY_DOWN, key, shift, 0, 0);
  for (let i = 0; i < milliseconds / 50; i++) game.app_input(ELAPSED, 50, 0, 0, 0);
  game.app_input(KEY_UP, key, 0, 0, 0);
  game.app_frame();
  const [x2, z2] = target(host);
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
assert.equal(spoken('opening-build'), 'Click the *build button* to continue');
game.app_input(PRESS, crystal.action, crystal.argument, 0, 0);
assert.equal(widget(host, 'energy').text, '135');
assert.ok(widget(host, 'scavenge'), 'the first extractor is ready at once');
assert.ok(!widget(host, 'opening-title'), 'the banner leaves once the game begins');
game.app_frame();
assert.ok(!host.frames.at(-1).batches.some(batch => batch.key === 10), 'and so do the pulsing crystals');
// Each tenth of a second advances the world a tick. The first attack
// raises the alert under the nests.
let alarm = null;
for (let i = 0; i < 3000; i++) {
  game.app_input(ELAPSED, 100, 0, 0, 0);
  alarm ??= widget(host, 'attack');
}
assert.ok(alarm, 'an attack raises the alert');
game.app_frame();
const readouts = h => ['health', 'energy', 'threat', 'elapsed'].map(key => widget(h, key)?.text);
console.log(readouts(host).join(' | '));

// A drag pans the camera away from the hub.
const resting = host.frames.at(-1).camera;
game.app_input(POINTER_DOWN, 1, 480, 320, 0);
game.app_input(POINTER_MOVE, 1, 380, 260, 0);
game.app_input(POINTER_UP, 1, 380, 260, 0);
game.app_frame();
assert.notDeepEqual(host.frames.at(-1).camera, resting, 'the drag moves the camera');

// Save, restore into a fresh instance, and compare what each shows.
const length = game.app_save();
const bytes = Uint8Array.from({length}, (_, i) => game.app_save_byte(i));
const other = screen();
const restored = await instantiateGame(path, other);
const started = performance.now();
restored.app_load_begin(bytes.length);
bytes.forEach((byte, index) => restored.app_load_byte(index, byte));
restored.app_load_end();
const elapsed = performance.now() - started;
restored.app_input(RESIZE, 960, 640, 0, 0);
restored.app_frame();
assert.deepEqual(readouts(other), readouts(host));
assert.deepEqual(other.frames.at(-1).camera, host.frames.at(-1).camera, 'the restored game looks where the saved one did');
console.log(`a journal of ${length} bytes replays the same colony in ${elapsed.toFixed(0)} ms`);
