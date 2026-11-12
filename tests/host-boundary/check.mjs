// The actual Wasm boundary: nullable opaque handovers and borrowed byte records.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, runProgram, programExports} from '../../host/browser/load.mjs';
import {hostExports, retireProgram} from '../../host/browser/memory.mjs';

let program, api, constructors, memory, gc, number = 42;
const seen = [], errors = [];
const wasi = createWasi({print: (fd, line) => { if (fd === 2) errors.push(line); }});
const host = {'snail.test': {
  text(count) { seen.push(['text', count]); return 7; },
  bytes(marker, address) {
    const pointer = address >>> 0, buffer = memory.buffer;
    const length = new DataView(buffer).getUint32(pointer, true);
    seen.push(['bytes', marker, [...new Uint8Array(buffer, pointer + 4, length)]]);
    return length;
  },
  managed() {
    // Wasm helpers own construction. JavaScript only carries refs.
    const bytes = constructors['payload-buffer'](4);
    assert.throws(() => api.fail(), 'a nested trap restores only the nested root scope');
    for (const [index, byte] of [0, 255, 128, 1].entries()) constructors['payload-put'](bytes, index, byte);
    const result = constructors['payload-finish'](number, bytes);
    constructors['payload-put'](bytes, 2, 0); // Finished Bytes must own their copy.
    return result;
  },
}};
const filename = resolve(process.argv[2]);
if (filename.endsWith('.json')) {
  program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  api = programExports(program);
  constructors = hostExports(program.linked.get('boundary.value').exports, program.runtime.exports);
  memory = program.runtime.exports.memory;
  gc = program.runtime.exports;
  runProgram(program);
} else {
  const instance = await instantiate(await WebAssembly.compile(await readFile(filename)), {...wasi.getImportObject(), ...host});
  wasi.initialize(instance);
  api = constructors = hostExports(instance.exports);
  memory = api.memory;
  gc = instance.exports;
  api.main();
}
gc['snail:gc/stress']?.(1);
assert.equal(api.echo(null), null);
assert.equal(api.value(null), -1n);
const state = api.state();
gc['snail:gc/collect']?.();
assert.equal(api.echo(state), state);
assert.equal(api.value(state), 42n);
assert.throws(() => api.echo(42), TypeError);
assert.throws(() => api.echo(constructors['payload-buffer'](1)), TypeError, 'opaque handles retain their logical types');
const otherWasi = createWasi({print() {}});
let other;
if (program) {
  const loaded = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, otherWasi, host);
  runProgram(loaded);
  other = programExports(loaded);
} else {
  const loaded = await instantiate(await WebAssembly.compile(await readFile(filename)), {...otherWasi.getImportObject(), ...host});
  otherWasi.initialize(loaded);
  other = hostExports(loaded.exports);
  other.main();
}
assert.throws(() => api.echo(other.state()), TypeError, 'equal numeric addresses in another heap are not references here');
api.discard(null);
api.discard(state);
assert.throws(() => api.fail());
assert.match(errors.join('\n'), /a deliberate boundary trap/);
assert.equal(api.value(api.state()), 42n, 'a trap preserves the opaque checkpoint');
assert.equal(api.binary(), 4);
assert.equal(api.empty(), 0);
assert.deepEqual(seen, [['text', 1], ['bytes', 7, [0, 255, 128, 1]], ['bytes', 0, []]]);
const result = api.managed();
gc['snail:gc/collect']?.();
assert.equal(api['result-number'](result), 42);
assert.equal(api['inspect-bytes'](api['result-bytes'](result)), 128);
assert.throws(() => api['result-number']({}), TypeError);
assert.throws(() => api['inspect-bytes'](new Uint8Array(4)), TypeError);
number = -1;
assert.equal(api['result-number'](api.managed()), -1);
assert.equal(api.value(api.inferred(43n)), 43n, 'a concrete inferred export retains its effects');
if (program) retireProgram(program);
else gc['snail:gc/release-roots']?.(gc['snail:gc/module-roots'].value);
gc['snail:gc/collect']?.();
assert.equal(api.value(api.state()), 43n, 'a host-held export keeps its retired module globals alive');
if (gc['snail:gc/checkpoint']) assert.equal(gc['snail:gc/checkpoint'](), 0);
console.log('host boundary: opaque values, typed managed results and borrowed bytes');
