// The actual Wasm boundary: nullable opaque handovers and borrowed byte records.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWasi, instantiate} from '../../src/app/load.mjs';

let instance;
const seen = [], errors = [];
const held = Promise.withResolvers();
let retained;
const wasi = createWasi({print: (fd, line) => { if (fd === 2) errors.push(line); }});
instance = await instantiate(await WebAssembly.compile(await readFile(process.argv[2])), {...wasi.getImportObject(), 'snail.test': {
  text(count) { seen.push(['text', count]); return 7; },
  bytes(marker, address) {
    const pointer = address >>> 0, memory = instance.exports.memory.buffer;
    const length = new DataView(memory).getUint32(pointer, true);
    seen.push(['bytes', marker, [...new Uint8Array(memory, pointer + 4, length)]]);
    return length;
  },
  hold: new WebAssembly.Suspending(async address => {
    const pointer = address >>> 0, memory = instance.exports.memory.buffer;
    const length = new DataView(memory).getUint32(pointer, true);
    retained = new Uint8Array(memory, pointer + 4, length).slice();
    await held.promise;
    return retained.length;
  }),
}});
wasi.initialize(instance);
const api = instance.exports;
api.main();
assert.equal(api.echo(null), null);
assert.equal(api.value(null), -1n);
const state = api.state();
assert.equal(api.echo(state), state);
assert.equal(api.value(state), 42n);
assert.throws(() => api.echo(42), TypeError);
api.discard(null);
api.discard(state);
assert.throws(() => api.fail());
assert.match(errors.join('\n'), /a deliberate boundary trap/);
assert.equal(api.value(api.state()), 42n, 'a trap preserves the opaque checkpoint');
assert.equal(api.binary(), 4);
const pending = WebAssembly.promising(api.held)();
assert.equal(api.empty(), 0);
held.resolve();
assert.equal(await pending, 4);
assert.deepEqual([...retained], [0, 255, 128, 1], 'owned bytes survive suspension and staging reuse');
assert.deepEqual(seen, [['text', 1], ['bytes', 7, [0, 255, 128, 1]], ['bytes', 0, []]]);
