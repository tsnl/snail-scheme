import fs from 'node:fs';
import assert from 'node:assert/strict';
import {WASI} from 'node:wasi';

// ---- Pathname setup ends before the timed complete repeated file workload ----

const [artifact, specification, mode, providerPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const paths = config.pathnames.map(path => Array.from(path, character => character.codePointAt(0)));
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => ['benchmark', 'wasi_snapshot_preview1', 'snail.library'].includes(entry.module)));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': process.cwd()}, returnOnExit: true});
let barriers = 0;
const imports = {benchmark: {
  barrier: () => { if (mode === '--validate') barriers++; return 1; },
  path_length: which => BigInt(paths[which].length),
  path_character: (which, index) => paths[which][Number(index)],
}, wasi_snapshot_preview1: {...wasi.wasiImport}};
const events = [], live = new Map();
let eofSeen = false;

// ---- Separate traces prove all input precedes output and every iteration closes ----

if (config.trace) {
  imports.wasi_snapshot_preview1.path_open = (...args) => {
    const status = wasi.wasiImport.path_open(...args);
    const pathname = new TextDecoder().decode(new Uint8Array((provider ?? instance).exports.memory.buffer, args[2], args[3]));
    if (status === 0) {
      const descriptor = new DataView((provider ?? instance).exports.memory.buffer).getUint32(args.at(-1), true);
      live.set(descriptor, pathname);
      if (pathname === config.pathnames[0]) eofSeen = false;
    }
    events.push(['open', pathname, status]);
    return status;
  };
  imports.wasi_snapshot_preview1.fd_read = (...args) => {
    const status = wasi.wasiImport.fd_read(...args);
    if (status === 0 && new DataView((provider ?? instance).exports.memory.buffer).getUint32(args.at(-1), true) === 0) {
      eofSeen = true;
      events.push(['eof', live.get(args[0])]);
    }
    return status;
  };
  imports.wasi_snapshot_preview1.fd_write = (...args) => {
    if (live.get(args[0]) === config.pathnames[1]) assert(eofSeen, 'Tail writes only after reading the entire input');
    return wasi.wasiImport.fd_write(...args);
  };
  imports.wasi_snapshot_preview1.fd_close = descriptor => {
    const status = wasi.wasiImport.fd_close(descriptor);
    events.push(['close', live.get(descriptor), status]);
    if (status === 0) live.delete(descriptor);
    return status;
  };
  imports.wasi_snapshot_preview1.path_unlink_file = (...args) => {
    const status = wasi.wasiImport.path_unlink_file(...args);
    events.push(['delete', status]);
    return status;
  };
}
let provider;
if (providerPath) {
  const scalarModule = new WebAssembly.Module(fs.readFileSync(providerPath));
  assert(WebAssembly.Module.imports(scalarModule).every(item => ['snail.platform', 'wasi_snapshot_preview1'].includes(item.module)));
  provider = new WebAssembly.Instance(scalarModule, {wasi_snapshot_preview1: imports.wasi_snapshot_preview1,
    'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)}});
  imports['snail.library'] = provider.exports;
}
const instance = new WebAssembly.Instance(module, imports);
const close = () => provider ? provider.exports['snail:io/close-all']() : instance.exports['close-resources']();
let failure, observation;
try {
  wasi.initialize(provider ?? instance);
  instance.exports.main();
  if (mode === '--validate') assert.equal(barriers, config.setup_barriers);
  const start = process.hrtime.bigint();
  const result = instance.exports.bench(BigInt(config.count));
  const seconds = Number(process.hrtime.bigint() - start) / 1e9;
  assert.equal(result, 1n); // The original predicate is always true; file checks are separate.
  if (mode === '--validate') assert.equal(barriers, 2 * Math.max(0, Number(config.count)));
  if (config.trace) {
    assert.equal(live.size, 0, 'each worker closes its own input and output');
    assert.equal(events.filter(event => event[0] === 'open' && event[2] === 0).length, 2 * config.count);
    assert.equal(events.filter(event => event[0] === 'close' && event[2] === 0).length, 2 * config.count);
    assert.equal(events.filter(event => event[0] === 'eof').length, config.count);
    assert.equal(events.filter(event => event[0] === 'delete' && event[1] === 0).length, Math.max(0, config.count - 1));
  }
  observation = {seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null};
} catch (error) { failure = error; }
finally {
  try { assert.equal(close(), 0); }
  catch (error) { failure ??= error; }
}
if (failure) throw failure;
if (config.trace) {
  assert.equal(live.size, 0);
  observation.events = events;
}
console.log(JSON.stringify(observation));
