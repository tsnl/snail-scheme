import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- Real WASI streams, owned files and observed terminal cleanup ----

const [artifact, directory, action] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': directory}, returnOnExit: true});
const imports = {...wasi.wasiImport};
const live = new Set();
const ownership = {opened: 0, closed: 0, standardClosed: [], closesBeforeCleanup: 0};
let memory, exitCode;
imports.proc_exit = code => {
  exitCode = code;
  return wasi.wasiImport.proc_exit(code);
};
imports.path_open = (...args) => {
  const status = wasi.wasiImport.path_open(...args);
  if (status === 0) {
    live.add(new DataView(memory.buffer).getUint32(args.at(-1), true));
    ownership.opened++;
  }
  return status;
};
imports.fd_close = fd => {
  if (fd <= 2) ownership.standardClosed.push(fd);
  const status = wasi.wasiImport.fd_close(fd);
  if (status === 0 && live.delete(fd)) ownership.closed++;
  return status;
};
imports.fd_write = (...args) => action === 'stdout-failure' && args[0] === 1 ? 29 : wasi.wasiImport.fd_write(...args);
const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: imports});
const api = instance.exports;
memory = api.memory;
const failures = new Set(['closed', 'trap', 'character', 'handle', 'read-stdout', 'stdout-failure']);
try {
  wasi.initialize(instance);
  api.main();
  const invoke = () => {
    if (action === 'stream') {
      assert(api['copy-output']() > 0n);
      assert.equal(api.roundtrip(), 1);
    } else {
      const names = {graphs: 'graphs', deep: 'deep-output', stdout: 'stdout-check', closed: 'closed-empty',
        trap: 'callback-trap', character: 'invalid-character', handle: 'invalid-handle',
        'read-stdout': 'read-stdout', 'stdout-failure': 'stdout-failure'};
      api[names[action]]();
    }
  };
  if (action === 'trap') assert.throws(invoke, WebAssembly.RuntimeError);
  else if (failures.has(action)) {
    // Fatal Rust diagnostics deliberately exit through WASI. Node represents
    // returnOnExit as a private sentinel, rather than a WebAssembly trap.
    assert.throws(invoke);
    assert.equal(exitCode, 1);
  } else invoke();
} finally {
  ownership.closesBeforeCleanup = ownership.closed;
  assert.equal(api['close-resources'](), 0);
  assert.equal(api['close-resources'](), 0);
  assert.equal(live.size, 0);
  assert.equal(ownership.closed, ownership.opened);
  assert.deepEqual(ownership.standardClosed, []);
  if (failures.has(action) && action !== 'trap') assert.equal(ownership.closesBeforeCleanup, 1);
  fs.writeFileSync(path.join(directory, 'ownership.json'), JSON.stringify(ownership, null, 2) + '\n');
}
