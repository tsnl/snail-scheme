// Exposed functions take and return the references they are given, and an
// Option Any crosses as a nullable reference.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../../host/browser/load.mjs';
const wasi = createWasi({print: (fd, line) => { throw new Error(line); }});
const module = await WebAssembly.compile(await readFile(process.argv[2]));
const instance = await instantiate(module, wasi.getImportObject());
wasi.initialize(instance);
const api = instance.exports;
assert.throws(() => api.read(null), TypeError);
const resource = api.create(42n), alias = api.alias(resource), pair = api.duplicate(resource);
assert.equal(alias, resource);
assert.throws(() => api.read(pair), TypeError);
assert.throws(() => api.read(16), TypeError);
const secondWasi = createWasi({print: () => {}});
const second = await instantiate(module, secondWasi.getImportObject());
secondWasi.initialize(second);
assert.throws(() => second.exports.read(resource), TypeError);
assert.equal(second.exports.read(second.exports.create(7n)), 7n);
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

// A host callback can retain a guest handle, as a scheduler does. Drop the
// entire instance and callback together. Its root finalizer must let both go.
async function abandonedMemory() {
  const host = {};
  const ownWasi = createWasi({print: () => host.value});
  const guest = await instantiate(module, ownWasi.getImportObject());
  ownWasi.initialize(guest);
  host.value = guest.exports.create(42n);
  return new WeakRef(guest.exports.memory);
}
assert.ok(WebAssembly.Module.imports(module).some(entry => entry.name === 'fd_write'));
const abandoned = await abandonedMemory();
for (let i = 0; i < 12 && abandoned.deref(); i++) {
  // A weak dereference keeps its target alive for the current job.
  await new Promise(resolve => setImmediate(resolve));
  global.gc();
}
assert.equal(abandoned.deref(), undefined, 'an abandoned host/guest cycle releases the entire instance');
console.log('host values: aliases, nullable Any and collection of an abandoned instance');
