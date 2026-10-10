// Integration test: the production JS shim observes a real WasmGC object.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createFinalizers } from '../src/runtime/host.mjs';

const { instance } = await WebAssembly.instantiate(await readFile(process.argv[2]));
const wasm = instance.exports;
const notices = [];
const finalizers = createFinalizers((kind, id) => notices.push([kind, id]));

function registerObjects() {
  const held = wasm.make();
  finalizers.register(held, 1, 42);
  wasm.hold(held);
  const closed = wasm.make();
  finalizers.register(closed, 1, 43);
  finalizers.unregister(closed);
}

async function collect() {
  global.gc();
  await new Promise(setImmediate);
}

registerObjects();
for (let i = 0; i < 5; i++) await collect();
assert.deepEqual(notices, [], 'Wasm roots retain objects; unregister cancels cleanup');
wasm.release();
for (let i = 0; i < 100 && notices.length === 0; i++) await collect();
assert.deepEqual(notices, [[1, 42]], 'cleanup receives only the released resource ID');
console.log('WasmGC host finalization checks passed');
