// Instrumented retention diagnostic, not an FPS benchmark or natural playtest.
// A valid dense colony/crowd is restored every 60 ticks to sustain active load. Each
// intervening tick executes the real Scheme reducer, validator and serializer.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {RunRecording} from '../../src/application/recording.mjs';
import {colony, colonyWords, at, pixelAt, routeCell, restoreColony} from './colony-state.mjs';

function grown(world) {
  world.started = true; world.produced += 100000; world.delivered += 100000; world.ore += 100000;
  for (let y = 11; y <= 30 && world.buildings.length < 64; y++) for (let x = 1; x <= 20 && world.buildings.length < 64; x++) {
    if ((x >= 7 && x <= 9 && y >= 21 && y <= 23) || (x === 12 && y === 20)) continue;
    const point = at(world, x, y), aim = pixelAt(world, x, y);
    world.buildings.push({id: world.nextId++, kind: 3, ...point, level: 1, hp: 90, stock: 0, stage: 2,
      cooldown: 0, aimX: aim.x, aimY: aim.y, armed: 0, source: 0, moveX: -1, moveY: -1});
    world.surveys.push({...point, radius: 7}); world.spent += 25; world.ore -= 25;
  }
  while (world.bots.length < 64) {
    world.bots.push({...world.bots[0], id: world.nextId++, path: []}); world.spent += 25; world.ore -= 25;
  }
  return world;
}
function crowd(world) {
  const path = Array.from({length: 12}, (_, i) => routeCell(world, 19 - i, 22));
  for (let i = 0; i < 128; i++) world.enemies.push({id: world.nextId++, ...pixelAt(world, 20, 22), hp: 80,
    kind: 0, rank: 0, burrower: false, target: 0, path: [...path]});
  return world;
}
const directory = resolve(process.argv[2]), ticks = Number(process.argv[3] ?? 6000);
const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'))), bytes = readFileSync(join(directory, manifest.module));
const runtime = new ReducerRuntime(); await runtime.replace(runtime.prepare(bytes, manifest));
await runtime.initialize(1); await runtime.initialize(2);
const fixture = crowd(grown(colony(runtime.snapshot(1)))); await restoreColony(runtime, fixture);
const recording = RunRecording.start(runtime), samples = [], transition = runtime.command('match', 'advance');
let maximumWorldBytes = 0, advancedTicks = 0, previousTick = fixture.tick;
runtime.recording = {capture(r, event) {
  const start = performance.now(); recording.capture(r, event); samples.push(performance.now() - start);
  maximumWorldBytes = Math.max(maximumWorldBytes, r.stores.get(1).byteLength);
}, fail(message) { recording.fail(message); }};
const start = performance.now();
for (let tick = 0; tick < ticks; tick++) {
  if (tick && tick % 60 === 0) { fixture.tick = tick; await runtime.restore(1, colonyWords(fixture)); previousTick = tick; }
  await runtime.dispatch(1, transition); assert.equal(recording.reason, '');
  const now = runtime.inspect(0); advancedTicks += now - previousTick; previousTick = now;
}
samples.sort((a, b) => a - b);
const result = {fixture: '64 depots, 64 workers, 128 enemies; real 60-tick windows separated by fixture restores',
  generation: manifest.generation, advanceCommands: ticks, advancedTicks, noOpCommands: ticks - advancedTicks,
  retainedFirstTick: colony(recording.snapshot(recording.first)).tick, maximumWorldBytes, elapsedMilliseconds: performance.now() - start,
  captureMedianMs: samples[Math.floor(samples.length / 2)], captureP95Ms: samples[Math.floor(samples.length * .95)],
  captureMaxMs: samples.at(-1), ...recording.stats()};
console.log(JSON.stringify(result, null, 2));
assert.equal(advancedTicks, ticks, 'every measured command must actually advance the dense World');
if (process.argv[4]) writeFileSync(process.argv[4], new Uint8Array(await recording.exportBlob().arrayBuffer()));
await runtime.close();
