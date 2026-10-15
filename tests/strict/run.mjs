import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// ---- Native entry point ----

const [path, expected, checks = '{}'] = process.argv.slice(2);
const bytes = await readFile(path);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), [], 'pure fixtures require no runtime');
const instance = await WebAssembly.instantiate(module);
assert.equal(typeof instance.exports.main, 'function');
if (expected === 'trap') {
  assert.throws(() => instance.exports.main(), WebAssembly.RuntimeError);
  console.log('expected runtime type rejection');
} else {
  const value = instance.exports.main();
  assert.equal(String(value), expected);
  console.log(`result ${typeof value} ${String(value)}`);
}

// Exported probes can observe effects after a checked operation traps.
for (const [name, result] of Object.entries(JSON.parse(checks))) {
  assert.equal(typeof instance.exports[name], 'function');
  if (result === 'trap') {
    assert.throws(() => instance.exports[name](), WebAssembly.RuntimeError, name);
  } else {
    assert.equal(String(instance.exports[name]()), result, name);
  }
}
