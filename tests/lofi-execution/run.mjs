import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance, InitializationError}
  from '../../src/lofi/execute.mjs';

const directory = process.argv[2];
const bytes = name => readFileSync(join(directory, name));
const load = name => loadWasm(bytes(`${name}.wasm`));
const providerModule = new WebAssembly.Module(bytes('provider.wasm'));
const provider = () => new WebAssembly.Instance(providerModule);
const bindings = instance => new Map([['probe', instance]]);

// ---- Loads own code; instances own state; providers are explicitly shared ----

const source = bytes('state.wasm'), code = loadWasm(source), secondLoad = load('state');
source.fill(0);
assert.deepEqual(code.entry, {library: ['execution', 'facade'], export: 'main'});
assert.deepEqual(code.parameters, ['I32']);
assert.equal(code.result, 'I32');
const shared = provider();
assert.equal(shared.exports.trace.value, 0);
const first = instantiate(code, bindings(shared)), second = instantiate(code, bindings(shared));
const third = instantiate(secondLoad, bindings(shared));
globalThis.gc?.();
assert.equal(shared.exports.trace.value, 121212, 'dependency aliases initialize once, before the facade');
assert.equal(invokeEntry(first, [4]), 4);
assert.equal(invokeEntry(first, [3]), 7);
assert.equal(invokeEntry(second, [2]), 2);
assert.equal(invokeEntry(third, [1]), 1, 'separate load has no shared library state');
assert.throws(() => invokeEntry(first, []), /parameter count/);
assert.throws(() => invokeEntry(first, [1, 2]), /parameter count/);
for (const value of [1n, 0.5, NaN, Infinity, -0x80000001, 0x80000000, true, '1'])
  assert.throws(() => invokeEntry(first, [value]), /I32/);
assert.equal(invokeEntry(first, [0]), 7, 'invalid calls perform no guest effects');
closeInstance(first);
closeInstance(first);
globalThis.gc?.();
assert.throws(() => invokeEntry(first, [0]), /closed/);
assert.equal(invokeEntry(second, [1]), 3);
const independentProvider = provider(), fourth = instantiate(code, bindings(independentProvider));
assert.equal(independentProvider.exports.trace.value, 12);
assert.equal(invokeEntry(fourth, [1]), 1);
assert.equal(shared.exports.trace.value, 121212, 'closing an instance does not close a shared provider');

// ---- Provider and actual ABI signatures are checked before initialization ----

assert.throws(() => instantiate(code), /missing Wasm provider/);
assert.throws(() => instantiate(code, new Map([['probe', {exports: {mark() {}}}]])), TypeError);
const wrongProvider = new WebAssembly.Instance(new WebAssembly.Module(bytes('wrong-provider.wasm')));
assert.throws(() => instantiate(code, bindings(wrongProvider)), WebAssembly.LinkError);
assert.equal(wrongProvider.exports.trace.value, 0);
const checkedProvider = provider();
for (const name of ['wrong-main', 'wrong-entry'])
  assert.throws(() => instantiate(load(name), bindings(checkedProvider)), WebAssembly.LinkError);
assert.equal(checkedProvider.exports.trace.value, 0, 'ABI mismatch precedes main effects');
assert.throws(() => load('start'), /automatic start/);
assert.throws(() => load('mutable-import'), /only function imports/);
assert.throws(() => loadWasm(bytes('native.o')), /native64 loading is not supported/);

// ---- Failed initialization returns no handle and retains external effects ----

const failedCode = load('failed'), effectProvider = provider();
for (const expected of [7, 77]) {
  let instance;
  assert.throws(() => { instance = instantiate(failedCode, bindings(effectProvider)); }, InitializationError);
  assert.equal(instance, undefined);
  assert.equal(effectProvider.exports.trace.value, expected, 'failed dependencies prevent dependent initialization');
}

// ---- Exact scalar arguments and results ----

const identity = type => instantiate(load(type));
const i32 = identity('i32'), i64 = identity('i64');
for (const value of [-0x80000000, -1, 0, 0x7fffffff]) assert.equal(invokeEntry(i32, [value]), value);
for (const value of [-(1n << 63n), -1n, 0n, (1n << 53n) + 1n, (1n << 63n) - 1n])
  assert.equal(invokeEntry(i64, [value]), value);
for (const value of [1, 1.5, -(1n << 63n) - 1n, 1n << 63n])
  assert.throws(() => invokeEntry(i64, [value]), /I64/);
