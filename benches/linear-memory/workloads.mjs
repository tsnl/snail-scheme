// Compare the same compiler source hosted on two memory backends, and run
// the existing Siegework balance workload on each one's release build.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {copyFileSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
if (process.argv.length !== 4) throw new Error('usage: node workloads.mjs WASMGC_CHECKOUT OUTPUT_DIRECTORY');
const control = resolve(process.argv[2]), out = resolve(process.argv[3]);
mkdirSync(out, {recursive: true});
const runner = join(root, 'host/native/run-snail.mjs'), source = 'tests/siegework/balance.scm';
const expected = readFileSync(join(root, 'tests/siegework/balance.out'), 'utf8');
const execute = (file, args, cwd = root) => execFileSync(file, args, {cwd, encoding: 'utf8'});
const node = (...args) => execute(process.execPath, ['--no-warnings', runner, ...args]);
function tools(checkout, name) {
  const [cli, runtime, toolchain] = execute(join(checkout, 'scripts/bootstrap'), [], checkout).trim().split('\n');
  return {name, checkout, cli, runtime, toolchain};
}
const gc = tools(control, 'wasmgc'), linear = tools(root, 'linear');
function compile(backend, input, wat) {
  node(backend.cli, root, backend.runtime, backend.toolchain, 'compile', 'node', join(root, input), wat, join(root, 'src'));
}
const hosted = join(out, 'compiler-on-wasmgc');
compile(gc, 'bootstrap/cli.scm', hosted + '.wat');
execute(join(control, 'build/wasm-snail-scheme-support-toolchain/release/snail-link'),
  [hosted + '.wat', gc.toolchain, hosted + '.wasm']);
gc.cli = hosted + '.wasm';
for (const backend of [gc, linear]) {
  const dir = execute(join(backend.checkout, 'snail-scheme'), ['build', '--release', '--target', 'node', source], backend.checkout).trim();
  backend.game = join(out, 'balance-' + backend.name + '.wasm');
  copyFileSync(join(dir, 'balance.wasm'), backend.game);
}
function measure(label, action) {
  const samples = new Map([[gc, []], [linear, []]]);
  for (let round = 0; round < 6; round++) {
    for (const backend of round % 2 ? [linear, gc] : [gc, linear]) {
      const start = performance.now();
      action(backend);
      if (round) samples.get(backend).push(performance.now() - start);
    }
  }
  for (const [backend, times] of samples) {
    times.sort((a, b) => a - b);
    console.log(JSON.stringify({workload: label, backend: backend.name, medianMs: times[2], samplesMs: times}));
  }
}
const output = backend => join(out, 'balance-from-' + backend.name + '.wat');
measure('compile balance', backend => compile(backend, source, output(backend)));
assert.deepEqual(readFileSync(output(gc)), readFileSync(output(linear)), 'the same compiler must emit identical WAT');
measure('run balance', backend => assert.equal(node(backend.game), expected));

// Wrap each existing entry in a diagnostic run. The clock covers the work
// inside main. All counts are sampled before the first report is formatted.
function profile(label, input, params, args, expectedOutput, optimized) {
  const program = readFileSync(join(root, input), 'utf8');
  const entry = join(out, label + '-profile.scm'), wat = entry + '.wat', wasm = entry + '.wasm';
  const arguments_ = params.map(([name]) => name).join(' ');
  const header = params.map(([name, type]) => '(' + name + ' ' + type + ')').join(' ');
  writeFileSync(entry, program.replace('(import', '(import (bench heap)').replace('(define (main', '(define (workload') +
    '\n(define (main ' + header + ') (→ Unit) (with-heap-profile out (lambda () (workload ' + arguments_ + '))))\n');
  node(linear.cli, root, linear.runtime, linear.toolchain, 'compile', 'node', entry, wat,
    join(root, 'benches/linear-memory/src'), join(root, 'src'));
  execute(join(root, 'build/wasm-snail-scheme-support-toolchain/release/snail-link'),
    [wat, label === 'compiler' ? linear.toolchain : linear.runtime, wasm]);
  if (optimized) execute('wasm-opt', ['--disable-gc', '--enable-reference-types', '--enable-tail-call',
    '--enable-bulk-memory', '--enable-nontrapping-float-to-int', '--enable-sign-ext', '--enable-mutable-globals',
    '--enable-multivalue', '-O2', wasm, '-o', wasm]);
  const printed = node(wasm, ...args).trimEnd().split('\n'), counters = printed.pop().split(' ').map(Number);
  assert.equal(printed.join('\n'), expectedOutput.trimEnd());
  assert.ok(counters.length === 6 && counters.every(Number.isFinite));
  const [elapsedNs, pauseNs, maxPauseNs, collections, allocations, bytes] = counters;
  console.log(JSON.stringify({workload: label, elapsedNs, pauseNs, maxPauseNs, collections, allocations, bytes}));
}
const compilerParams = [['invoked', 'Arguments'], ['environment', 'ProcessEnvironment'], ['processes', 'Processes'],
  ['fs', 'Fs'], ['clock', 'Clock'], ['in', 'InputPort'], ['out', 'OutputPort']];
const profiledWat = join(out, 'balance-profiled-compiler.wat');
profile('compiler', 'bootstrap/cli.scm', compilerParams,
  [root, linear.runtime, linear.toolchain, 'compile', 'node', join(root, source), profiledWat, join(root, 'src')], '', false);
assert.deepEqual(readFileSync(profiledWat), readFileSync(output(linear)));
profile('simulation', source, [['out', 'OutputPort']], [], expected, true);

// V8's main-isolate trace includes host startup and pauses. Its concurrent
// collector work does not stop the main thread and is absent from this sum.
function enginePauses(workload, args) {
  const start = performance.now();
  const log = execFileSync(process.execPath, ['--no-warnings', '--trace-gc-nvp', runner, ...args],
    {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const elapsedMs = performance.now() - start;
  const pauses = [...log.matchAll(/^\[[^\]]+:0\]\s+\d+ ms: GC: (\{.*\})$/gm)].map(match => JSON.parse(match[1]).pause);
  assert.ok(pauses.length && pauses.every(Number.isFinite), 'expected Node 26 main-isolate GC events');
  console.log(JSON.stringify({workload, backend: 'wasmgc', elapsedMs, collections: pauses.length,
    pauseMs: pauses.reduce((sum, ms) => sum + ms, 0), maxPauseMs: Math.max(...pauses)}));
}
enginePauses('compiler', [gc.cli, root, gc.runtime, gc.toolchain, 'compile', 'node', join(root, source), output(gc), join(root, 'src')]);
enginePauses('simulation', [gc.game]);
