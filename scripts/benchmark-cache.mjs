#!/usr/bin/env node
// Compile tests/benchmarks/function-cache.sld first. No build runs during timing.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {cpus} from 'node:os';
import {WASI} from 'node:wasi';

assert(globalThis.gc, 'run node --expose-gc');
const bytes = readFileSync(process.argv[2]);
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
const {instance} = await WebAssembly.instantiate(bytes, wasi.getImportObject());
wasi.initialize(instance);
assert.equal(instance.exports.main(), 0);
const groups = [
  {names: ['plain_expensive', 'cached_expensive', 'lru_expensive'], count: 50000n},
  {names: ['plain_cheap', 'cached_cheap'], count: 50000n},
  {names: ['plain_misses', 'cached_misses'], count: 20000n},
];
const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: cpus()[0].model, module_sha256: createHash('sha256').update(bytes).digest('hex'),
  module_bytes: bytes.length, groups: []};
for (const {names, count} of groups) {
  const expected = instance.exports[names[0]](count);
  for (let warm = 0; warm < 10; ++warm) for (const name of names)
    assert.equal(instance.exports[name](count), expected);
  const samples = [];
  for (let repeat = 0; repeat < 21; ++repeat) {
    for (const name of repeat % 2 ? [...names].reverse() : names) {
      globalThis.gc();
      const start = performance.now();
      const result = instance.exports[name](count);
      const milliseconds = performance.now() - start;
      assert.equal(result, expected);
      samples.push({repeat, name, milliseconds});
    }
  }
  const medians_ms = Object.fromEntries(names.map(name => [name,
    samples.filter(s => s.name === name).map(s => s.milliseconds).sort((a, b) => a - b)[10]]));
  report.groups.push({count: String(count), checksum: String(expected), medians_ms, samples});
}
console.log(JSON.stringify(report, null, 2));
