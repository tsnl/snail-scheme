// Run a compiled, zero-argument pure example through the public execution API.
import {readFileSync} from 'node:fs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const [filename] = process.argv.slice(2);
if (!filename) throw new Error('usage: node examples/applications/run.mjs EXAMPLE.wasm');
const instance = instantiate(loadWasm(readFileSync(filename)));
try {
  console.log(invokeEntry(instance, []));
} finally {
  closeInstance(instance);
}
