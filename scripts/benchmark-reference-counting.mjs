#!/usr/bin/env node
// Compare the old suffix rewrite with lexical exit contexts, using one compiler.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, readdirSync, readFileSync, statSync, writeFileSync} from 'node:fs';
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
  for (const [index, path] of args.slice(1).entries()) {
    const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}});
    const {instance} = await WebAssembly.instantiate(readFileSync(path), wasi.getImportObject());
    wasi.initialize(instance);
    assert.equal(instance.exports.main(), 0);
    variants.push({name: index ? 'current' : 'baseline', measure: instance.exports.measure,
      nodes: depth => (index ? 8n : 10n) * depth + 8n});
  }
  // Exercise the deepest case before collecting any samples, then warm each size.
  for (let warm = 0; warm < 10; ++warm)
    for (const variant of variants)
      assert.equal(variant.measure(512n, 5n), variant.nodes(512n) * 5n);
  const cases = [];
  for (const depth of [32n, 128n, 512n]) {
    const iterations = 10n, samples = [];
    for (const variant of variants) {
      for (let warm = 0; warm < 3; ++warm)
        assert.equal(variant.measure(depth, iterations), variant.nodes(depth) * iterations);
    }
    for (let repeat = 0; repeat < 9; ++repeat) {
      for (const variant of repeat % 2 ? [...variants].reverse() : variants) {
        globalThis.gc();
        const start = performance.now();
        const checksum = variant.measure(depth, iterations);
        const milliseconds = performance.now() - start;
        assert.equal(checksum, variant.nodes(depth) * iterations);
        samples.push({variant: variant.name, repeat, milliseconds, checksum: String(checksum)});
      }
    }
    const time = name => median(samples.filter(s => s.variant === name).map(s => s.milliseconds));
    cases.push({depth: String(depth), iterations: String(iterations),
      baseline_nodes: String(variants[0].nodes(depth)), current_nodes: String(variants[1].nodes(depth)),
      baseline_ms: time('baseline'), current_ms: time('current'), samples});
  }
  console.log(JSON.stringify(cases));
  process.exit(0);
}

const [baselineArg, compilerArg, outputArg] = args;
assert(baselineArg && compilerArg,
  'usage: benchmark-reference-counting.mjs BASE_ROOT CURRENT_COMPILER [OUTPUT]');
const baseline = resolve(baselineArg), compiler = resolve(compilerArg);
const output = resolve(outputArg ?? join(root, 'build/migration/reference-counting'));
mkdirSync(output, {recursive: true});
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
// The benchmark imports these compiler libraries and the core library closure.
// Verify the common code rather than attributing unrelated source changes to this pass.
const common = readdirSync(join(root, 'src/snail/core')).filter(name => name.endsWith('.sld'))
  .map(name => `src/snail/core/${name}`)
  .concat(['read', 'annotations', 'core', 'capabilities', 'ownership', 'check', 'conversions', 'specialize']
    .map(name => `src/snail/shell/compiler/${name}.sld`));
const common_sources = common.sort().map(path => {
  const current = artifact(join(root, path));
  assert.deepEqual(artifact(join(baseline, path)), current, `common dependency changed: ${path}`);
  return {path, ...current};
});
const fixture = readFileSync(join(root, 'tests/benchmarks/reference-counting.sld'), 'utf8');
const runtime = join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm');
const variants = [];
for (const [name, directory, library] of [
  ['baseline', baseline, 'lifetimes'], ['current', root, 'reference-counting'],
]) {
  const source = join(output, `${name}.sld`), wat = join(output, `${name}.wat`);
  const wasm = join(output, `${name}.wasm`);
  writeFileSync(source, fixture.replaceAll('compiler reference-counting', `compiler ${library}`)
    .replaceAll('lower-reference-counting', `lower-${library}`));
  run('node', ['--no-warnings', join(root, 'host/native/run-snail.mjs'), compiler,
    'wat', source, wat, output, join(directory, 'src')]);
  run(join(root, 'build/native-snail/release/snail'), ['link', wat, runtime, wasm]);
  variants.push({name, directory, commit: run('git', ['rev-parse', 'HEAD'], directory).trim(),
    implementation: artifact(join(directory, `src/snail/shell/compiler/${library}.sld`)),
    source: artifact(source), wat: artifact(wat), wasm: artifact(wasm)});
}
const cases = JSON.parse(run('taskset', ['-c', cpu, 'node', '--no-warnings', '--expose-gc',
  fileURLToPath(import.meta.url), '--measure', join(output, 'baseline.wasm'), join(output, 'current.wasm')]));
const report = {date: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: cpus()[Number(cpu)]?.model, affinity: cpu, compiler: artifact(compiler),
  harness: artifact(fileURLToPath(import.meta.url)), scalar_runtime: artifact(runtime),
  common_sources, variants, cases};
writeFileSync(join(output, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(cases.map(({samples, ...summary}) => summary)));
