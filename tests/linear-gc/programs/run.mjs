// One fresh process per artifact. Timing excludes loading and instantiation;
// collection and allocation inside each batch are included. Profile separately.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import os from 'node:os';
import {createWasi, instantiate} from '../../../host/browser/load.mjs';
import {hostExports} from '../../../host/browser/memory.mjs';

const [path, variant = 'unnamed'] = process.argv.slice(2);
const bytes = await readFile(path), compileStart = performance.now();
const module = new WebAssembly.Module(bytes), compileMs = performance.now() - compileStart;
const wasi = createWasi({print(fd, line) { if (fd === 2) console.error(line); }});
const start = performance.now();
const instance = await instantiate(module, wasi.getImportObject());
wasi.initialize(instance);
const api = hostExports(instance.exports), gc = instance.exports;
api.main();
const initializeMs = performance.now() - start;
const work = {'arithmetic': 1_000_000, 'rooted-calls': 300_000, lists: 50_000,
              arrays: 100_000, closures: 10_000, effects: 2_000};
const workloads = [];
for (const [name, count] of Object.entries(work)) {
  const call = () => api[name](BigInt(count));
  const checksum = call();
  for (let i = 0; i < 32; i++) assert.equal(call(), checksum);
  const samples = Array.from({length: 9}, () => {
    const start = process.hrtime.bigint();
    const answers = Array.from({length: 32}, call);
    const elapsed = Number(process.hrtime.bigint() - start) / 32e6;
    for (const answer of answers) assert.equal(answer, checksum);
    return elapsed;
  });
  let profile = null;
  if (gc['snail:gc/profile']) {
    const collections = gc['snail:gc/collections']();
    gc['snail:gc/profile'](1);
    for (let i = 0; i < 9; i++) assert.equal(call(), checksum);
    profile = Object.fromEntries(['profile-allocations', 'profile-bytes', 'pause-ns', 'longest-pause-ns']
      .map(key => [key, gc[`snail:gc/${key}`]().toString()]));
    profile.collections = gc['snail:gc/collections']() - collections;
    profile.batches = 9;
    gc['snail:gc/profile'](0);
  }
  workloads.push({name, count, checksum: checksum.toString(), samples_ms: samples,
    median_ms: [...samples].sort((a, b) => a - b)[4], profile,
    linear_memory_bytes: gc.memory.buffer.byteLength});
}
console.log(JSON.stringify({variant, node: process.version, v8: process.versions.v8,
  cpu: os.cpus()[0].model, flags: process.execArgv, sha256: createHash('sha256').update(bytes).digest('hex'),
  wasm_bytes: bytes.length, compile_ms: compileMs, initialize_ms: initializeMs,
  samples: 9, calls_per_sample: 32, warmup_calls: 32,
  max_rss_kib: process.resourceUsage().maxRSS, workloads}, null, 2));
