// Numeric conversion scratch belongs to one actual Wasm runtime instance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../host/browser/load.mjs';

const module = await WebAssembly.compile(await readFile(process.argv[2]));
async function runtime() {
  const wasi = createWasi({print: (_, text) => { throw new Error(text); }});
  const instance = await instantiate(module, {...wasi.getImportObject(), 'snail.platform': {
    'diagnostics/report-error': () => { throw new Error('unexpected runtime diagnostic'); },
  }});
  wasi.initialize(instance);
  return instance.exports;
}

function parse(runtime, text) {
  const scalars = Array.from(text, character => character.codePointAt(0));
  const pointer = runtime['snail:io/stage'](scalars.length);
  new Uint32Array(runtime.memory.buffer, pointer, scalars.length).set(scalars);
  return runtime['snail:datum/parse-real'](scalars.length);
}

function text(runtime, length) {
  let result = '';
  for (let index = 0; index < length; index++) result += String.fromCodePoint(runtime['snail:datum/text-character'](index));
  return result;
}

const first = await runtime(), second = await runtime();
assert.equal(parse(first, '12.5'), 1);
assert.equal(parse(second, '-0.0'), 1);
assert.equal(first['snail:datum/parsed-real'](), 12.5);
assert(Object.is(second['snail:datum/parsed-real'](), -0));
assert.equal(parse(first, 'invalid'), 0);
assert.equal(parse(first, '+nan.0'), 1);
assert(Number.isNaN(first['snail:datum/parsed-real']()));
assert.equal(parse(first, '4.9406564584124654e-324'), 1);
assert.equal(first['snail:datum/parsed-real'](), Number.MIN_VALUE);
const length = first['snail:datum/real-text'](1.25);
const other = second['snail:datum/real-text'](-Infinity);
assert.equal(parse(first, '7.5'), 1);
assert.equal(text(first, length), '1.25');
assert.equal(text(second, other), '-inf.0');
assert(Object.is(second['snail:datum/parsed-real'](), -0));
assert.equal(first['snail:io/close-all'](), 0);
assert.equal(second['snail:io/close-all'](), 0);
