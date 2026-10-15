import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Observe actual linked scalar services and close every opened file ----

const [artifact, directory] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(item => ['reader.test', 'wasi_snapshot_preview1'].includes(item.module)));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': directory}, returnOnExit: true});
const trace = [], floating = new DataView(new ArrayBuffer(8));
const provider = {
  emit_i64: value => trace.push(`i:${value}`),
  emit_char: value => trace.push(`c:${value}`),
  emit_f64: value => {
    floating.setFloat64(0, value, true);
    trace.push(`f:${Number.isNaN(value) ? 'nan' : floating.getBigUint64(0, true)}`);
  },
};
const imports = {...wasi.wasiImport}, live = new Set();
let memory;
imports.path_open = (...args) => {
  const status = wasi.wasiImport.path_open(...args);
  if (status === 0) live.add(new DataView(memory.buffer).getUint32(args.at(-1), true));
  return status;
};
imports.fd_close = fd => {
  const status = wasi.wasiImport.fd_close(fd);
  if (status === 0) live.delete(fd);
  return status;
};
const instance = new WebAssembly.Instance(module, {'reader.test': provider, wasi_snapshot_preview1: imports});
memory = instance.exports.memory;
try {
  wasi.initialize(instance);
  instance.exports.main();
  assert.equal(instance.exports.check(), 42n);
  assert.equal(instance.exports.storage(), 1);
  const result = instance.exports.scan();
  assert.equal(live.size, 0, 'normal read/error return must close the input');
  trace.push(`result:${result}`);
  process.stdout.write(trace.join('\n') + '\n');
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
  assert.equal(live.size, 0, 'terminal cleanup must close input after a trap');
}
