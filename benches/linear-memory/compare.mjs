// Compare previously built modules in one process and engine. Alternate
// their order and time only the exported kernel after warming up.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {createWasi, instantiate} from '../../host/browser/load.mjs';

const paths = process.argv.slice(2);
if (paths.length < 2) throw new Error('usage: node compare.mjs FIRST.wasm SECOND.wasm [MORE.wasm...]');
const runs = [];
for (const path of paths) {
  const module = await WebAssembly.compile(await readFile(path));
  const wasi = createWasi({print: (fd, line) => { throw new Error(line); }});
  const instance = await instantiate(module, wasi.getImportObject());
  if (instance.exports._initialize) wasi.initialize(instance);
  runs.push({path, cast: instance.exports['cast-rays'], samples: []});
}
const count = 50_000n, seed = -2.375;
const checksum = 342_894;
for (let round = 0; round < 14; round++) {
  for (let i = 0; i < runs.length; i++) {
    const run = runs[(round + i) % runs.length];
    const start = performance.now();
    const result = run.cast(count, seed);
    const elapsed = performance.now() - start;
    assert.equal(result, checksum, run.path + ' checksum');
    if (round >= 3) run.samples.push(elapsed);
  }
}
for (const run of runs) {
  run.samples.sort((a, b) => a - b);
  console.log(JSON.stringify({path: run.path, rays: Number(count), checksum,
    medianMs: run.samples[5], minMs: run.samples[0], maxMs: run.samples.at(-1)}));
}
