// Runs the compiled game without a browser: a recording screen host, keys
// that pan, the opening's banner and pulsing crystals, taps that select
// cells, an order given through the HUD's card, five minutes of play, a drag
// of the camera, and a save replayed through the JSPI application loop.
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import assert from 'node:assert/strict';
import {screenImports} from '../../../host/browser/host.mjs';
import {createRuntime, applicationEntry} from '../../../host/browser/runtime.mjs';
import {createWasi, instantiate, linkProgram, runProgram} from '../../../host/browser/load.mjs';

const ELAPSED = 11, PRESS = 9, POINTER_UP = 5, POINTER_MOVE = 4, POINTER_DOWN = 3, KEY_DOWN = 1, KEY_UP = 2;
const SUGGESTED = 5;

// The browser host's screen with a renderer that records the latest frame and
// holds no batch, a picture store that has every picture, and a HUD that
// keeps the latest widgets.
function screen() {
  const host = {frames: [], widgets: [], imports: null};
  host.imports = screenImports({hasBatch: () => false, draw: frame => { host.frames = [frame]; }}, {has: () => true},
                               {update: panels => { host.widgets = panels.flatMap(panel => panel.widgets); }});
  return host;
}

// Where the camera looked in the last frame, on the ground.
const target = host => [host.frames.at(-1).camera.target[0], host.frames.at(-1).camera.target[2]];

// A linked module, or a modules.json naming the game's library modules,
// which link to a runtime instance of their own (host/browser/load.mjs).
async function instantiateGame(path, host, saved) {
  const runtime = createRuntime({seed: 7, load: async () => saved});
  const wasi = createWasi({print: (fd, line) => console.log(line)});
  let program;
  if (path.endsWith('.json')) {
    program = await linkProgram(file => readFile(resolve(dirname(path), file)), path, wasi, {...runtime.imports, 'snail.runtime.browser.screen': host.imports});
    runProgram(program);
  } else {
    program = await instantiate(await WebAssembly.compile(await readFile(path)), {...wasi.getImportObject(), ...runtime.imports, 'snail.runtime.browser.screen': host.imports});
    wasi.initialize(program);
    program.exports.main();
  }
  await runtime.start(applicationEntry(program)).ready.promise;
  return runtime;
}

// The scheduler may yield an event-loop turn. Wait until the loop consumes
// the input and parks again before inspecting the screen or sending a tick.
async function send(game, ...event) {
  game.send(...event);
  const end = Date.now() + 10000, queue = game.execution.queue;
  while (!queue.waiting && !queue.closed) {
    assert.ok(Date.now() < end, 'the application consumed its queued input');
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  assert.equal(game.execution.queue.closed, false, 'the application is still running');
}

const widget = (host, key) => host.widgets.find(entry => entry.key === key);
const tap = async (game, x, y) => { await send(game, POINTER_DOWN, 1, x, y, 0); await send(game, POINTER_UP, 1, x, y, 0); };

const path = resolve(process.argv[2]);
const host = screen();
const game = await instantiateGame(path, host);
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
await tap(game, 480, 320);
assert.equal(widget(host, 'build-extractor').control, 0, 'the starter crystal is in the middle');
assert.equal(widget(host, 'build-extractor').tone, SUGGESTED);
await send(game, KEY_DOWN, 53, 0, 0, 0);
await send(game, KEY_UP, 53, 0, 0, 0);

// Holding D for a second pans nine cells along the ground; holding W for a
// second pans eighteen, the ground being seen at 30 degrees.
const panned = async (key, milliseconds, shift = 0) => {
  const [x, z] = target(host);
  await send(game, KEY_DOWN, key, shift, 0, 0);
  for (let i = 0; i < milliseconds / 50; i++) await send(game, ELAPSED, 50, 0, 0, 0);
  await send(game, KEY_UP, key, 0, 0, 0);
  await send(game, ELAPSED, 0);
  const [x2, z2] = target(host);
  return Math.hypot(x2 - x, z2 - z);
};
assert.ok(Math.abs(await panned(100, 1000) - 9) < 0.01, 'D pans nine cells a second');
assert.ok(Math.abs(await panned(119, 1000) - 18) < 0.01, 'W pans eighteen cells of ground a second');
assert.ok(Math.abs(await panned(100, 1000, 1) - 9) < 0.01, 'Shift+D pans as D does');
await send(game, KEY_DOWN, 104, 0, 0, 0);
await send(game, KEY_UP, 104, 0, 0, 0);
await send(game, ELAPSED, 0);

// The camera looks at the hub, so a tap in the middle selects it and the
// construction panel offers the hub's buttons.
await tap(game, 480, 320);
assert.ok(widget(host, 'repair'), 'the hub can be repaired');

// Tap around until the construction panel offers an extractor, then build
// it through that button.
let crystal = null;
for (let y = 10; y < 640 && !crystal; y += 20)
  for (let x = 10; x < 960 && !crystal; x += 20) {
    await tap(game, x, y);
    const button = widget(host, 'build-extractor');
    if (button && button.control === 0) crystal = button;
  }
assert.ok(crystal, 'a crystal is in view');
assert.equal(crystal.tone, SUGGESTED, 'the opening suggests the extractor');
assert.equal(spoken('opening-build'), 'Click the *build button* to continue');
await send(game, PRESS, crystal.action, crystal.argument, 0, 0);
assert.equal(widget(host, 'energy').text, '135');
assert.ok(widget(host, 'scavenge'), 'the first extractor is ready at once');
assert.ok(!widget(host, 'opening-title'), 'the banner leaves once the game begins');
await send(game, ELAPSED, 0);
assert.ok(!host.frames.at(-1).batches.some(batch => batch.key === 10), 'and so do the pulsing crystals');
// Each tenth of a second advances the world a tick. The first attack
// raises the alert under the nests.
let alarm = null;
for (let i = 0; i < 3000; i++) {
  await send(game, ELAPSED, 100, 0, 0, 0);
  alarm ??= widget(host, 'attack');
}
assert.ok(alarm, 'an attack raises the alert');
await send(game, ELAPSED, 0);
const readouts = h => ['health', 'energy', 'threat', 'elapsed'].map(key => widget(h, key)?.text);
console.log(readouts(host).join(' | '));

// A drag pans the camera away from the hub.
const resting = host.frames.at(-1).camera;
await send(game, POINTER_DOWN, 1, 480, 320, 0);
await send(game, POINTER_MOVE, 1, 380, 260, 0);
await send(game, POINTER_UP, 1, 380, 260, 0);
await send(game, ELAPSED, 0);
assert.notDeepEqual(host.frames.at(-1).camera, resting, 'the drag moves the camera');

// Save, restore into a fresh instance, and compare what each shows.
const {saved: bytes} = await game.stop();
const other = screen();
const started = performance.now();
const restored = await instantiateGame(path, other, bytes);
const elapsed = performance.now() - started;
assert.deepEqual(readouts(other), readouts(host));
assert.deepEqual(other.frames.at(-1).camera, host.frames.at(-1).camera, 'the restored game looks where the saved one did');
await restored.stop();
console.log(`a journal of ${bytes.length} bytes replays the same colony in ${elapsed.toFixed(0)} ms`);
