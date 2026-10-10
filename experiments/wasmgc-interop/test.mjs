import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const [bridgePath, extensionPath] = process.argv.slice(2);
assert.equal(typeof globalThis.gc, "function", "run Node with --expose-gc");
const bridge = (await WebAssembly.instantiate(await readFile(bridgePath))).instance.exports;
const extension = extensionPath
  ? (await WebAssembly.instantiate(await readFile(extensionPath), { scheme: bridge })).instance.exports
  : bridge;

// Every Rust accessor import points directly at a Wasm function. JavaScript
// orchestrates whole test calls and forced collections, never individual fields.
assert(extension.memory instanceof WebAssembly.Memory);
assert.equal(bridge.live_roots(), 0);
const original = bridge.make_pair(20, 22);
assert.equal(extension.pair_sum(original, 8), 50);
const saved = extension.save_pair(original);
assert.notEqual(saved, original);
bridge.release(original);
assert.equal(bridge.live_roots(), 1);

for (let i = 0; i < 5; i++) {
  bridge.churn(100000);
  bridge.discard_garbage();
  globalThis.gc();
  assert.equal(extension.pair_sum(saved, 0), 42);
}

const shifted = extension.shifted_pair(saved, 10);
assert.equal(bridge.live_roots(), 2);
globalThis.gc();
assert.equal(bridge.take_sum(shifted), 62);
assert.equal(bridge.live_roots(), 1);
assert.throws(() => bridge.first(shifted), WebAssembly.RuntimeError);

// Replacing Rust's owner drops the previous root. Clearing it drops the last
// root. Slot counts prove release, not an engine-specific collection schedule.
const replacement = bridge.make_pair(3, 4);
const replacementSaved = extension.save_pair(replacement);
assert.equal(bridge.live_roots(), 2);
bridge.release(replacement);
globalThis.gc();
assert.equal(extension.pair_sum(replacementSaved, 0), 7);
extension.clear_saved_pair();
assert.equal(bridge.live_roots(), 0);
assert.throws(() => bridge.first(replacementSaved), WebAssembly.RuntimeError);
extension.clear_saved_pair();
assert.equal(bridge.live_roots(), 0);

console.log(JSON.stringify({
  status: "ok", forcedCollections: 7, peakLiveHandles: 3,
  finalLiveHandles: bridge.live_roots(), linearMemoryBytes: extension.memory.buffer.byteLength,
  node: process.version, linked: !extensionPath,
}));
