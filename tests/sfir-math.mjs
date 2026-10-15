import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Invoke the linked provider; the driver checks every scalar result ----

const [artifact, ...inputs] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: wasi.wasiImport});
wasi.initialize(instance);
instance.exports.main();
for (const input of inputs) {
  for (let operation = 0; operation < 3; operation++) {
    const value = instance.exports.trigonometry(BigInt(operation), Number(input));
    console.log(Object.is(value, -0) ? '-0' : value.toString());
  }
}
assert.equal(instance.exports['close-resources'](), 0);
