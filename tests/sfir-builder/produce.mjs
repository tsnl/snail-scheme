import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, InitializationError} from '../../src/snail-sfir/execute.mjs';
import {openLibraryBuilder, invokeLibraryGenerator, libraryTransferJSON} from '../../src/snail-sfir/library-builder.mjs';
import {scalars} from './scalars.mjs';

const directory = process.argv[2];
const load = name => loadWasm(readFileSync(join(directory, `${name}.wasm`)));
const producer = load('build');
writeFileSync(join(directory, 'example.json'), libraryTransferJSON(invokeLibraryGenerator(load('example'))));
for (const [name, offset] of [['first', 7], ['second', 20], ['ill-typed', -1]]) {
  const result = invokeLibraryGenerator(producer, new Map(), [offset]);
  const json = libraryTransferJSON(result), packet = JSON.parse(json);
  assert.deepEqual(Object.keys(packet).sort(), ['nodes', 'root', 'version']);
  assert.equal(packet.nodes[packet.root][0], 'library');
  assert(packet.nodes.some(node => node[0] === 'import-reference'));
  assert(packet.nodes.some(node => node[0] === 'local-reference'));
  writeFileSync(join(directory, `${name}.json`), json);
}
assert.throws(() => invokeLibraryGenerator(load('fail')), WebAssembly.RuntimeError);
assert.throws(() => invokeLibraryGenerator(load('wrong-token')), /invocation handle/);
assert.throws(() => invokeLibraryGenerator(load('wrong-kind')), /handle kind/);
assert.throws(() => invokeLibraryGenerator(load('bad-location')), /one-based/);
assert.throws(() => invokeLibraryGenerator(load('initial-failure')), InitializationError);
assert(libraryTransferJSON(invokeLibraryGenerator(producer, new Map(), [7])).includes('library'));
for (const [name, type, value] of scalars)
  writeFileSync(join(directory, `${name}.json`),
    libraryTransferJSON(invokeLibraryGenerator(load(`build-${type}`), new Map(), [value])));
assert.throws(() => invokeLibraryGenerator(producer, new Map([['sfir.builder', {}]]), [7]), /invocation-owned/);

// Raw service calls still enforce categories, origin and lifetime. Tokens from
// another invocation cannot become local IDs even when both start at zero.
const first = openLibraryBuilder(), second = openLibraryBuilder();
const one = first.provider.exports, two = second.provider.exports;
const name = one['name-empty'](), otherName = two['name-empty']();
assert.notEqual(name, otherName);
assert.throws(() => one['name-character'](otherName, 65), /invocation handle/);
assert.throws(() => one['name-character'](one['nil'](), 65), /handle kind/);
assert.throws(() => one['name-character'](name, 0xd800), /Unicode scalar/);
assert.throws(() => one['export'](name, one['literal-I32'](7, one['span'](name, 1, 1))), /handle kind/);
assert.throws(() => first.finish(name), /handle kind/);
first.close(); first.close(); second.close();
assert.throws(() => one['name-empty'](), /closed/);
assert.throws(() => first.finish(name), /closed/);
assert.throws(() => libraryTransferJSON(JSON.parse('{}')), /owned library transfer/);
console.log('PASS compiled SFIR producer, structured transfers, handle ownership and cleanup');
