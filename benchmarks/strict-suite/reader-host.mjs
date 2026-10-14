import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Setup and repeated worker I/O remain distinct observable phases ----

const [artifact, specification, providerPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(item => ['benchmark', 'reader.test', 'wasi_snapshot_preview1', 'snail.library'].includes(item.module)));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': process.cwd()}, returnOnExit: true});
const live = new Map(), phases = {setup: [], worker: [], cleanup: []};
let memory, phase = 'setup', barriers = 0;
const trace = [], floating = new DataView(new ArrayBuffer(8));
const observer = {
  emit_i64: value => trace.push(`i:${value}`),
  emit_char: value => trace.push(`c:${value}`),
  emit_f64: value => {
    floating.setFloat64(0, value, true);
    trace.push(`f:${Number.isNaN(value) ? 'nan' : floating.getBigUint64(0, true)}`);
  },
};
const imports = {...wasi.wasiImport};
imports.path_open = (...args) => {
  const path = new TextDecoder().decode(new Uint8Array(memory.buffer, args[2], args[3]));
  const status = wasi.wasiImport.path_open(...args);
  if (status === 0) live.set(new DataView(memory.buffer).getUint32(args.at(-1), true), path);
  phases[phase].push(['open', path, status]);
  return status;
};
imports.fd_read = (...args) => {
  const status = wasi.wasiImport.fd_read(...args);
  if (status === 0 && live.has(args[0])) {
    phases[phase].push(['read', live.get(args[0]), new DataView(memory.buffer).getUint32(args.at(-1), true)]);
  }
  return status;
};
imports.fd_close = descriptor => {
  const status = wasi.wasiImport.fd_close(descriptor);
  phases[phase].push(['close', live.get(descriptor), status]);
  if (status === 0) live.delete(descriptor);
  return status;
};
let provider;
if (providerPath) {
  const scalarModule = new WebAssembly.Module(fs.readFileSync(providerPath));
  assert(WebAssembly.Module.imports(scalarModule).every(item => ['snail.platform', 'wasi_snapshot_preview1'].includes(item.module)));
  provider = new WebAssembly.Instance(scalarModule, {wasi_snapshot_preview1: imports,
    'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)}});
}
const instance = new WebAssembly.Instance(module, {benchmark: {barrier: () => {barriers++; return 1;}},
                                                  'reader.test': observer, 'snail.library': provider?.exports,
                                                  wasi_snapshot_preview1: imports});
memory = (provider ?? instance).exports.memory;
const close = () => provider ? provider.exports['snail:io/close-all']() : instance.exports['close-resources']();
let result, failure;
try {
  wasi.initialize(provider ?? instance);
  instance.exports.main();
  assert.equal(instance.exports['configured-count'](), BigInt(config.count));
  assert.equal(barriers, 0);
  assert.equal(live.size, 0);
  phase = 'worker';
  if (config.observe) {
    for (let index = 0; index < (config.replacement ? 2 : 1); index++) {
      if (index) fs.copyFileSync(config.replacement, config.pathnames[0]);
      trace.push(`call:${index}`);
      result = instance.exports['observe-once']();
    }
  } else result = instance.exports.bench(BigInt(config.count));
  assert.equal(live.size, 0);
} catch (error) { failure = error; }
finally {
  phase = 'cleanup';
  try { assert.equal(close(), 0); assert.equal(live.size, 0); }
  catch (error) { failure ??= error; }
}
const closed = name => phases[name].filter(event => event[0] === 'close').length;
if (failure) {
  console.log(JSON.stringify({failed: true, barriers, setup_closed: closed('setup'),
                             worker_closed: closed('worker'), cleanup_closed: closed('cleanup'), phases}));
  throw failure;
}
console.log(JSON.stringify({result: Number(result), barriers, setup_closed: closed('setup'),
                           worker_closed: closed('worker'), phases, ...(config.observe ? {trace} : {})}));
