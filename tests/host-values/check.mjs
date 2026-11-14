// Exposed functions take and return the references they are given, and an
// Option Any crosses as a nullable reference.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../../host/browser/load.mjs';
const wasi = createWasi({print: (fd, line) => { throw new Error(line); }});
const instance = await instantiate(await WebAssembly.compile(await readFile(process.argv[2])),
  wasi.getImportObject());
wasi.initialize(instance);
const api = instance.exports;
assert.throws(() => api.read(null), TypeError);
const resource = api.create(42n), alias = api.alias(resource), pair = api.duplicate(resource);
assert.equal(alias, resource);
for (let i = 0; i < 3; i++) {
  assert.equal(api.read(resource), 42n);
  assert.equal(api.combine(resource, alias), 84n);
  assert.equal(api['pair-value'](pair), 84n);
}
for (const value of [20n, -1n]) {
  const optional = api.optional(value);
  for (let i = 0; i < 3; i++) assert.equal(api['optional-value'](optional), value < 0 ? -1n : value + 1n);
}
assert.equal(api['close-resources'](), 0);
console.log('host values: repeated calls, aliased arguments and nullable Any');
