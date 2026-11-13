// Each returned reference carries a host ownership credit, including aliases.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../../host/browser/load.mjs';
const released = [], wasi = createWasi({print: (fd, line) => { throw new Error(line); }});
const instance = await instantiate(await WebAssembly.compile(await readFile(process.argv[2])), {
  ...wasi.getImportObject(), 'test.owners': {released: value => released.push(value)},
});
wasi.initialize(instance);
const api = instance.exports;
const owner = api.create(42n), alias = api.alias(owner), pair = api.duplicate(owner);
for (let i = 0; i < 3; i++) {
  assert.equal(api.read(owner), 42n);
  assert.equal(api.combine(owner, owner), 84n);
  assert.equal(api['pair-value'](pair), 84n);
}
api['create:release-result'](owner);
api['alias:release-result'](alias);
assert.deepEqual(released, []);
assert.equal(api['pair-value'](pair), 84n);
api['duplicate:release-result'](pair);
assert.deepEqual(released, [42n]);
for (const value of [20n, -1n]) {
  const optional = api.optional(value);
  for (let i = 0; i < 3; i++) assert.equal(api['optional-value'](optional), value < 0 ? -1n : value + 1n);
  api['optional:release-result'](optional);
}
assert.equal(api['close-resources'](), 0);
console.log('host owners: repeated calls, aliased arguments, independent result credits and nullable Any');
