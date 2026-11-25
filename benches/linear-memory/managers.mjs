import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {createWasi, instantiate} from '../../host/browser/load.mjs';

// Compile and initialize once. Each timed call receives an already prepared
// scene. Collect heap statistics in separate calls after all timings.
const out = process.argv[2];
if (!out) throw new Error('usage: node managers.mjs OUTPUT_DIRECTORY [--controls | --write-grids]');
async function load(name, dir = '') {
  const module = await WebAssembly.compile(await readFile(join(out, dir, name + '.release.wasm')));
  const wasi = createWasi({print: (_fd, line) => { throw new Error(line); }});
  const instance = await instantiate(module, wasi.getImportObject());
  if (instance.exports._initialize) wasi.initialize(instance);
  return instance.exports;
}
const [snail, checked, raw] = await Promise.all(['managers', 'c-checked', 'c'].map(name => load(name)));
const controls = process.argv[3] === '--controls' ? await Promise.all(
  ['inlined', 'bounds', 'loops', 'bounds-loops', 'bounds-loops/inlined', 'walls', 'directions', 'directions/inlined']
    .map(async name => ({name, module: await load('managers', name)}))) : [];

function measure(workload, cases, repetitions = 1) {
  const samples = cases.map(() => []);
  for (let round = 0; round < 22; round++) {
    for (let j = 0; j < cases.length; j++) {
      const i = (j + round) % cases.length;
      let result;
      const start = performance.now();
      for (let k = 0; k < repetitions; k++) result = cases[i].run();
      const elapsed = (performance.now() - start) / repetitions;
      assert.equal(result, cases[i].expected, cases[i].name);
      if (round >= 7) samples[i].push(elapsed);
    }
  }
  for (let i = 0; i < cases.length; i++) {
    const {name, run, heap, allocationFree} = cases[i];
    const ms = samples[i].sort((a, b) => a - b);
    const stats = {workload, name, medianMs: ms[7], minMs: ms[0], maxMs: ms.at(-1)};
    if (heap) {
      heap['enable-profile'](1);
      const before = heap.collections();
      run();
      stats.allocations = Number(heap.allocations());
      stats.collections = heap.collections() - before;
      heap['enable-profile'](0);
      if (allocationFree) assert.equal(stats.allocations, 0, name);
    }
    console.log(JSON.stringify(stats));
  }
}

function rays(walls, phase, n, seed, timed) {
  const args = [BigInt(walls), BigInt(phase)];
  const shared = snail['prepare-shared'](...args);
  function prepare(module) {
    const scene = module['prepare-walls'](...args), end = BigInt(walls * 4);
    for (const at of [-1n, end - 3n, end, 1n << 32n, (1n << 63n) - 1n])
      assert.throws(() => module['probe-wall'](scene, at), WebAssembly.RuntimeError);
    if (walls) assert.ok(Number.isFinite(module['probe-wall'](scene, end - 4n)));
    return scene;
  }
  const packed = prepare(snail);
  const cChecked = checked['prepare-walls'](...args), cRaw = raw['prepare-walls'](...args);
  const count = BigInt(n);
  const shipping = () => snail['cast-shared'](shared, count, seed);
  const expected = shipping();
  if (walls === 12 && phase === 0 && n === 50_000 && seed === -2.375) assert.equal(expected, 342894);
  const cases = [{name: 'Snail shipping', run: shipping, heap: snail, expected}];
  for (const [mode, label] of ['dense', 'WallId', 'packed slots'].entries()) {
    cases.push({name: 'Snail ' + label, run: () => snail.cast(packed, count, seed, mode),
      heap: snail, allocationFree: true, expected});
  }
  for (const [kind, module, scene] of [['checked', checked, cChecked], ['unchecked', raw, cRaw]]) {
    for (const [mode, label] of ['dense', 'WallId'].entries()) {
      cases.push({name: 'C ' + kind + ' ' + label, run: () => module.cast(scene, count, seed, mode), expected});
    }
  }
  for (const {name, module} of controls) {
    const scene = prepare(module);
    for (const [mode, label] of ['dense', 'WallId'].entries()) {
      cases.push({name: name + ' ' + label, run: () => module.cast(scene, count, seed, mode),
        heap: module, allocationFree: true, expected});
    }
  }
  for (const test of cases) assert.equal(test.run(), expected, test.name);
  if (timed) measure({rays: n, walls, phase, seed, checksum: expected}, cases);
}

