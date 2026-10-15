import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- Actual linked workers, exact scalar fields and owned failure cleanup ----

const [artifact, directory, action, operation, code] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': directory}, returnOnExit: true});
const imports = {...wasi.wasiImport};
let closed = 0, exitCode;
imports.fd_close = fd => { closed++; return wasi.wasiImport.fd_close(fd); };
imports.proc_exit = status => { exitCode = status; return wasi.wasiImport.proc_exit(status); };
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: imports});
const api = instance.exports;
try {
  wasi.initialize(instance);
  api.main();
  if (action === 'scalars') {
    for (const row of fs.readFileSync(path.join(directory, 'scalars.txt'), 'utf8').trim().split('\n')) {
      const value = Number(row.split(' ')[0]);
      console.log([value, api.lower(value), api.alphabetic(value), api.numeric(value), api.whitespace(value)].join(' '));
    }
  } else if (action === 'strings') {
    for (const line of fs.readFileSync(path.join(directory, 'strings.txt'), 'utf8').trim().split('\n')) {
      const [a, b, expected, ...characters] = line.split(' ').map(Number);
      api['fresh-strings'](BigInt(a), BigInt(b));
      for (let index = 0; index < a; index++) api['fill-left'](BigInt(index), characters[index]);
      for (let index = 0; index < b; index++) api['fill-right'](BigInt(index), characters[a + index]);
      console.log(api.ordered());
      assert.equal(api['self-ordered'](), 0);
      assert.equal(api.ordered(), expected);
    }
    api['fresh-strings'](1n, 1n);
    api['fill-left'](0n, 97); api['fill-right'](0n, 98); assert.equal(api.ordered(), 1);
    api['fill-left'](0n, 99); assert.equal(api.ordered(), 0);
    api['fill-left'](0n, 98); assert.equal(api.ordered(), 0);
    api['fill-right'](0n, 99); assert.equal(api.ordered(), 1);
  } else {
    assert.equal(action, 'malformed');
    assert.throws(() => api.malformed(BigInt(operation), Number(code)));
    assert.equal(exitCode, 1);
    assert.equal(closed, 1, 'Rust releases the pending file before reporting failure');
  }
} finally {
  assert.equal(api['close-resources'](), 0);
  assert.equal(api['close-resources'](), 0);
}
