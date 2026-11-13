#!/usr/bin/env node
// Compare identical suspended-owner workloads, with separate resume/cancel paths.
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

if (args[0] === '--measure') {
  assert(globalThis.gc);
  const variants = [];
  for (const [index, file] of args.slice(1).entries()) {
    const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
    const {instance} = await WebAssembly.instantiate(readFileSync(file), wasi.getImportObject());
    wasi.initialize(instance);
    assert.equal(instance.exports.main(), 0);
    variants.push({name: index ? 'second' : 'first', measure: instance.exports.measure});
  }
  const cases = [];
  for (const cancel of [false, true]) for (const depth of [1n, 16n, 128n]) {
    const count = 1000n, checksum = count * (cancel ? 1n : depth + 1n), samples = [];
    for (let warm = 0; warm < 10; ++warm) for (const variant of variants)
      assert.equal(variant.measure(count, depth, Number(cancel)), checksum);
    for (let repeat = 0; repeat < 21; ++repeat) {
      for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
        globalThis.gc();
        const start = performance.now();
        const result = variant.measure(count, depth, Number(cancel));
        const milliseconds = performance.now() - start;
        assert.equal(result, checksum);
        samples.push({variant: variant.name, repeat, milliseconds});
      }
    }
    const time = variant => median(samples.filter(s => s.variant === variant).map(s => s.milliseconds));
    cases.push({cancel, depth: String(depth), iterations: String(count), checksum: String(checksum),
      first_ms: time('first'), second_ms: time('second'), samples});
  }
  console.log(JSON.stringify(cases));
  process.exit(0);
}

const [baseArg, baseCompilerArg, compilerArg, outputArg] = args;
assert(baseArg && baseCompilerArg && compilerArg,
  'usage: benchmark-frame-ownership.mjs BASE_ROOT BASE_COMPILER CURRENT_COMPILER [OUTPUT]');
const output = resolve(outputArg ?? join(root, 'build/migration/frame-ownership'));
mkdirSync(join(output, 'generated'), {recursive: true});
const cpu = process.env.BENCH_CPU ?? '2';
assert(/^\d+$/.test(cpu));
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command}: ${result.stderr || result.stdout}`);
  return result.stdout;
}
const artifact = path => ({bytes: statSync(path).size,
  sha256: createHash('sha256').update(readFileSync(path)).digest('hex')});
const source = join(root, 'tests/benchmarks/frame-ownership.sld');
const runtime = join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm');
const variants = [];
for (const [name, directory, compiler] of [
  ['baseline', resolve(baseArg), resolve(baseCompilerArg)], ['current', root, resolve(compilerArg)],
]) {
  const wat = join(output, `${name}.wat`), wasm = join(output, `${name}.wasm`);
  run('node', ['--no-warnings', join(root, 'host/native/run-snail.mjs'), compiler,
    'wat', source, wat, join(output, 'generated'), join(directory, 'src')], directory);
  run(join(root, 'build/native-snail/release/snail'), ['link', wat, runtime, wasm]);
  variants.push({name, commit: run('git', ['rev-parse', 'HEAD'], directory).trim(),
    compiler: artifact(compiler), wat: artifact(wat), wasm: artifact(wasm),
    implementation: Object.fromEntries(['prepare', 'wasm'].map(module =>
      [module, artifact(join(directory, `src/snail/shell/compiler/${module}.sld`))]))});
}
const measure = (first, second) => JSON.parse(run('taskset', ['-c', cpu, 'node',
  '--no-warnings', '--expose-gc', fileURLToPath(import.meta.url), '--measure',
  join(output, `${first}.wasm`), join(output, `${second}.wasm`)]));
// Reverse module creation in a fresh process and include an identical-binary
// control: instance order and engine layout affected earlier measurements.
const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: cpus()[Number(cpu)]?.model, affinity: cpu, harness: artifact(fileURLToPath(import.meta.url)),
  source: artifact(source), scalar_runtime: artifact(runtime), variants,
  forward: {first: 'baseline', second: 'current', cases: measure('baseline', 'current')},
  reverse: {first: 'current', second: 'baseline', cases: measure('current', 'baseline')},
  control: {first: 'current', second: 'current', cases: measure('current', 'current')}};
writeFileSync(join(output, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report.forward.cases.map(({samples, ...summary}) => summary)));
