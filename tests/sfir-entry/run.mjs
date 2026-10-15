import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const module = new WebAssembly.Module(readFileSync(process.argv[2]));
assert.deepEqual(WebAssembly.Module.imports(module), []);
for (let index = 0; index < 2; index++) {
  const api = new WebAssembly.Instance(module).exports;
  assert.equal(api.count.value, 0);
  assert.throws(() => api.entry(1), WebAssembly.RuntimeError);
  assert.equal(api.main(), undefined);
  assert.equal(api.count.value, 1, 'library aliases initialize once');
  assert.equal(api.entry(1), 42);
  assert.equal(api.entry(2), 43);
  assert.throws(() => api.main(), WebAssembly.RuntimeError);
  assert.equal(api.count.value, 1);
  assert.equal(api.entry(1), 42);
}
