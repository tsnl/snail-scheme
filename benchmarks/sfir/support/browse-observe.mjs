import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Separate probes stream every event without retaining a second trace ----

const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': process.cwd()}, returnOnExit: true});
let buffer = '';
const flush = () => { fs.writeSync(1, buffer); buffer = ''; };
const emit = text => { buffer += text + '\n'; if (buffer.length >= 65536) flush(); };
const floating = new DataView(new ArrayBuffer(8));
const observer = {
  emit_i64: value => emit(`i:${value}`),
  emit_char: value => emit(`c:${value}`),
  emit_f64: value => {
    floating.setFloat64(0, value, true);
    emit(`f:${Number.isNaN(value) ? 'nan' : floating.getBigUint64(0, true)}`);
  },
};
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(item => ['benchmark', 'reader.test', 'wasi_snapshot_preview1'].includes(item.module)));
const instance = new WebAssembly.Instance(module, {benchmark: {barrier: () => 1,
  write_character: value => fs.writeSync(1, String.fromCodePoint(value))},
  'reader.test': observer, wasi_snapshot_preview1: wasi.wasiImport});
try {
  wasi.initialize(instance);
  instance.exports.main();
  emit(`result:${instance.exports[config.export]()}`);
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
  flush();
}
