import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {join} from 'node:path';
import {openCompilerService} from '../../src/lofi/compiler/service.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const directory = process.argv[2];
const module = name => new WebAssembly.Module(readFileSync(join(directory, `${name}.wasm`)));
const shared = new WebAssembly.Instance(module('provider'));
const wrong = new WebAssembly.Instance(module('wrong-provider'));
const messages = [];
let text = '';
const observer = new WebAssembly.Instance(module('observer'), {host: {
  character(value) { text += String.fromCodePoint(value); },
  message() { messages.push(text); text = ''; },
  fail() { throw new Error(`Lofi assertion failed; diagnostics: ${messages.join('\n')}`); },
}});
const borrowed = new Map([['probe', shared]]);
const selections = new Map([['empty', new Map()], ['probe', borrowed], ['wrong', new Map([['probe', wrong]])]]);
const service = openCompilerService({providerSets: selections});
selections.clear();
borrowed.clear();
const providers = new Map([...service.providers, ['tests', observer]]);
let instance;
try {
  instance = instantiate(loadWasm(readFileSync(join(directory, 'program.wasm'))), providers);
  assert.equal(invokeEntry(instance, []), 42);
  assert.equal(shared.exports.trace.value, 121277, 'aliases initialize once per instance; failed initializers retain effects');
  assert.equal(wrong.exports.trace.value, 0, 'provider mismatch precedes initialization');
  assert.equal(messages.length, 13);
  for (const expected of ['bad-source.sld', 'source state', 'lofi primitive', 'unknown provider set',
    'missing Wasm provider', 'expected type', 'semantic signature', 'closed', 'initialization failed', 'unreachable'])
    assert(messages.some(message => message.includes(expected)), `${expected}: ${messages}`);
  assert(existsSync('saved-application.wasm'));
} finally {
  if (instance) closeInstance(instance);
  service.close();
  service.close();
}
assert.throws(() => service.providers.get('lofi.compiler').exports['map-empty'](), /closed/);
const saved = instantiate(loadWasm(readFileSync('saved-application.wasm')), new Map([['probe', shared]]));
assert.equal(invokeEntry(saved, [9]), 9, 'saved artifact survives compiler scope closure');
closeInstance(saved);
console.log('PASS ordinary Lofi compile/load/instantiate/invoke, source/generated imports, aliases, signatures, errors and closure');
