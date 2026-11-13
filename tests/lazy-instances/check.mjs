// Instance replacement resets lazy caches; retained old code keeps its cache.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, relinkProgram} from '../../host/browser/load.mjs';

const path = resolve(process.argv[2]);
const wasi = () => createWasi({print: (fd, line) => { throw new Error(line); }});
if (path.endsWith('.json')) {
  const read = file => readFile(resolve(dirname(path), file));
  const first = await linkProgram(read, path, wasi(), {});
  const oldNext = first.linked.get('main').exports.next;
  assert.equal(oldNext(), 1n);
  assert.equal(oldNext(), 2n);
  const second = await relinkProgram(first, 'main', path, read);
  assert.equal(second.linked.get('main').exports.next(), 1n);
  assert.equal(oldNext(), 3n);
} else {
  const module = await WebAssembly.compile(await readFile(path));
  async function fresh() {
    const host = wasi();
    const instance = await instantiate(module, host.getImportObject());
    host.initialize(instance);
    return instance.exports.next;
  }
  const first = await fresh(), second = await fresh();
  assert.equal(first(), 1n);
  assert.equal(first(), 2n);
  assert.equal(second(), 1n);
  assert.equal(first(), 3n);
}
console.log('lazy values: independent instances and retained old caches');
