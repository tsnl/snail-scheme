import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createIdentityHasher } from '../src/runtime/host.mjs';

const hash = createIdentityHasher();
const { instance } = await WebAssembly.instantiate(await readFile(process.argv[2]), {
  'snail.host': { 'hash-identity': hash },
});
const wasm = instance.exports;
const nextJob = () => new Promise(resolve => setImmediate(resolve));
wasm.pin();
const saved = wasm.hash();
for (let round = 0; round < 12; ++round) {
  await nextJob();
  global.gc();
  assert.equal(wasm.hash(), saved, 'identity must survive with only Wasm retaining it');
}
for (const value of [0, -1, 1, -1073741824, 1073741823]) {
  assert.equal(wasm.immediate(value), hash(value));
}
const weak = new WeakRef(wasm.get());
wasm.drop();
let collected = false;
for (let round = 0; round < 100; ++round) {
  await nextJob();
  global.gc();
  if (weak.deref() === undefined) { collected = true; break; }
}
assert.ok(collected, 'the enduring identity hasher must not retain a dead self-cycle');
console.log('Wasm identity hash lifetime checks passed');
