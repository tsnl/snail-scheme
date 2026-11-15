#!/usr/bin/env node
// Compile tests/benchmarks/value-model.sld with each compiler, then pass the
// two linked modules here. Instantiation, warm-up and forced GC are untimed.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {cpus} from 'node:os';
import {WASI} from 'node:wasi';

const args = process.argv.slice(2), memory = args[0] === '--memory';
const [baseline, current, repeatsText = '7'] = args;
if (!baseline || !current) throw new Error('usage: benchmark-values.mjs BASE.wasm CURRENT.wasm [REPEATS], or --memory FILE.wasm CASE');
if (!globalThis.gc) throw new Error('run Node with --expose-gc');
const repeats = memory ? 1 : Number(repeatsText), scale = Number(process.env.BENCH_SCALE ?? 1);
assert(Number.isSafeInteger(repeats) && repeats > 0);
assert(Number.isFinite(scale) && scale > 0);
const cases = [
  ['scalar', 20_000_000, n => (n / 97n) * 4656n + (n % 97n) * (n % 97n + 1n) / 2n],
  ['records', 5_000_000, n => n * 3n],
  ['record_list', 300_000, n => n * (n + 1n)],
  ['arrays', 2_000_000, n => n * (n - 1n) / 2n],
];
// Each memory observation runs in a fresh process with just one module.
// This is process RSS, including V8, compilation and warm-up, not live Wasm
// heap size. A baseline/current pair must use the same engine and flags.
if (memory) {
  const selected = cases.find(([name]) => name === args[2]);
  assert(selected, 'unknown memory case');
  const [name, size, expected] = selected, count = BigInt(Math.max(1, Math.round(size * scale)));
  const bytes = await readFile(current);
  const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
  const {instance} = await WebAssembly.instantiate(bytes, wasi.getImportObject());
  wasi.initialize(instance);
  assert.equal(instance.exports.main(), 0);
  for (let repeat = 0; repeat < 4; ++repeat) {
    globalThis.gc();
    assert.equal(instance.exports[name](count), expected(count));
  }
  console.log(JSON.stringify({case: name, count: count.toString(), checksum: expected(count).toString(),
    peak_rss_kib: process.resourceUsage().maxRSS, module_bytes: bytes.length}));
  process.exit(0);
}
const modules = [];
for (const [name, file] of [['baseline', baseline], ['current', current]]) {
  const bytes = await readFile(file);
  const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
  const {instance} = await WebAssembly.instantiate(bytes, wasi.getImportObject());
  wasi.initialize(instance);
  assert.equal(instance.exports.main(), 0);
  modules.push({name, bytes: bytes.length, exports: instance.exports});
}
console.log(JSON.stringify({node: process.version, v8: process.versions.v8,
  platform: process.platform, arch: process.arch, cpu: cpus()[0]?.model, repeats, scale,
  modules: modules.map(({name, bytes}) => ({name, bytes}))}));
for (const [name, size, expected] of cases) {
  const count = BigInt(Math.max(1, Math.round(size * scale)));
  const rows = [];
  for (const module of modules) {
    for (let warm = 0; warm < 3; ++warm) assert.equal(module.exports[name](count), expected(count));
  }
  for (let repeat = 0; repeat < repeats; ++repeat) {
    for (const module of repeat % 2 ? [...modules].reverse() : modules) {
      globalThis.gc();
      const start = performance.now();
      const result = module.exports[name](count);
      const elapsed = performance.now() - start;
      assert.equal(result, expected(count));
      rows.push({variant: module.name, repeat, milliseconds: elapsed});
    }
  }
  const median = variant => {
    const sorted = rows.filter(row => row.variant === variant).map(row => row.milliseconds).sort((a, b) => a - b);
    return sorted[Math.floor(sorted.length / 2)];
  };
  console.log(JSON.stringify({case: name, count: count.toString(), checksum: expected(count).toString(),
    baseline_ms: median('baseline'), current_ms: median('current'),
    ratio: median('current') / median('baseline'), samples: rows}));
}
