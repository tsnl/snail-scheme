// The actual Wasm boundary: counted opaque values and staged byte records.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, programExports} from '../../host/browser/load.mjs';

let program, api, constructors, memory, number = 42;
const seen = [], errors = [], releases = [];
function owned(name, ...args) {
  const value = api[name](...args);
  const release = api[`${name}:release-result`];
  if (release) releases.push(() => release(value));
  return value;
}
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
    for (const [index, byte] of [0, 255, 128, 1].entries()) constructors['payload-put'](bytes, index, byte);
    const result = constructors['payload-finish'](number, bytes);
    constructors['payload-put'](bytes, 2, 0); // Finished Bytes must own their copy.
    constructors['payload-buffer:release-result']?.(bytes);
    return result; // The foreign return transfers this host-owned result.
  },
}};
const filename = resolve(process.argv[2]);
if (filename.endsWith('.json')) {
  program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  api = programExports(program);
  constructors = program.linked.get('boundary.value').exports;
  memory = program.runtime.exports.memory;

} else {
  const instance = await instantiate(await WebAssembly.compile(await readFile(filename)), {...wasi.getImportObject(), ...host});
  wasi.initialize(instance);
  api = constructors = instance.exports;
  memory = api.memory;
}
try {
assert.equal(api.echo(null), null);
assert.equal(api.value(null), -1n);
const checkpoint = owned('create');
const state = owned('state', checkpoint);
assert.equal(owned('echo', state), state);
assert.equal(api.value(state), 42n);
assert.throws(() => api.echo(42), TypeError);
api.discard(null);
api.discard(state);
assert.throws(() => api.fail());
assert.match(errors.join('\n'), /a deliberate boundary trap/);
assert.equal(api.value(owned('state', checkpoint)), 42n, 'a trap preserves the opaque checkpoint');
assert.equal(api.binary(), 4);
assert.equal(api.empty(), 0);
assert.deepEqual(seen, [['text', 1], ['bytes', 7, [0, 255, 128, 1]], ['bytes', 0, []]]);
const result = owned('managed');
assert.equal(api['result-number'](result), 42);
assert.equal(api['inspect-bytes'](owned('result-bytes', result)), 128);
assert.throws(() => api['result-number']({}), TypeError);
assert.throws(() => api['inspect-bytes'](new Uint8Array(4)), TypeError);
number = -1;
assert.equal(api['result-number'](owned('managed')), -1);
assert.equal(api.value(owned('inferred', checkpoint, 43n)), 43n, 'a concrete inferred export retains its effects');
} finally {
  for (const release of releases.reverse()) release();
}
console.log('host boundary: counted opaque values, typed managed results and staged bytes');
