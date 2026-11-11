// Run the same linked Wasm artifacts as the Wasmtime harness.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';

const directory = process.argv[2];
const bench = process.argv.includes('--bench');
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const moduleAt = name => new WebAssembly.Module(fs.readFileSync(path.join(directory, name)));

function check(guest) {
  const names = Object.keys(guest).filter(name => /^(test_|negative_|trap_)/.test(name));
  for (const name of names) {
    guest.reset();
    if (name.startsWith('trap_')) assert.throws(() => guest[name](), WebAssembly.RuntimeError, name);
    else assert.equal(guest[name](), 1, name);
  }
  // Exercise generated spill kernels with actual collection at every call.
  for (const roots of [1, 4, 16]) {
    const checksums = ['locals', 'shadow', 'stack'].map(mode => {
      guest.reset(); guest.stress(1);
      return guest[`${mode}_${roots}`](3, 2);
    });
    assert.ok(checksums.every(value => value === checksums[0]));
  }
  return names;
}

function timed(guest, fn, iterations, work) {
  guest.reset();
  const start = process.hrtime.bigint();
  const checksum = fn(iterations, work);
  return [Number(process.hrtime.bigint() - start), checksum];
}

function benchmark(guest, roots, work) {
  const modes = ['locals', 'shadow', 'stack'];
  const functions = modes.map(mode => guest[`${mode}_${roots}`]);
  let iterations = 16384;
  while (timed(guest, functions[0], iterations, work)[0] < 20e6) iterations *= 2;
  for (const fn of functions) for (let i = 0; i < 5; i++) timed(guest, fn, iterations, work);
  const samples = Array.from({ length: 15 }, (_, round) => {
    const sample = [], checksums = [];
    for (let offset = 0; offset < 3; offset++) {
      const mode = (round + offset) % 3;
      const [ns, checksum] = timed(guest, functions[mode], iterations, work);
      sample[mode] = ns / iterations; checksums[mode] = checksum;
    }
    assert.ok(checksums.every(value => value === checksums[0]));
    return sample;
  });
  return { roots, work, iterations, modes,
    ns_per_call: modes.map((_, i) => median(samples.map(s => s[i]))),
    overhead_percent: [1, 2].map(i => median(samples.map(s => (s[i] / s[0] - 1) * 100))),
    samples_ns_per_call: samples };
}

function churn(guest, runtime) {
  const samples = [];
  for (let i = 0; i < 9; i++) {
    const [ns, checksum] = timed(guest, guest.churn, 1e6, 0);
    assert.equal(checksum, 1234567); samples.push(ns / 1e6);
  }
  assert.ok(runtime.collections() > 0);
  return { allocations: 1e6, collections: runtime.collections(), ns_per_allocation: median(samples) };
}

function pauses(guest, runtime) {
  return [1, 1000, 10000].map(count => {
    guest.reset(); guest.prepare_live(count);
    const samples = Array.from({ length: 15 }, () => {
      const start = process.hrtime.bigint(); guest.collect_live();
      return Number(process.hrtime.bigint() - start) / 1000;
    });
    assert.equal(runtime.live(), count);
    return { live_objects: count, payload_bytes: count * 32, median_us: median(samples) };
  });
}

const results = [32, 64].map(bits => {
  const runtime = new WebAssembly.Instance(moduleAt(`runtime${bits}.wasm`)).exports;
  const guest = new WebAssembly.Instance(moduleAt(`workload${bits}.wasm`), { gc: runtime }).exports;
  const tests = check(guest);
  const cases = bench ? [[1, 1], [4, 1], [16, 1], [16, 64]].map(([r, w]) => benchmark(guest, r, w)) : [];
  return { bits, tests, cases, churn: churn(guest, runtime), pauses: pauses(guest, runtime) };
});
assert.equal(new WebAssembly.Instance(moduleAt('high-address.wasm')).exports.probe(), 1234567);
console.log(JSON.stringify({ engine: `Node ${process.version} / V8 ${process.versions.v8}`,
  flags: process.execArgv, cpu: os.cpus()[0].model, platform: `${os.platform()} ${os.release()} ${os.arch()}`,
  affinity: os.platform() === 'linux' ? fs.readFileSync('/proc/self/status', 'utf8').match(/^Cpus_allowed_list:\s*(.*)$/m)?.[1] : null,
  sha256: Object.fromEntries(['runtime32.wasm', 'runtime64.wasm', 'workload32.wasm', 'workload64.wasm'].map(name =>
    [name, createHash('sha256').update(fs.readFileSync(path.join(directory, name))).digest('hex')])),
  high_address: 'passed: 4 GiB + 16', results }, null, 2));
