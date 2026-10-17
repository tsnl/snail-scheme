import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- Observe owned descriptors and preserve the borrowed standard stream ----

const [artifact, directory, worker, expected, failure] = process.argv.slice(2);
const stdin = fs.openSync(path.join(directory, 'input.txt'), 'r');
const wasi = new WASI({version: 'preview1', args: [], env: {}, stdin,
  preopens: {'.': directory}, returnOnExit: true});
const imports = {...wasi.wasiImport}, live = new Set();
let memory, opened = 0, closed = 0;
imports.path_open = (...args) => {
  const status = wasi.wasiImport.path_open(...args);
  if (status === 0) {
    live.add(new DataView(memory.buffer).getUint32(args.at(-1), true));
    opened++;
  }
  return status;
};
imports.fd_close = fd => {
  const status = wasi.wasiImport.fd_close(fd);
  if (status === 0 && live.delete(fd)) closed++;
  return status;
};

// ---- A cached EOF survives peek; consuming it exposes appended input ----

function eofGrowth(api) {
  api['open-growing']();
  for (const byte of ['A', 'B']) {
    assert.equal(api['peek-growing'](), -1n);
    fs.appendFileSync(path.join(directory, 'input.txt'), byte);
    assert.equal(api['peek-growing'](), -1n);
    assert.equal(api['read-growing'](), -1n);
    assert.equal(api['peek-growing'](), BigInt(byte.charCodeAt(0)));
    assert.equal(api['read-growing'](), BigInt(byte.charCodeAt(0)));
  }
  api['close-growing']();
}

// ---- Each failure leaves a terminal instance with all owned files released ----

const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: imports});
memory = instance.exports.memory;
let failed = false;
try {
  wasi.initialize(instance);
  instance.exports.main();
  if (worker === 'eof-growth') eofGrowth(instance.exports);
  else {
    const result = instance.exports[worker]();
    if (failure === '0') assert.equal(BigInt(result), BigInt(expected));
  }
} catch (error) {
  if (failure === '0') throw error;
  failed = true;
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
  assert.equal(live.size, 0);
  assert.equal(closed, opened);
  fs.fstatSync(stdin);
  fs.closeSync(stdin);
}
assert.equal(failed, failure === '1');
console.log(JSON.stringify({failed, opened, closed, borrowedOpen: true}));
process.exitCode = Number(failed);
