#!/usr/bin/env node
// Compare the landed Java-style compiler with shared lazy runtime values.
// Both source languages are identical for these fixtures; no translation or bootstrap.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, readFileSync, statSync, writeFileSync} from 'node:fs';
import {cpus} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {WASI} from 'node:wasi';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const median = values => values.toSorted((a, b) => a - b)[Math.floor(values.length / 2)];

// A separate affinity-pinned process measures only calls into warmed modules.
if (args[0] === '--reads') {
  assert(globalThis.gc);
  async function fresh(module) {
    const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
    const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
    wasi.initialize(instance);
    assert.equal(instance.exports.main(), 0);
    return instance.exports;
  }
  const modules = [];
  for (const [index, file] of args.slice(1).entries()) {
    const module = await WebAssembly.compile(readFileSync(file));
    modules.push({name: index ? 'current' : 'baseline', module, exports: await fresh(module)});
  }
  const report = [];
  for (const [name, count, value] of [['scalar-read', 20000000n, 2016n], ['aggregate-read', 100000n, 63n]]) {
    for (const module of modules) for (let warm = 0; warm < 3; ++warm)
      assert.equal(module.exports[name](count), count * value);
    const samples = [];
    for (let repeat = 0; repeat < 21; ++repeat) {
      for (const module of repeat % 2 ? [...modules].reverse() : modules) {
        globalThis.gc();
        const start = performance.now(), result = module.exports[name](count);
        const milliseconds = performance.now() - start;
        assert.equal(result, count * value);
        samples.push({variant: module.name, repeat, milliseconds});
      }
    }
    const times = variant => median(samples.filter(s => s.variant === variant).map(s => s.milliseconds));
    report.push({case: name, count: String(count), checksum: String(count * value),
      baseline_ms: times('baseline'), current_ms: times('current'),
      ratio: times('current') / times('baseline'), samples});
  }
  // Keep module instantiation untimed, but force a fresh cache on every call.
  // Warm the engine using discarded instances; never warm the measured cache.
  for (const module of modules) for (let warm = 0; warm < 3; ++warm)
    assert.equal((await fresh(module.module))['first-load'](), 199990000n);
  const samples = [];
  for (let repeat = 0; repeat < 21; ++repeat) {
    for (const module of repeat % 2 ? [...modules].reverse() : modules) {
      globalThis.gc();
      const entry = await fresh(module.module);
      const start = performance.now(), value = entry['first-load']();
      const milliseconds = performance.now() - start;
      assert.equal(value, 199990000n);
      samples.push({variant: module.name, repeat, milliseconds});
    }
  }
  const times = variant => median(samples.filter(s => s.variant === variant).map(s => s.milliseconds));
  report.push({case: 'first-load', count: '20000', checksum: '199990000',
    baseline_ms: times('baseline'), current_ms: times('current'), samples});
  console.log(JSON.stringify(report));
  process.exit(0);
}

const [baseRoot, baseCompiler, compiler, outputArg] = args;
assert(baseRoot && baseCompiler && compiler,
  'usage: benchmark-lazy-values.mjs BASE_ROOT BASE_COMPILER CURRENT_COMPILER [OUTPUT]');
const output = resolve(outputArg ?? join(root, 'build/migration/lazy-benchmark'));
mkdirSync(join(output, 'generated'), {recursive: true});
const cpu = process.env.BENCH_CPU ?? '2';
assert(/^\d+$/.test(cpu));
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command}: ${result.stderr || result.stdout}`);
  return result.stdout;
}
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const artifact = file => ({bytes: statSync(file).size, sha256: hash(file)});
const variants = [
  {name: 'baseline', root: resolve(baseRoot), compiler: resolve(baseCompiler)},
  {name: 'current', root, compiler: resolve(compiler)},
];
const sources = {values: 'value-model.sld', siege: 'siege.sld', lazy: 'lazy-values.sld'};
const runtime = join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm');
const compileArgs = (v, source, target) => ['--no-warnings', join(root, 'host/native/run-snail.mjs'),
  v.compiler, 'wat', source, target, join(output, 'generated'),
  join(v.root, 'apps/siegework/src'), join(v.root, 'src')];
const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: cpus()[Number(cpu)]?.model, affinity: cpu, platform: process.platform, arch: process.arch,
  harness: artifact(fileURLToPath(import.meta.url)), scalar_runtime: artifact(runtime),
  drivers: Object.fromEntries(['benchmark-values.mjs', 'benchmark-siege.mjs'].map(name =>
    [name, artifact(join(root, 'scripts', name))])),
  sources: Object.fromEntries(Object.entries(sources).map(([key, name]) =>
    [key, artifact(join(root, 'tests/benchmarks', name))])), variants: []};
for (const variant of variants) {
  const entry = {name: variant.name, commit: run('git', ['rev-parse', 'HEAD'], variant.root).trim(),
    compiler: artifact(variant.compiler), artifacts: {}};
  for (const [kind, name] of Object.entries(sources)) {
    const prefix = join(output, `${variant.name}-${kind}`);
    run('node', compileArgs(variant, join(root, 'tests/benchmarks', name), `${prefix}.wat`), variant.root);
    run(join(root, 'build/native-snail/release/snail'), ['link', `${prefix}.wat`, runtime, `${prefix}.wasm`]);
    variant[kind] = `${prefix}.wasm`;
    entry.artifacts[kind] = artifact(variant[kind]);
  }
  report.variants.push(entry);
}
const pinnedNode = script => ['-c', cpu, 'node', '--no-warnings', '--expose-gc', join(root, script)];
report.runtime = run('taskset', [...pinnedNode('scripts/benchmark-values.mjs'), variants[0].values,
  variants[1].values, '21']).trim().split('\n').map(JSON.parse);
report.siege = JSON.parse(run('taskset', [...pinnedNode('scripts/benchmark-siege.mjs'),
  variants[0].siege, variants[1].siege, '32']));
report.reads = JSON.parse(run('taskset', [...pinnedNode('scripts/benchmark-lazy-values.mjs'),
  '--reads', variants[0].lazy, variants[1].lazy]));
report.compilation = [];
for (const fixture of ['values', 'lazy']) {
  for (let repeat = 0; repeat < 9; ++repeat) {
    for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
      const timing = join(output, 'time.txt'), target = join(output, `${variant.name}-timed.wat`);
      run('time', ['-f', '%e %U %S %M', '-o', timing, 'taskset', '-c', cpu, 'node',
        ...compileArgs(variant, join(root, 'tests/benchmarks', sources[fixture]), target)], variant.root);
      const [elapsed_s, user_s, system_s, peak_rss_kib] = readFileSync(timing, 'utf8').trim().split(' ').map(Number);
      report.compilation.push({fixture, variant: variant.name, repeat, elapsed_s, user_s, system_s, peak_rss_kib});
    }
  }
}
writeFileSync(join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log(join(output, 'results.json'));
