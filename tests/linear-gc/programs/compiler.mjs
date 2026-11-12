// One real compiler invocation. Run fresh processes for timing and a separate
// --profile process for allocation/GC counters; the compiler needs only WASI.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {exiting} from '../../../host/native/wasi.mjs';

const parameters = process.argv.slice(2);
let profiling = false, mode = 'wat';
while (parameters[0]?.startsWith('--')) {
  const flag = parameters.shift();
  if (flag === '--profile') profiling = true;
  else if (flag === '--schema') mode = 'schema';
  else throw new Error(`unknown compiler measurement flag: ${flag}`);
}
const [artifact, variant, entry, destination, ...directories] = parameters;
assert.ok(destination, 'compiler.mjs [--profile] [--schema] COMPILER LABEL SOURCE OUTPUT [LIBRARY_DIRECTORY ...]');
const scratch = mkdtempSync(join(tmpdir(), 'snail-compile-bench-'));
try {
  const filename = resolve(artifact), source = resolve(entry), output = resolve(destination);
  mkdirSync(dirname(output), {recursive: true});
  const bytes = readFileSync(filename), start = performance.now();
  const module = new WebAssembly.Module(bytes), compile_ms = performance.now() - start;
  assert.ok(WebAssembly.Module.imports(module).every(imported => imported.module === 'wasi_snapshot_preview1'));
  const wasi = exiting(new WASI({version: 'preview1', args: [filename, mode, source, output, scratch, ...directories.map(path => resolve(path))],
    env: {SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}}));
  const instantiateStart = performance.now();
  const instance = new WebAssembly.Instance(module, wasi.getImportObject());
  wasi.initialize(instance);
  const initialize_ms = performance.now() - instantiateStart, api = instance.exports;
  const initialCollections = api['snail:gc/collections']?.() ?? 0;
  if (profiling) api['snail:gc/profile']?.(1);
  const runStart = performance.now(), result = api.main();
  const execute_ms = performance.now() - runStart;
  assert.equal(Number(result), 0);
  if (api['snail:gc/checkpoint']) assert.equal(api['snail:gc/checkpoint'](), 0);
  const stats = {};
  for (const name of ['collections', 'heap-bytes', 'root-words', 'profile-allocations', 'profile-bytes', 'pause-ns', 'longest-pause-ns']) {
    if (api[`snail:gc/${name}`]) {
      const value = api[`snail:gc/${name}`]();
      stats[name] = (typeof value === 'number' ? value >>> 0 : value).toString();
    }
  }
  if (stats.collections) stats.collections = String(Number(stats.collections) - initialCollections);
  const generated = readFileSync(output);
  console.log(JSON.stringify({variant, mode, profiling, source, node: process.version, v8: process.versions.v8,
    flags: process.execArgv, compiler_sha256: createHash('sha256').update(bytes).digest('hex'),
    compiler_bytes: bytes.length, output_bytes: generated.length,
    output_sha256: createHash('sha256').update(generated).digest('hex'),
    compile_ms, initialize_ms, execute_ms, linear_memory_bytes: api.memory.buffer.byteLength,
    max_rss_kib: process.resourceUsage().maxRSS, stats}, null, 2));
} finally { rmSync(scratch, {recursive: true}); }
