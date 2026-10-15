import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/snail-sfir/execute.mjs';

const directory = process.argv[2];
const code = loadWasm(readFileSync(join(directory, 'application.wasm')));
for (let index = 0; index < 2; ++index) {
  const provider = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(join(directory, 'consumer.wasm'))));
  const instance = instantiate(code, new Map([['tests.consumer', provider]]));
  assert.equal(invokeEntry(instance, []), 84);
  assert.equal(invokeEntry(instance, []), 84);
  assert.equal(provider.exports.count(), 1, 'diamond import initialized a library twice');
  closeInstance(instance);
}
const hygiene = instantiate(loadWasm(readFileSync(join(directory, 'hygiene.wasm'))));
assert.equal(invokeEntry(hygiene, []), 42, 'private wrapper captured the imported produce name');
closeInstance(hygiene);
const records = readFileSync(join(directory, 'providers.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
assert.deepEqual(records.map(record => [record.action, record.libraryKey.at(-1)]),
  [['open', 'offset'], ['close', 'offset'], ['open', 'answer'], ['close', 'answer'], ['open', 'support'], ['close', 'support']]);
console.log('PASS nested compiled recipes, separate dependency maps, identity, initialization, source context and provider cleanup');