for (const [name, round] of [['f32', Math.fround], ['f64', value => value]]) {
  const instance = identity(name);
  const values = [0, -0, 1 / 3, Number.MIN_VALUE, -Number.MIN_VALUE, NaN, Infinity, -Infinity];
  if (name === 'f64') values.push(Number.MAX_VALUE, -Number.MAX_VALUE);
  for (const value of values)
    assert(Object.is(invokeEntry(instance, [value]), round(value)), `${name} preserves its floating representation`);
  if (name === 'f32') {
    const largest = (2 - 2 ** -23) * 2 ** 127;
    for (const value of [largest, largest + 2 ** 102, -largest, -largest - 2 ** 102])
      assert.equal(invokeEntry(instance, [value]), round(value));
    for (const value of [Number.MAX_VALUE, -Number.MAX_VALUE, largest + 2 ** 103])
      assert.throws(() => invokeEntry(instance, [value]), /finite F32 value overflows/);
  }
  assert.throws(() => invokeEntry(instance, [1n]), /scalar type/);
}
const bool = identity('bool'), char = identity('char'), unit = identity('unit-result');
for (const value of [false, true]) assert.equal(invokeEntry(bool, [value]), value);
for (const value of [0, 1, 2, 'true']) assert.throws(() => invokeEntry(bool, [value]), /boolean/);
for (const value of ['\0', 'λ', '😀', '\ud7ff', '\ue000', String.fromCodePoint(0x10ffff)])
  assert.equal(invokeEntry(char, [value]), value);
for (const value of ['', 'ab', '\ud800', '\udfff', 65])
  assert.throws(() => invokeEntry(char, [value]), /Unicode scalar/);
assert.equal(invokeEntry(unit, []), undefined);
assert.throws(() => invokeEntry(unit, [undefined]), /parameter count/);
for (const name of ['bad-bool', 'bad-char']) {
  const instance = instantiate(load(name), bindings(provider()));
  assert.throws(() => invokeEntry(instance, []), /invalid .* entry result/);
  assert.throws(() => invokeEntry(instance, []), /invalid .* entry result/);
}

// ---- Calls preserve prior effects after traps and reject reentrant operations ----

const trapped = instantiate(load('traps'));
assert.equal(invokeEntry(trapped, [1]), 1);
assert.throws(() => invokeEntry(trapped, [0]), WebAssembly.RuntimeError);
assert.equal(invokeEntry(trapped, [1]), 3);
let callbackInstance;
const callbackProvider = new WebAssembly.Instance(new WebAssembly.Module(bytes('callback-provider.wasm')), {
  host: {call() {
    assert.throws(() => invokeEntry(callbackInstance, []), /already executing/);
    assert.throws(() => closeInstance(callbackInstance), /already executing/);
    return 42;
  }}
});
callbackInstance = instantiate(load('callback'), bindings(callbackProvider));
assert.equal(invokeEntry(callbackInstance, []), 42);
const argumentsWithGetter = [0];
Object.defineProperty(argumentsWithGetter, 0, {get() {
  assert.throws(() => closeInstance(second), /already executing/);
  return 0;
}});
assert.equal(invokeEntry(second, argumentsWithGetter), 3);

// ---- Malformed or unsupported artifact metadata never becomes loaded code ----

function metadataModule(signature, twice = false) {
  const name = new TextEncoder().encode('lofi.entry');
  const json = new TextEncoder().encode(JSON.stringify(signature));
  const payload = [name.length, ...name, ...json];
  assert(payload.length < 128);
  const section = [0, payload.length, ...payload];
  return Uint8Array.from([0, 97, 115, 109, 1, 0, 0, 0, ...section, ...(twice ? section : [])]);
}
const signature = {version: 1, library: ['test'], export: 'entry', parameters: ['I32'], result: 'I32'};
for (const change of [{version: 2}, {parameters: ['Any']}, {parameters: ['Unit']}, {result: 'Ref'},
  {library: []}, {export: 42}, {extra: true}])
  assert.throws(() => loadWasm(metadataModule({...signature, ...change})), /metadata/);
assert.throws(() => loadWasm(metadataModule(signature, true)), /one lofi.entry/);
assert.throws(() => loadWasm(metadataModule(signature)), /missing Wasm function export/);
assert.throws(() => loadWasm(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])), /one lofi.entry/);
assert.throws(() => instantiate({}), /loaded Wasm code/);
assert.throws(() => invokeEntry({}, []), /Lofi Wasm instance/);
console.log('PASS Wasm load, independent instances, checked providers and scalar invocation');
