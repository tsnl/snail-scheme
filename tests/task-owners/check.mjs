import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../../host/browser/load.mjs';
const released = [], wasi = createWasi({print: (fd, line) => { throw new Error(line); }});
const instance = await instantiate(await WebAssembly.compile(await readFile(process.argv[2])), {
  ...wasi.getImportObject(), 'test.owners': {released: value => released.push(value)},
});
wasi.initialize(instance);
const api = instance.exports;
const a = api['tasks:create'](), b = api['tasks:create'](), weak = api.watch(a);
api.seed(a, 10n); api.seed(b, 20n);
assert.equal(api['tasks:turn'](a, 1000n), 0n);
assert.deepEqual(released, []);
api['tasks:close'](a);
assert.deepEqual(released, [10n]);
assert.equal(api['tasks:wake'](a, 1n), 0);
api['tasks:create:release-result'](a);
assert.equal(api.alive(weak), 0, 'saved handler contexts must not retain their scheduler');
assert.equal(api['tasks:turn'](b, 1000n), 0n);
assert.equal(api['tasks:turn'](b, 1001n), -1n);
assert.deepEqual(released, [10n, 20n]);
api['tasks:close'](b); api['tasks:create:release-result'](b);
const c = api['tasks:create'](), unstarted = api.watch(c);
api.seed(c, 30n);
api['tasks:create:release-result'](c);
assert.equal(api.alive(unstarted), 0);
assert.deepEqual(released, [10n, 20n, 30n]);
assert.equal(api['close-resources'](), 0);
console.log('task owners: isolated schedulers, canceled resumes, weak contexts and unstarted cleanup');
