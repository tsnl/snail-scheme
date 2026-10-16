import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/snail-lofi/execute.mjs';
import {scalars} from './scalars.mjs';

const directory = process.argv[2];
for (const [name, arguments_, expected] of [
  ['first', [35], 42], ['alias', [35], 42], ['second', [35], 55],
  ['reexport', [19, 23], 42], ['combined', [35], 97], ['example', [], 42]
]) {
  const code = loadWasm(readFileSync(join(directory, `${name}-result.wasm`)));
  const instance = instantiate(code);
  globalThis.gc?.();
  assert.equal(invokeEntry(instance, arguments_), expected);
  closeInstance(instance);
}
for (const [name, , expected] of scalars) {
  const instance = instantiate(loadWasm(readFileSync(join(directory, `${name}-result.wasm`))));
  assert(Object.is(invokeEntry(instance, []), expected), name);
  closeInstance(instance);
}
console.log('PASS received library execution, private lexical identities, aliases and renamed reexports');
