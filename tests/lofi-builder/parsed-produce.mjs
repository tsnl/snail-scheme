import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {openLibraryBuilder, libraryTransferJSON} from '../../src/lofi/compiler/builder.mjs';

const directory = process.argv[2], builder = openLibraryBuilder();
const text = readFileSync(join(directory, 'parsed-source.json'), 'utf8');
const code = loadWasm(readFileSync(join(directory, 'parsed-producer.wasm')));
const instance = instantiate(code, new Map([['lofi.builder', builder.provider]]));
try {
  const original = builder.receive(text), independent = builder.receive(text);
  assert.notEqual(original, independent, 'reading identical packets creates fresh syntax identities');
  const transformed = invokeEntry(instance, [original]);
  writeFileSync(join(directory, 'parsed.json'), libraryTransferJSON(builder.finish(transformed)));
  assert.equal(builder.finish(original), builder.finish(original), 'alias finishing preserves identity');
  assert.throws(() => builder.provider.exports['checked-library'](0n), /foreign/);
  assert.throws(() => builder.provider.exports['checked-library'](builder.provider.exports['root-scope']()), /kind/);
  const malformed = JSON.parse(text);
  malformed.origin = 'trusted';
  assert.throws(() => builder.receive(JSON.stringify(malformed)), /unsupported/);
  delete malformed.origin;
  const annotated = malformed.nodes.find(node => node[0] === 'definition');
  const originalSpan = annotated[5];
  annotated[5] = malformed.nodes.findIndex(node => node[0] === 'name');
  assert.throws(() => builder.receive(JSON.stringify(malformed)), /wrong kind/);
  annotated[5] = originalSpan;
  malformed.nodes.push(['scope', 'extra']);
  assert.throws(() => builder.receive(JSON.stringify(malformed)), /unsupported/);
  assert.throws(() => builder.receive('{"version":1,"root":0,"nodes":[["cons",0,0]]}'), /cyclic/);
  const before = JSON.parse(libraryTransferJSON(builder.finish(original)));
  const after = JSON.parse(libraryTransferJSON(builder.finish(transformed)));
  assert.equal(before.nodes.filter(node => node[0] === 'number-literal').length,
    after.nodes.filter(node => node[0] === 'number-literal').length);
} finally {
  closeInstance(instance);
  builder.close();
}
assert.throws(() => builder.receive(text), /closed/);
console.log('PASS parsed syntax through compiled Lofi inspection/reconstruction and owned packet import');
