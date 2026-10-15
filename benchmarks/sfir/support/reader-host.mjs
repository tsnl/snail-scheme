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
const cycles = {setup: [], worker: [], cleanup: []}, deleted = [];
const writeCharacter = value => fs.writeSync(1, String.fromCodePoint(value));
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
  if (status === 0) live.set(new DataView(memory.buffer).getUint32(args.at(-1), true),
                            {path, read: 0, written: 0, eof: false});
  phases[phase].push(['open', path, status]);
  return status;
};
imports.fd_read = (...args) => {
  const status = wasi.wasiImport.fd_read(...args);
  if (status === 0 && live.has(args[0])) {
    const file = live.get(args[0]), bytes = new DataView(memory.buffer).getUint32(args.at(-1), true);
    assert(!file.eof, 'read continued after EOF');
    file.read += bytes;
    file.eof = bytes === 0;
    phases[phase].push(['read', file.path, bytes]);
  }
  return status;
};
imports.fd_write = (...args) => {
  const status = wasi.wasiImport.fd_write(...args);
  if (status === 0 && live.has(args[0])) {
    const file = live.get(args[0]), bytes = new DataView(memory.buffer).getUint32(args.at(-1), true);
    file.written += bytes;
    phases[phase].push(['write', file.path, bytes]);
  }
  return status;
};
imports.fd_close = descriptor => {
  const file = live.get(descriptor);
  const status = wasi.wasiImport.fd_close(descriptor);
  phases[phase].push(['close', file?.path, status]);
  if (status === 0) {
    if (file) cycles[phase].push(file);
    live.delete(descriptor);
  }
  return status;
};
imports.path_unlink_file = (...args) => {
  const path = new TextDecoder().decode(new Uint8Array(memory.buffer, args[1], args[2]));
  const status = wasi.wasiImport.path_unlink_file(...args);
  deleted.push({phase, path, status});
  return status;
};
let provider;
if (providerPath) {
  const scalarModule = new WebAssembly.Module(fs.readFileSync(providerPath));
  assert(WebAssembly.Module.imports(scalarModule).every(item => ['snail.platform', 'wasi_snapshot_preview1'].includes(item.module)));
  provider = new WebAssembly.Instance(scalarModule, {wasi_snapshot_preview1: imports,
    'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)}});
}
const instance = new WebAssembly.Instance(module, {benchmark: {barrier: () => {barriers++; return 1;},
                                                  write_character: writeCharacter, write_char: writeCharacter},
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
  if (!config.observe) {
    assert.equal(result, BigInt(config.expected), 'complete benchmark predicate');
    assert.equal(barriers, (config.barriers_per_iteration ?? config.worker_barriers) * config.count);
    validateFileCycles();
  }
} catch (error) { failure = error; }
finally {
  phase = 'cleanup';
  try { assert.equal(close(), 0); assert.equal(live.size, 0); }
  catch (error) { failure ??= error; }
}
const closed = name => phases[name].filter(event => event[0] === 'close').length;
if (failure) {
  console.log(JSON.stringify({failed: true, barriers, setup_closed: closed('setup'),
                             worker_closed: closed('worker'), cleanup_closed: closed('cleanup'), phases, cycles, deleted}));
  throw failure;
}
console.log(JSON.stringify({result: Number(result), barriers, setup_closed: closed('setup'),
                           worker_closed: closed('worker'), phases, cycles, deleted, ...(config.observe ? {trace} : {})}));

// ---- Each input cycle consumes its whole file; output cycles retain their bytes ----

function validateFileCycles() {
  assert.equal(cycles.setup.length, 1);
  assert.equal(cycles.setup[0].path, 'input.txt');
  assert.equal(cycles.setup[0].read, fs.statSync('input.txt').size);
  const paths = config.pathnames ?? [];
  assert.equal(cycles.worker.length, paths.length * config.count);
  for (const path of paths) validatePathCycles(path);
  if (config.name === 'cat') {
    assert.deepEqual(fs.readFileSync(paths[0]), fs.readFileSync(paths[1]));
    assert.equal(deleted.length, Math.max(0, config.count - 1));
    assert(deleted.every(item => item.phase === 'worker' && item.path === paths[1] && item.status === 0));
  }
}

function validatePathCycles(path) {
  const matching = cycles.worker.filter(item => item.path === path);
  assert.equal(matching.length, config.count);
  for (const cycle of matching) {
    if (path.startsWith('outputs/')) assert.equal(cycle.written, fs.statSync(path).size);
    else {
      assert.equal(cycle.read, fs.statSync(path).size);
      assert(cycle.eof, 'input cycle did not reach EOF');
    }
  }
}
