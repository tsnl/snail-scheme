import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {WASI} from 'node:wasi';

// ---- Numeric libraries use their ordinary linked scalar services ----

const module = await WebAssembly.compile(await readFile(process.argv[2]));
const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
const instance = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi.wasiImport});
try {
  wasi.initialize(instance);
  assert.equal(instance.exports.main(), 42);
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
}
console.log('PASS numeric-library arithmetic exceptions');
