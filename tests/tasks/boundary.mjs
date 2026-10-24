// The host can hold opaque GC cells but cannot bypass their one-shot entry.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, runProgram} from '../../src/app/load.mjs';

const path = resolve(process.argv[2]), work = [], lines = [];
const host = {'snail.tasks': {dispatch: (run, drop, owner) => work.push({run, drop, owner})}};
const wasi = createWasi({print: (_, line) => lines.push(line)});
if (path.endsWith('.json')) {
  const program = await linkProgram(file => readFile(resolve(dirname(path), file)), path, wasi, host);
  runProgram(program);
} else {
  const instance = await instantiate(await WebAssembly.compile(await readFile(path)), {...wasi.getImportObject(), ...host});
  wasi.initialize(instance); instance.exports.main();
}
assert.equal(work.length, 2);
await WebAssembly.promising(work[0].run)(work[0].owner);
await assert.rejects(WebAssembly.promising(work[0].run)(work[0].owner), WebAssembly.RuntimeError);
work[1].drop(work[1].owner);
await assert.rejects(WebAssembly.promising(work[1].run)(work[1].owner), WebAssembly.RuntimeError);
assert.deepEqual(lines, ['ran']);
console.log('task boundary: invocation and cancellation clear owned work');
