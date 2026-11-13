#!/usr/bin/env node
// Compare two complete revisions. Build both compilers first; this driver never bootstraps.
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

if (args[0] === '--nested') {
  assert(globalThis.gc);
  const variants = [];
  for (const [index, file] of args.slice(1).entries()) {
    const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
    const {instance} = await WebAssembly.instantiate(readFileSync(file), wasi.getImportObject());
    wasi.initialize(instance);
    assert.equal(instance.exports.main(), 0);
    variants.push({name: index ? 'current' : 'baseline', measure: instance.exports.measure});
  }
  const cases = [];
  for (const depth of [32n, 128n, 512n]) {
    const iterations = 10n, checksum = (8n * depth + 8n) * iterations, samples = [];
    for (let warm = 0; warm < 10; ++warm) for (const variant of variants)
      assert.equal(variant.measure(depth, iterations), checksum);
    for (let repeat = 0; repeat < 21; ++repeat) {
      for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
        globalThis.gc();
        const start = performance.now(), result = variant.measure(depth, iterations);
        const milliseconds = performance.now() - start;
        assert.equal(result, checksum);
        samples.push({variant: variant.name, repeat, milliseconds});
      }
    }
    const time = name => median(samples.filter(s => s.variant === name).map(s => s.milliseconds));
    cases.push({depth: String(depth), iterations: String(iterations), checksum: String(checksum),
      baseline_ms: time('baseline'), current_ms: time('current'), samples});
  }
  console.log(JSON.stringify(cases));
  process.exit(0);
}

const [baselineArg, baseCompilerArg, currentCompilerArg, outputArg] = args;
assert(baselineArg && baseCompilerArg && currentCompilerArg,
  'usage: benchmark-cuts.mjs BASE_ROOT BASE_COMPILER CURRENT_COMPILER [OUTPUT]');
const output = resolve(outputArg ?? join(root, 'build/migration/cuts'));
mkdirSync(join(output, 'generated'), {recursive: true});
const cpu = process.env.BENCH_CPU ?? '2';
assert(/^\d+$/.test(cpu));
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command}: ${result.stderr || result.stdout}`);
  return result.stdout;
}
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const artifact = file => ({bytes: statSync(file).size, sha256: hash(readFileSync(file))});
const runtime = join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm');
const variants = [
  {name: 'baseline', root: resolve(baselineArg), compiler: resolve(baseCompilerArg)},
  {name: 'current', root, compiler: resolve(currentCompilerArg)},
];
const fixtures = {values: 'value-model', siege: 'siege', nested: 'reference-counting', frames: 'frame-ownership'};
const compileArgs = (v, source, target) => ['--no-warnings', join(root, 'host/native/run-snail.mjs'),
  v.compiler, 'wat', source, target, join(output, 'generated'),
  join(v.root, 'apps/siegework/src'), join(v.root, 'src')];
const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: cpus()[Number(cpu)]?.model, affinity: cpu, platform: process.platform, arch: process.arch,
  harness: artifact(fileURLToPath(import.meta.url)), scalar_runtime: artifact(runtime), variants: []};
for (const variant of variants) {
  const entry = {name: variant.name, commit: run('git', ['rev-parse', 'HEAD'], variant.root).trim(),
    tree: run('git', ['rev-parse', 'HEAD^{tree}'], variant.root).trim(),
    changes_sha256: hash(run('git', ['diff', 'HEAD', '--binary'], variant.root)),
    compiler: artifact(variant.compiler), artifacts: {}, sources: {}};
  variant.sources = {};
  for (const [kind, name] of Object.entries(fixtures)) {
    // The IR fixture uses each revision's own constructor shapes. Other inputs are identical.
    const source = join(kind === 'nested' ? variant.root : root, 'tests/benchmarks', `${name}.sld`);
    const prefix = join(output, `${variant.name}-${kind}`);
    run('node', compileArgs(variant, source, `${prefix}.wat`), variant.root);
    run(join(root, 'build/native-snail/release/snail'), ['link', `${prefix}.wat`, runtime, `${prefix}.wasm`]);
    variant[kind] = `${prefix}.wasm`;
    variant.sources[kind] = source;
    entry.artifacts[kind] = artifact(variant[kind]);
    entry.sources[kind] = artifact(source);
  }
  report.variants.push(entry);
}
const pinnedNode = script => ['-c', cpu, 'node', '--no-warnings', '--expose-gc', join(root, 'scripts', script)];
report.runtime = run('taskset', [...pinnedNode('benchmark-values.mjs'), variants[0].values,
  variants[1].values, '21']).trim().split('\n').map(JSON.parse);
report.siege = JSON.parse(run('taskset', [...pinnedNode('benchmark-siege.mjs'), variants[0].siege, variants[1].siege, '32']));
report.nested = JSON.parse(run('taskset', [...pinnedNode('benchmark-cuts.mjs'), '--nested', variants[0].nested, variants[1].nested]));
report.frames = JSON.parse(run('taskset', [...pinnedNode('benchmark-frame-ownership.mjs'), '--measure', variants[0].frames, variants[1].frames]));
report.memory = [];
for (let repeat = 0; repeat < 5; ++repeat) {
  for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
    for (const kind of ['scalar', 'records', 'record_list', 'vectors']) {
      const sample = JSON.parse(run('taskset', [...pinnedNode('benchmark-values.mjs'), '--memory', variant.values, kind]));
      report.memory.push({variant: variant.name, repeat, ...sample});
    }
  }
}
report.compilation = [];
for (const fixture of ['values', 'siege', 'nested']) {
  for (let repeat = 0; repeat < 9; ++repeat) {
    for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
      const timing = join(output, 'time.txt'), target = join(output, `${variant.name}-timed.wat`);
      run('time', ['-f', '%e %U %S %M', '-o', timing, 'taskset', '-c', cpu, 'node',
        ...compileArgs(variant, variant.sources[fixture], target)], variant.root);
      const [elapsed_s, user_s, system_s, peak_rss_kib] = readFileSync(timing, 'utf8').trim().split(' ').map(Number);
      report.compilation.push({fixture, variant: variant.name, repeat, elapsed_s, user_s, system_s, peak_rss_kib});
    }
  }
}
writeFileSync(join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log(join(output, 'results.json'));
