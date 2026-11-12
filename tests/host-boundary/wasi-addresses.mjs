// Exercise the upper half of wasm32 without reserving a multi-gigabyte buffer.
// These views model a small window at 0x80000000; Wasm supplies signed i32s.
import assert from 'node:assert/strict';
import {createWasi} from '../../host/browser/load.mjs';
import {Exit, exiting} from '../../host/native/wasi.mjs';

const base = 0x80000000, storage = new ArrayBuffer(128);
const NativeView = globalThis.DataView, NativeBytes = globalThis.Uint8Array;
const view = new NativeView(storage), memory = {buffer: storage}, lines = [];
const wasi = createWasi({args: ['hello'], print: (fd, text) => lines.push([fd, text])});
wasi.initialize({exports: {memory, _initialize() {}}});
const offset = address => {
  assert.ok(address >= base && address < base + storage.byteLength, 'an unsigned wasm32 address');
  return address - base;
};
try {
  globalThis.DataView = class extends NativeView {
    setUint32(address, ...args) { return super.setUint32(offset(address), ...args); }
    getUint32(address, ...args) { return super.getUint32(offset(address), ...args); }
    setBigUint64(address, ...args) { return super.setBigUint64(offset(address), ...args); }
  };
  globalThis.Uint8Array = class extends NativeBytes {
    constructor(buffer, address, length) { super(buffer, offset(address), length); }
  };
  const api = wasi.getImportObject().wasi_snapshot_preview1;
  api.args_sizes_get(base | 0, (base + 4) | 0);
  assert.equal(view.getUint32(0, true), 1);
  assert.equal(view.getUint32(4, true), 6);
  api.args_get((base + 8) | 0, (base + 32) | 0);
  assert.equal(view.getUint32(8, true), base + 32);
  assert.equal(new TextDecoder().decode(new NativeBytes(storage, 32, 6)), 'hello\0');
  api.environ_sizes_get((base + 16) | 0, (base + 20) | 0);
  assert.equal(view.getUint32(16, true), 0);
  assert.equal(view.getUint32(20, true), 0);
  new NativeBytes(storage, 32, 6).set(new TextEncoder().encode('hello\n'));
  view.setUint32(72, base + 32, true);
  view.setUint32(76, 6, true);
  api.fd_write(1, (base + 72) | 0, 1, (base + 80) | 0);
  assert.deepEqual(lines, [[1, 'hello']]);
  assert.equal(view.getUint32(80, true), 6);
  assert.equal(api.random_get((base + 88) | 0, 4), 0);
  api.clock_time_get(0, 0n, (base + 96) | 0);
  assert.ok(view.getBigUint64(96, true) > 0n);
} finally {
  globalThis.DataView = NativeView;
  globalThis.Uint8Array = NativeBytes;
}

// Node's native methods reject negative i32 addresses (fd_readdir returns
// EINVAL). The bridge must normalize every preview1 i32, preserving i64s.
const calls = [], initialized = [];
const native = exiting({
  getImportObject: () => ({wasi_snapshot_preview1: Object.fromEntries(
    ['fd_readdir', 'fd_seek', 'path_open'].map(name =>
      [name, (...args) => { calls.push([name, ...args]); return 0; }]))}),
  initialize: instance => initialized.push(instance),
});
const api = native.getImportObject().wasi_snapshot_preview1;
api.fd_readdir(4, base | 0, 4096, 0n, (base + 16) | 0);
api.fd_seek(4, -5n, 2, base | 0);
api.path_open(3, 1, base | 0, 12, 5, 0n, 0n, 0, (base + 24) | 0);
assert.deepEqual(calls, [
  ['fd_readdir', 4, base, 4096, 0n, base + 16],
  ['fd_seek', 4, -5n, 2, base],
  ['path_open', 3, 0, base, 12, 5, 0n, 0n, 0, base + 24],
]);
assert.throws(() => api.proc_exit(-1), error => error instanceof Exit && error.code === 0xffffffff);
native.initialize(memory);
assert.deepEqual(initialized, [memory]);
