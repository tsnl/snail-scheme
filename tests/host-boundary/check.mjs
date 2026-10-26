// The actual Wasm boundary: nullable opaque handovers and borrowed byte records.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, runProgram, programExports} from '../../src/app/load.mjs';

let program, api, constructors, memory, number = 42;
const seen = [], errors = [];
const held = Promise.withResolvers();
let retained;
const wasi = createWasi({print: (fd, line) => { if (fd === 2) errors.push(line); }});
const host = {'snail.test': {
  text(count) { seen.push(['text', count]); return 7; },
  bytes(marker, address) {
    const pointer = address >>> 0, buffer = memory.buffer;
    const length = new DataView(buffer).getUint32(pointer, true);
    seen.push(['bytes', marker, [...new Uint8Array(buffer, pointer + 4, length)]]);
    return length;
  },
  hold: new WebAssembly.Suspending(async address => {
    const pointer = address >>> 0, buffer = memory.buffer;
    const length = new DataView(buffer).getUint32(pointer, true);
    retained = new Uint8Array(buffer, pointer + 4, length).slice();
    await held.promise;
    return retained.length;
  }),
  managed: new WebAssembly.Suspending(async () => {
    await Promise.resolve();
    // Synchronous Wasm helpers own construction. JavaScript only carries refs.
    const bytes = constructors['payload-buffer'](4);
    for (const [index, byte] of [0, 255, 128, 1].entries()) constructors['payload-put'](bytes, index, byte);
    const result = constructors['payload-finish'](number, bytes);
    constructors['payload-put'](bytes, 2, 0); // Finished Bytes must own their copy.
    return result;
  }),
}};
const filename = resolve(process.argv[2]);
if (filename.endsWith('.json')) {
  program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  api = programExports(program);
  constructors = program.linked.get('boundary.value').exports;
  memory = program.runtime.exports.memory;
  runProgram(program);
} else {
  const instance = await instantiate(await WebAssembly.compile(await readFile(filename)), {...wasi.getImportObject(), ...host});
  wasi.initialize(instance);
  api = constructors = instance.exports;
  memory = api.memory;
  api.main();
}
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
const result = await WebAssembly.promising(api.managed)();
assert.equal(api['result-number'](result), 42);
assert.equal(api['inspect-bytes'](api['result-bytes'](result)), 128);
assert.throws(() => api['result-number']({}), TypeError);
assert.throws(() => api['inspect-bytes'](new Uint8Array(4)), TypeError);
number = -1;
assert.equal(api['result-number'](await WebAssembly.promising(api.managed)()), -1);
console.log('host boundary: opaque values, typed managed results, owned bytes and JSPI');
