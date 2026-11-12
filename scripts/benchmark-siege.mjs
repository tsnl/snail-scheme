#!/usr/bin/env node
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {WASI} from 'node:wasi';

const [baseline, current, countText = '32'] = process.argv.slice(2), count = BigInt(countText);
assert(baseline && current && count > 0n && globalThis.gc);
const modules = [];
for (const [name, path] of [['baseline', baseline], ['current', current]]) {
  const bytes = await readFile(path), wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
  const {instance} = await WebAssembly.instantiate(bytes, wasi.getImportObject());
  wasi.initialize(instance);
  assert.equal(instance.exports.main(), 0);
  modules.push({name, bytes: bytes.length, run: instance.exports.simulate});
}
const checksum = modules[0].run(count), samples = [];
for (const module of modules) {
  for (let warm = 0; warm < 3; ++warm) assert.equal(module.run(count), checksum);
}
for (let repeat = 0; repeat < 11; ++repeat) {
  for (const module of repeat % 2 ? [...modules].reverse() : modules) {
    globalThis.gc();
    const began = performance.now(), result = module.run(count), elapsed = performance.now() - began;
    assert.equal(result, checksum);
    samples.push({variant: module.name, repeat, milliseconds: elapsed});
  }
}
const median = variant => samples.filter(row => row.variant === variant)
  .map(row => row.milliseconds).sort((a, b) => a - b)[5];
console.log(JSON.stringify({node: process.version, colonies: count.toString(), checksum: checksum.toString(),
  modules: modules.map(({name, bytes}) => ({name, bytes})), baseline_ms: median('baseline'),
  current_ms: median('current'), ratio: median('current') / median('baseline'), samples}));
