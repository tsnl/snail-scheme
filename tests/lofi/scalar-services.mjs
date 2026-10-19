import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- The Scheme harness supplies identical scalar inputs to both Wasm forms ----

const [artifact, ...arguments_] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(item => item.module === 'wasi_snapshot_preview1'));
const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: wasi.wasiImport});
wasi.initialize(instance);
instance.exports.main();
assert.equal(arguments_.length % 4, 0);
for (let i = 0; i < arguments_.length; i += 4) {
  const [kind, operation, left, right] = arguments_.slice(i, i + 4);
  const inputs = [BigInt(operation), Number(left)];
  if (kind === 'binary') inputs.push(Number(right));
  const value = instance.exports[kind](...inputs);
  console.log(Object.is(value, -0) ? '-0' : value.toString());
}
assert.equal(instance.exports['close-resources'](), 0);
