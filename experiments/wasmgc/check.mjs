// Correctness checks for the functions lowered from check.scm.
import assert from 'node:assert/strict';
import fs from 'node:fs';

const path = process.argv[2] ?? 'build/wasmgc/check.wasm';
const { exports: e } = new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(path)));
let assertions = 0;
function check(actual, expected) {
  assert.equal(actual, expected);
  assertions++;
}
function trap(call, error) {
  e.error_code.value = 0;
  assert.throws(call, WebAssembly.RuntimeError);
  check(e.error_code.value, error);
}

// ---- Representation boundaries and arithmetic ----

check(e.sum_i64(1073741823n, 1n), 1073741824n);
check(e.sum(1073741823, 1), 1073741824);
check(e.sum(-1073741824, 0), -1073741824);
check(e.difference_i64(-1073741824n, 1n), -1073741825n);
check(e.sum_i64(-1073741824n, -1073741824n), -2147483648n);
check(e.sum_i64(9223372036854775807n, -9223372036854775808n), -1n);
check(e.difference_i64(-9223372036854775808n, -9223372036854775808n), 0n);
check(e.sum_f64(3.5, 2), 5.5);
check(e.difference_f64(4, 1.5), 2.5);
check(e.sum_mixed(3n, 2.5), 5.5);
check(e.sum_mixed(9007199254740993n, 0), 9007199254740992);
check(e.sum_f64(Infinity, 1), Infinity);
check(Number.isNaN(e.difference_f64(Infinity, Infinity)), true);

const maximum = 9223372036854775807n;
const minimum = -9223372036854775808n;
trap(() => e.sum_i64(maximum, 1n), 2);
trap(() => e.sum_i64(minimum, -1n), 2);
trap(() => e.difference_i64(maximum, -1n), 2);
trap(() => e.difference_i64(minimum, 1n), 2);
trap(() => e.type_error(), 1);
trap(() => e.sum(1073741824, 0), 3);
trap(() => e.sum(-1073741825, 0), 3);
trap(() => e['double-sum'](1073741823, 1073741823), 3);
check(e['double-sum_i64'](1073741823n, 1073741823n), 4294967292n);
check(e.truthy(0), 1);

// ---- Exact mixed comparisons ----

check(e['equal-number_mixed'](9007199254740993n, 9007199254740992), 0);
check(e.greater_mixed(9007199254740993n, 9007199254740992), 1);
check(e.less_mixed(9007199254740993n, 9007199254740992), 0);
check(e.less_mixed(maximum, 9223372036854775808), 1);
check(e['equal-number_mixed'](maximum, 9223372036854775808), 0);
check(e['equal-number_mixed'](minimum, -9223372036854775808), 1);
check(e.less_mixed(minimum, -Infinity), 0);
check(e.greater_mixed(minimum, -Infinity), 1);
check(e.less_mixed(maximum, Infinity), 1);
for (const name of ['equal-number', 'less', 'less-equal', 'greater', 'greater-equal']) {
  check(e[name + '_mixed'](1n, NaN), 0);
  check(e[name + '_f64'](NaN, 1), 0);
}

// ---- Proper tail calls ----

check(e.down(2000000, 0), 2000000);
console.log(`WasmGC correctness: ${assertions} assertions passed`);
