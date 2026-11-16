// The actual Wasm boundary: opaque values and staged byte records.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkedFileImports, linkProgram, programExports, wasmImports} from '../../host/browser/load.mjs';

let program, api, constructors, memory, number = 42;
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
    for (const [index, byte] of [0, 255, 128, 1].entries()) constructors['payload-put'](bytes, index, byte);
    const result = constructors['payload-finish'](number, bytes);
    constructors['payload-put'](bytes, 2, 0); // Finished Bytes must hold their own copy.
    return result;
  },
}};
const filename = resolve(process.argv[2]);
if (filename.endsWith('.manifest.datum')) {
  program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  api = programExports(program);
  constructors = program.linked.get('boundary.value').exports;
  memory = program.runtime.exports.memory;

} else {
  // The target installs the portable capabilities, which this test leaves unused.
  const module = await WebAssembly.compile(await readFile(filename));
  const instance = await instantiate(module, {...wasi.getImportObject(), ...host, ...portable(module)});
  wasi.initialize(instance);
  api = constructors = instance.exports;
  memory = api.memory;
}
assert.equal(api.echo(null), null);
assert.equal(api.value(null), -1n);
const checkpoint = api.create();
const state = api.state(checkpoint);
assert.equal(api.echo(state), state);
assert.equal(api.value(state), 42n);
assert.throws(() => api.echo(42), TypeError);
api.discard(null);
api.discard(state);
assert.throws(() => api.fail());
assert.match(errors.join('\n'), /a deliberate boundary trap/);
assert.equal(api.value(api.state(checkpoint)), 42n, 'a trap preserves the opaque checkpoint');
assert.equal(api.binary(), 4);
assert.equal(api.empty(), 0);
assert.equal(api.updated(), 2);
assert.deepEqual(seen, [['text', 1], ['bytes', 7, [0, 255, 128, 1]], ['bytes', 0, []], ['bytes', 9, [1, 2]]]);
const result = api.managed();
assert.equal(api['result-number'](result), 42);
assert.equal(api['inspect-bytes'](api['result-bytes'](result)), 128);
assert.throws(() => api['result-number']({}), TypeError);
assert.throws(() => api['inspect-bytes'](new Uint8Array(4)), TypeError);
number = -1;
assert.equal(api['result-number'](api.managed()), -1);
assert.equal(api.value(api.inferred(checkpoint, 43n)), 43n, 'a concrete inferred export retains its effects');
assert.equal(api.later(41n), 42n, "an exposed library function runs under the target's handlers");
console.log('host boundary: opaque values, typed managed results and staged bytes');

// The imports of the capabilities the target installs and this test leaves
// unused: the files a program links and the host's WebAssembly.
function portable(module) {
  const unread = file => { throw new Error(`this test reads no linked file ${file}`); };
  return {...linkedFileImports(unread, module), 'snail.runtime.wasm': wasmImports(() => null)};
}
