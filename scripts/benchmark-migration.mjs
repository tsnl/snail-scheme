#!/usr/bin/env node
// Serial measurements from two existing self-hosted compilers. This script
// never bootstraps either checkout; both variants link the current scalar runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, readFileSync, statSync, writeFileSync} from 'node:fs';
import {cpus} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [baseRootArg, baseCompilerArg, compilerArg, outputArg] = process.argv.slice(2);
assert(baseRootArg && baseCompilerArg && compilerArg,
  'usage: benchmark-migration.mjs BASE_ROOT BASE_COMPILER CURRENT_COMPILER [OUTPUT]');
const base = resolve(baseRootArg), output = resolve(outputArg ?? join(root, 'build/migration/benchmarks/final'));
const cpu = process.env.BENCH_CPU ?? '2';
assert(/^\d+$/.test(cpu), 'BENCH_CPU must name one CPU');
mkdirSync(join(output, 'generated'), {recursive: true});
const variants = [
  {name: 'baseline', root: base, compiler: resolve(baseCompilerArg)},
  {name: 'current', root, compiler: resolve(compilerArg)},
];
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command}: ${result.stderr || result.stdout}`);
  return result.stdout;
}
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const nodeArgs = ['--no-warnings', join(root, 'host/native/run-snail.mjs')];
function compileArgs(variant, source, target, directories = []) {
  return [...nodeArgs, variant.compiler, 'wat', source, target,
    join(output, 'generated'), ...directories, join(variant.root, 'src')];
}
function compile(variant, fixture, source, directories = []) {
  const prefix = join(output, `${variant.name}-${fixture}`);
  run('node', compileArgs(variant, source, `${prefix}.wat`, directories), variant.root);
  run(join(root, 'build/native-snail/release/snail'), ['link', `${prefix}.wat`,
    join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm'), `${prefix}.wasm`]);
  return `${prefix}.wasm`;
}

const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  platform: process.platform, arch: process.arch, cpu: cpus()[Number(cpu)]?.model, affinity: cpu,
  harness: {commit: run('git', ['rev-parse', 'HEAD']).trim(),
    sha256: hash(fileURLToPath(import.meta.url))},
  variants: variants.map(v => ({name: v.name, commit: run('git', ['rev-parse', 'HEAD'], v.root).trim(),
    compiler_sha256: hash(v.compiler), compiler_bytes: statSync(v.compiler).size})),
  scalar_runtime_sha256: hash(join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm'))};
const valueSource = readFileSync(join(root, 'tests/benchmarks/value-model.sld'), 'utf8');
const legacyValues = valueSource.replaceAll('make-vector', 'make-array')
  .replaceAll('vector-set!', 'array-set!').replaceAll('vector-ref', 'array-ref');
writeFileSync(join(output, 'legacy-values.sld'), legacyValues);
for (const variant of variants) {
  console.error(`Compiling ${variant.name} workloads`);
  variant.valueSource = variant.name === 'baseline' ? join(output, 'legacy-values.sld') : join(root, 'tests/benchmarks/value-model.sld');
  variant.values = compile(variant, 'values', variant.valueSource);
  variant.siege = compile(variant, 'siege', join(root, 'tests/benchmarks/siege.sld'),
    [join(variant.root, 'apps/siegework/src')]);
  report.variants.find(entry => entry.name === variant.name).artifacts =
    Object.fromEntries(['values', 'siege'].map(name => [name,
      {sha256: hash(variant[name]), bytes: statSync(variant[name]).size}]));
  report.variants.find(entry => entry.name === variant.name).value_source_sha256 = hash(variant.valueSource);
}

console.error('Measuring warmed runtime and simulation');
report.runtime = run('taskset', ['-c', cpu, 'node', '--no-warnings', '--expose-gc',
  join(root, 'scripts/benchmark-values.mjs'), variants[0].values, variants[1].values, '21'])
  .trim().split('\n').map(JSON.parse);
report.siege = JSON.parse(run('taskset', ['-c', cpu, 'node', '--no-warnings', '--expose-gc',
  join(root, 'scripts/benchmark-siege.mjs'), variants[0].siege, variants[1].siege, '32']));

console.error('Measuring process memory');
report.memory = [];
for (let repeat = 0; repeat < 5; ++repeat) {
  for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
    for (const kind of ['scalar', 'records', 'record_list', 'vectors']) {
      const sample = JSON.parse(run('taskset', ['-c', cpu, 'node', '--no-warnings', '--expose-gc',
        join(root, 'scripts/benchmark-values.mjs'), '--memory', variant.values, kind]));
      report.memory.push({variant: variant.name, repeat, ...sample});
    }
  }
}
console.error('Measuring cold compilation');
report.compilation = [];
for (let repeat = 0; repeat < 7; ++repeat) {
  for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
    const timing = join(output, 'time.txt'), target = join(output, `${variant.name}-timed.wat`);
    run('time', ['-f', '%e %U %S %M', '-o', timing, 'taskset', '-c', cpu, 'node',
      ...compileArgs(variant, variant.valueSource, target)], variant.root);
    const [elapsed_s, user_s, system_s, peak_rss_kib] = readFileSync(timing, 'utf8').trim().split(' ').map(Number);
    report.compilation.push({variant: variant.name, repeat, elapsed_s, user_s, system_s, peak_rss_kib,
      wat_bytes: statSync(target).size});
  }
}
writeFileSync(join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log(join(output, 'results.json'));
