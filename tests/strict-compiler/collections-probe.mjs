import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- One fresh linked instance per positive or terminal negative control ----

const module = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
assert(WebAssembly.Module.imports(module).every(item => item.module === 'wasi_snapshot_preview1'));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}, returnOnExit: true});
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: wasi.wasiImport});
const entry = process.argv[3];
try {
  wasi.initialize(instance);
  instance.exports.main();
  const answer = instance.exports[entry]();
  assert.equal(entry, 'compiler-collection-checks', 'negative control unexpectedly returned');
  assert.equal(answer, 42n);
  console.log('PASS compiler collections: 42');
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
}
