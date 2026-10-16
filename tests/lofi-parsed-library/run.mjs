import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {openCompilerService} from '../../src/lofi/compiler-service.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/execute.mjs';

const directory = process.argv[2];
const module = name => new WebAssembly.Module(readFileSync(join(directory, `${name}.wasm`)));
const probe = new WebAssembly.Instance(module('provider'));
const messages = [];
let text = '';
const observer = new WebAssembly.Instance(module('observer'), {host: {
  character(value) { text += String.fromCodePoint(value); },
  message() { messages.push(text); text = ''; },
  fail() { throw new Error(`Lofi assertion failed: ${messages.join('\n')}`); },
}});
const service = openCompilerService({providerSets: new Map([['probe', new Map([['probe', probe]])]])});
let instance;
try {
  instance = instantiate(loadWasm(readFileSync(join(directory, 'program.wasm'))),
    new Map([...service.providers, ['tests', observer]]));
  assert.equal(invokeEntry(instance, []), 42);
  assert.equal(probe.exports.trace.value, 555, 'same parsed value inserted twice initializes once');
  assert.equal(messages.length, 7);
  for (const expected of ['run', 'missing.sld', 'wide-error.sld', 'rest-error.sld', 'vector-error.sld', 'grammar-error.sld', 'multiple.sld'])
    assert(messages.some(message => message.includes(expected)), `${expected}: ${messages}`);
} finally {
  if (instance) closeInstance(instance);
  service.close();
}
console.log('PASS ordinary Lofi parse, typed inspection/transformation, fresh/aliased identity, explicit map compilation and execution');
