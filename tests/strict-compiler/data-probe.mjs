import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Execute an internal probe with the real linked scalar runtime ----

const module = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
assert(WebAssembly.Module.imports(module).every(item => item.module === 'wasi_snapshot_preview1'));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {}, returnOnExit: true});
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: wasi.wasiImport});
try {
  wasi.initialize(instance);
  assert.equal(instance.exports.main(), 42n);
  console.log('PASS compiler internal probe: 42');
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
}
