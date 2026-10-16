// Optional engine parity check for the standalone test's optimized Wasm.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {
  example: { example_hide: value => value },
});
assert.equal(instance.exports.run(40n), 42n);
assert.equal(instance.exports.run(1n), 3n);
assert.equal(instance.exports.previous(), 42n);
assert.equal(instance.exports["take-root"](), 3n);
assert.throws(() => instance.exports.trap(), WebAssembly.RuntimeError);
console.log("42");
