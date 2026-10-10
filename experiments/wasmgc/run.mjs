// Benchmark the canonical recursive workload; module compilation is untimed.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// ---- Workload ----

const inputs = [22, 23, 24, 25];
const expected = [17711, 28657, 46368, 75025];
const expectedWork = 4204971;

function fibonacciLinear(n) {
  let a = 0, b = 1;
  for (let i = 0; i < n; ++i) [a, b] = [b, a + b];
  return a;
}

function check(fibonacci) {
  for (let n = 0; n <= 12; ++n) assert.equal(fibonacci(n), fibonacciLinear(n));
  for (let i = 0; i < inputs.length; ++i) assert.equal(fibonacci(inputs[i]), expected[i]);
}

function workload(fibonacci) {
  let answer = 0;
  for (const n of inputs) answer += (n + 1) * fibonacci(n);
  assert.equal(answer, expectedWork);
  return answer;
}

function repeat(fibonacci, count) {
  let checksum = 0;
  for (let i = 0; i < count; ++i) checksum += workload(fibonacci);
  return checksum;
}

// ---- Run ----

const [modulePath, countText = '64'] = process.argv.slice(2);
const count = Number(countText);
assert(modulePath && Number.isSafeInteger(count) && count > 0);
const module = new WebAssembly.Module(readFileSync(modulePath));
const { exports: { fibonacci } } = new WebAssembly.Instance(module);
check(fibonacci);
repeat(fibonacci, 1);
const start = process.hrtime.bigint();
const checksum = repeat(fibonacci, count);
const elapsed = Number(process.hrtime.bigint() - start) / 1e9;
assert.equal(checksum, count * expectedWork);
console.log(`checksum: ${checksum}`);
console.log(`elapsed: ${elapsed.toFixed(9)} s; repetitions: ${count}`);
