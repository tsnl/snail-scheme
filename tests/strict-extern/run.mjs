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
} else {
  throw new Error(`unknown native boundary contract: ${contract}`);
}
console.log(`PASS ${contract}`);
