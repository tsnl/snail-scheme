import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// The imported functions come from a separately compiled Wasm producer. JS
// functions alone would accept arbitrary signatures and miss linker failures.
const [providerPath, programPath, contract] = process.argv.slice(2);
let callback = () => { throw new Error('unexpected foreign callback'); };
const producerModule = new WebAssembly.Module(readFileSync(providerPath));
const producer = new WebAssembly.Instance(producerModule, {host: {callback: () => callback()}}).exports;
const program = new WebAssembly.Module(readFileSync(programPath));
const instance = new WebAssembly.Instance(program, {probe: producer});
const api = instance.exports;
const trap = fn => assert.throws(fn, WebAssembly.RuntimeError);
trap(() => api.worker(1));

if (contract === 'native') {
  assert.equal(api.main(), 42);
  assert.equal(producer.trace.value, 91234);
  assert.equal(producer.marks.value, 4);
  assert.equal(api.worker(2), 2);
  assert.equal(api.worker(3), 5);
  assert.equal(api['void-worker'](7), undefined);
  assert.equal(producer.trace.value, 912347);
  assert.equal(api['class-worker'](40), 42);
  assert.equal(api['class-value-worker'](40), 42);
  assert.equal(api['local-worker'](40), 42);
  assert.equal(api['macro-worker'](42), 42);
  assert.equal(api['i64-worker'](-9223372036854775808n), -9223372036854775808n);
  assert.equal(api['f32-worker'](1.25), 1.25);
  assert.equal(api['f64-worker'](1.25e100), 1.25e100);
  assert.equal(api['bool-worker'](1), 1);
  assert.equal(api['bool-worker'](0), 0);
  assert.equal(api['char-worker'](0x10ffff), 0x10ffff);
  trap(() => api.main());
  assert.equal(api.worker(1), 6);
  assert.equal(producer.marks.value, 5);
  assert.throws(() => new WebAssembly.Instance(program, {probe: {...producer, add: producer.id64}}),
                WebAssembly.LinkError);
  assert.throws(() => new WebAssembly.Instance(program, {probe: {...producer, mark: producer.id32}}),
                WebAssembly.LinkError);
} else if (contract === 'failed-main') {
  trap(() => api.main());
  trap(() => api.main());
  trap(() => api.worker(1));
  assert.equal(producer.trace.value, 8);
  assert.equal(producer.marks.value, 1);
} else if (contract === 'unit-main') {
  assert.equal(api.main(), undefined);
  assert.equal(api.worker(), undefined);
  trap(() => api.main());
} else if (contract === 'round') {
  api.main();
  const cases = [[0, 0], [-0, -0], [0.5, 0], [-0.5, -0],
    [1.5, 2], [2.5, 2], [3.5, 4], [-1.5, -2], [-2.5, -2], [-3.5, -4],
    [1.25, 1], [-1.25, -1], [1.75, 2], [-1.75, -2],
    [2 ** 64, 2 ** 64], [-(2 ** 64), -(2 ** 64)],
    [Infinity, Infinity], [-Infinity, -Infinity], [NaN, NaN]];
  for (const name of ['worker', 'native64', 'view64', 'round32', 'native32', 'view32']) {
    for (const [input, expected] of cases)
      assert(Object.is(api[name](input), expected), `${name}: ${input} -> ${expected}`);
  }
  for (const name of ['worker', 'native64', 'view64']) {
    assert(Object.is(api[name](-Number.MIN_VALUE), -0));
    assert(Object.is(api[name](Number.MIN_VALUE), 0));
    assert.equal(api[name](Number.MAX_VALUE), Number.MAX_VALUE);
  }
  for (const name of ['round32', 'native32', 'view32']) {
    assert(Object.is(api[name](-(2 ** -149)), -0));
    assert(Object.is(api[name](2 ** -149), 0));
    assert.equal(api[name](2 ** 24 + 1), 2 ** 24);
  }
} else if (contract === 'reentrant-main') {
  callback = () => trap(() => api.main());
  assert.equal(api.main(), 42n);
  assert.equal(api.worker(42), 42);
  const secondProducer = new WebAssembly.Instance(producerModule, {
    host: {callback: () => second.exports.main()},
  }).exports;
  const second = new WebAssembly.Instance(program, {probe: secondProducer});
  trap(() => second.exports.main());
  trap(() => second.exports.main());
  trap(() => second.exports.worker(1));
} else if (contract === 'vectors') {
  callback = () => global.gc();
  assert.equal(api.main(), 42n);
  const contents = () => Array.from({length: 6}, (_, i) => api.read(BigInt(i)));
  const original = [0n, 1n, 2n, 3n, 4n, 5n];
  for (const index of [-1n, 6n, 2n ** 32n, 2n ** 32n + 1n, 2n ** 63n - 1n, -(2n ** 63n)]) {
    api.reset();
    trap(() => api.read(index));
    trap(() => api.write(index));
    assert.equal(api.marks(), 1234n, 'all operands precede the first-class operator and bounds check');
    assert.deepEqual(contents(), original, 'rejected write must not change any element');
  }
  for (const count of [-1n, 2n ** 32n, 2n ** 32n + 1n, 2n ** 63n - 1n]) {
    api.reset();
    trap(() => api.allocate(count));
    assert.equal(api.marks(), 12n, 'fill evaluates once even for a rejected allocation');
  }
  for (const count of [0n, 1n, 5n]) {
    api.reset();
    assert.equal(api.allocate(count), count);
    assert.equal(api.marks(), 12n);
  }
  for (const [at, start, end] of [[1n, 0n, 5n], [0n, 1n, 6n], [0n, 0n, 6n], [6n, 6n, 6n]]) {
    api.reset();
    const expected = [...original];
    expected.splice(Number(at), Number(end - start), ...original.slice(Number(start), Number(end)));
    api.copy(at, start, end);
    assert.equal(api.marks(), 123456n);
    assert.deepEqual(contents(), expected);
  }
  for (const [at, start, end] of [
    [-1n, 0n, 0n], [7n, 0n, 0n], [0n, 7n, 7n], [0n, -1n, 0n],
    [0n, 3n, 2n], [0n, 0n, 7n], [5n, 0n, 2n], [0n, 1n, 2n ** 32n],
    [2n ** 32n, 0n, 1n], [0n, 2n ** 32n, 2n ** 32n], [0n, 0n, 2n ** 63n - 1n],
  ]) {
    api.reset();
    trap(() => api.copy(at, start, end));
    assert.equal(api.marks(), 123456n, 'range validation follows every operand effect');
    assert.deepEqual(contents(), original, 'rejected copy must not partially write');
  }
  assert.equal(api['gc-check'](), 43n, 'managed fill and vector survive collection');
} else {
  throw new Error(`unknown native boundary contract: ${contract}`);
}
console.log(`PASS ${contract}`);
