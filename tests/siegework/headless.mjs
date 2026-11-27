// Builds Siegework's script and runs it without a browser: a recording WebGPU device, keys
// that pan, the opening's banner and pulsing crystals, taps that select
// cells, an order given by clicking the HUD's button, five minutes of play, a drag
// of the camera, and a save replayed through the application loop.
//   node tests/siegework/headless.mjs ROOT
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import assert from 'node:assert/strict';
import {createOverlay, widget as widgetIn, part, text, fire} from '../document.mjs';
import {createFetch} from '../../host/browser/fetch.mjs';
import {createDom} from '../../host/browser/dom.mjs';
import {createGpu} from '../../host/browser/gpu.mjs';
import {fakeGpu, fakeCanvas} from '../fake-gpu.mjs';
import {createRuntime, applicationEntry} from '../../host/browser/runtime.mjs';
import {createWasi, linkModule} from '../../host/browser/load.mjs';

const HIDDEN = 12, ELAPSED = 11, POINTER_UP = 5, POINTER_MOVE = 4, POINTER_DOWN = 3, KEY_DOWN = 1, KEY_UP = 2;

// A device that records each frame, and an overlay for the HUD's document.
function screen() {
  return {gpu: fakeGpu(), overlay: createOverlay()};
}

// The last frame: the batches it drew, by key, and where its camera's eye
// was. A batch k's style is bound as "raster/batch k"; the camera is the
// uniform whose eye follows two 4x4 matrices.
const frame = host => host.gpu.frames.at(-1);
const batches = host => [...new Set(frame(host).groups.map(label => label.match(/batch (\d+)$/)?.[1])
                                                     .filter(Boolean).map(Number))];
const eye = host => [...new Float32Array(frame(host).writes.get('raster/camera').buffer).slice(32, 35)];
// A batch's instances are 80 bytes each, written when its version is new.
const instances = (host, key) => (host.gpu.frames.findLast(f => f.writes.has(`mesh/batch ${key}/instances`))
                                    ?.writes.get(`mesh/batch ${key}/instances`).length ?? 0) / 80;

// Where the camera looked, on the ground: the eye moves as the target does.
const target = host => [eye(host)[0], eye(host)[2]];

// The project's actual package. The smaller application-runtime fixture
// exercises this same lifecycle under both static and dynamic linking.
async function instantiateGame(directory, host, saved) {
  const runtime = createRuntime({seed: 7, load: async () => saved});
  const wasi = createWasi({print: (fd, line) => console.log(line)});
  const program = await linkModule(file => readFile(join(directory, file)), 'main.wasm', wasi,
    {...runtime.imports, 'snail.runtime.browser.fetch': createFetch(runtime).imports,
     'snail.runtime.browser.dom': createDom(host.overlay, runtime).imports,
     'snail.runtime.gpu': createGpu(fakeCanvas(960, 640), runtime, host.gpu.open).imports},
    () => runtime.execution.tasks);
  await runtime.start(applicationEntry(program)).ready.promise;
  return runtime;
}

// The scheduler may yield an event-loop turn. Wait until the loop consumes
// the input and parks again before inspecting the screen or sending a tick.
async function send(game, ...event) {
  game.send(...event);
  await settled(game);
}

async function settled(game) {
  const end = Date.now() + 10000, queue = game.execution.queue;
  while (!queue.waiting && !queue.closed) {
    assert.ok(Date.now() < end, 'the application consumed its queued input');
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  assert.equal(game.execution.queue.closed, false, 'the application is still running');
}

const widget = (host, key) => widgetIn(host.overlay, key);
const enabled = button => button.disabled === false && button.getAttribute('aria-pressed') === null;
const suggested = node => node.getAttribute('data-tone') === 'suggested';
const tap = async (game, x, y) => { await send(game, POINTER_DOWN, 1, x, y, 0); await send(game, POINTER_UP, 1, x, y, 0); };

const root = resolve(process.argv[2]);
const built = await promisify(execFile)(join(root, 'snail-scheme'),
                                        ['build', '--target', 'browser', 'src/apps/siegework/main.scm'], {cwd: root});
const path = built.stdout.trim();
const host = screen();
const game = await instantiateGame(path, host);
assert.deepEqual(batches(host).sort((a, b) => a - b), [1, 3, 4, 5, 6, 7, 8, 9, 10],
                 'terrain, structures, motion, bars, links, cursor, shimmer, beacons and preview');
assert.ok(instances(host, 10) > 0, 'the crystals in sight pulse before the game begins');
assert.equal(text(widget(host, 'opening-title')), 'Siegework');
const spoken = key => part(widget(host, key), 'text').childNodes
  .map(span => span.tagName === 'strong' ? `*${span.textContent}*` : span.textContent).join('');
assert.equal(spoken('opening-crystal'), 'Click the *glowing crystal*');
assert.equal(widget(host, 'how-to-play').getAttribute('href'), 'https://snail-scheme.pages.dev/games/siegework');
assert.ok(instances(host, 1) > 200, 'the explored ground around the hub');
assert.equal(text(widget(host, 'energy')), '160');
assert.equal(text(widget(host, 'nests')), '☆☆☆');
// The camera opens on the starter crystal: a tap in the middle offers the
// suggested extractor.
await tap(game, 480, 320);
assert.ok(enabled(widget(host, 'build-extractor')), 'the starter crystal is in the middle');
assert.ok(suggested(widget(host, 'build-extractor')));
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
    if (button && enabled(button)) crystal = button;
  }
assert.ok(crystal, 'a crystal is in view');
assert.ok(suggested(crystal), 'the opening suggests the extractor');
assert.equal(spoken('opening-build'), 'Click the *build button* to continue');
fire(crystal, 'click');
await settled(game);
assert.equal(text(widget(host, 'energy')), '135');
assert.ok(widget(host, 'scavenge'), 'the first extractor is ready at once');
assert.ok(!widget(host, 'opening-title'), 'the banner leaves once the game begins');
await send(game, ELAPSED, 0);
assert.ok(!batches(host).includes(10), 'and so do the pulsing crystals');
// Each tenth of a second advances the world a tick. The first attack
// raises the alert under the nests.
let alarm = null;
for (let i = 0; i < 3000; i++) {
  await send(game, ELAPSED, 100, 0, 0, 0);
  alarm ??= widget(host, 'attack');
}
assert.ok(alarm, 'an attack raises the alert');
await send(game, ELAPSED, 0);
const readouts = h => ['health', 'energy', 'threat', 'elapsed'].map(key => text(widget(h, key)));
console.log(readouts(host).join(' | '));

// A drag pans the camera away from the hub.
const resting = eye(host);
await send(game, POINTER_DOWN, 1, 480, 320, 0);
await send(game, POINTER_MOVE, 1, 380, 260, 0);
await send(game, POINTER_UP, 1, 380, 260, 0);
await send(game, ELAPSED, 0);
assert.notDeepEqual(eye(host), resting, 'the drag moves the camera');

// Hiding the page saves; restore into a fresh instance, and compare what
// each shows.
await send(game, HIDDEN);
const bytes = game.execution.saved;
const other = screen();
const started = performance.now();
const restored = await instantiateGame(path, other, bytes);
const elapsed = performance.now() - started;
assert.deepEqual(readouts(other), readouts(host));
assert.deepEqual(eye(other), eye(host), 'the restored game looks where the saved one did');
console.log(`a journal of ${bytes.length} bytes replays the same colony in ${elapsed.toFixed(0)} ms`);
game.close();
restored.close();