const side = 80, cells = side * side;
function readField(module, grid) {
  return Array.from({length: cells}, (_, i) => Number(module['grid-distance'](grid, BigInt(i))));
}

function fields(seed) {
  const grid = snail['prepare-grid'](BigInt(seed)), hub = snail['grid-hub'](grid);
  const cChecked = checked['prepare-grid'](), cRaw = raw['prepare-grid']();
  for (let i = 0n; i < BigInt(cells); i++) {
    const open = snail['grid-open'](grid, i);
    checked['set-open'](cChecked, i, open);
    raw['set-open'](cRaw, i, open);
  }
  snail['shipping-field'](grid, hub);
  const fromHub = readField(snail, grid);
  const furthest = BigInt(fromHub.indexOf(Math.max(...fromHub)));
  const goals = [hub, furthest];
  if (process.argv[3] === '--write-grids') {
    snail['shipping-field'](grid, furthest);
    const open = Array.from({length: cells}, (_, i) => snail['grid-open'](grid, BigInt(i)));
    writeFileSync(join(out, 'grid-' + seed + '.json'), JSON.stringify({
      open, goals: goals.map(Number), fields: [fromHub, readField(snail, grid)],
    }));
    return;
  }
  const cases = [
    ['Snail shipping', snail, grid, 'shipping-field'],
    ['Snail queue', snail, grid, 'packed-field'],
    ['C checked queue', checked, cChecked, 'packed-field'],
    ['C unchecked queue', raw, cRaw, 'packed-field'],
    ...controls.map(({name, module}) => [name, module, module['prepare-grid'](BigInt(seed)), 'packed-field']),
  ];
  for (const [, module, storage, fill] of cases) {
    if (module === raw || fill === 'shipping-field') continue;
    for (const i of [-1n, BigInt(cells), 1n << 32n, -(1n << 63n)]) {
      assert.throws(() => module['grid-distance'](storage, i), WebAssembly.RuntimeError);
      assert.throws(() => module[fill](storage, i), WebAssembly.RuntimeError);
    }
  }
  // Include edge goals in the correctness check, also when a corner is closed.
  for (const goal of [...goals, 0n, BigInt(cells - 1)]) {
    snail['shipping-field'](grid, goal);
    const expected = readField(snail, grid);
    for (const [name, module, storage, fill] of cases) {
      module[fill](storage, goal);
      assert.deepEqual(readField(module, storage), expected, name + ' from slot ' + goal);
    }
  }
  const distance = fromHub[Number(furthest)];
  assert.ok(distance > 0);
  measure({game: 'Siegework distance field', seed, fields: goals.length,
    reachable: fromHub.filter(d => d >= 0).length}, cases.map(([name, module, storage, fill]) => ({
      name, heap: module.allocations && module, allocationFree: fill === 'packed-field', expected: BigInt(distance) * 2n,
      run() {
        module[fill](storage, hub);
        const there = module['grid-distance'](storage, furthest);
        module[fill](storage, furthest);
        return there + module['grid-distance'](storage, hub);
      },
    })), 8);
}

if (process.argv[3] !== '--write-grids') {
  for (const [walls, phase, n, seed] of [[0, 0, 5, 1], [1, 7, 0, 0], [1, 3, 17, 5.5],
                                        [17, 9, 31, -17.5]]) rays(walls, phase, n, seed, false);
  rays(12, 0, 50_000, -2.375, true);
  rays(96, 3, 12_500, 1.125, true);
}
fields(1);
fields(4);
