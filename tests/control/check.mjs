import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createWasi, instantiate, linkProgram, runProgram} from '../../src/app/load.mjs';
import {programEntry} from '../../src/app/actors.mjs';
import {createControlHost} from '../../prototypes/ctl/runtime.mjs';

const file = resolve(process.argv[2]), host = createControlHost(), errors = [];
const wasi = createWasi({print: (fd, line) => errors.push(line)});
const gates = [];
const imports = {'lofi.control.prototype': host.imports, 'lofi.control.test': {pause: host.suspending(marker => {
  if (marker >= 4) return Promise.reject(new Error(`foreign rejection ${marker}`));
  if (marker === 3) return Promise.resolve();
  const gate = Promise.withResolvers();
  gates.push({marker, ...gate});
  return gate.promise;
})}};
const program = file.endsWith('.json') ?
  await linkProgram(path => readFile(resolve(dirname(file), path)), file, wasi, imports) :
  await instantiate(await WebAssembly.compile(await readFile(file)), {...wasi.getImportObject(), ...imports});
if (program.linked) runProgram(program);
else { wasi.initialize(program); program.exports.main(); }

function quiescent(name) {
  assert.deepEqual(host.stats, {tasks: 0, boundaries: 0, continuations: 0, queued: 0, active: false}, name);
  assert.ok(programEntry(program, name).handlers.every(global => global.value === null));
}

async function succeeds(name, expected, ...args) {
  assert.equal(await host.run(programEntry(program, name), ...args), expected, name);
  quiescent(name);
}

for (const [name, expected] of [['early', 42n], ['once', 42n], ['repeated', 12n], ['later-abort', 42n],
                               ['surviving-clause', 143n], ['surviving-clause-abort', 77n], ['no-operation', 42n], ['library-operation', 42n],
                               ['forwarding', 1033n], ['forwarding-abort', 77n], ['forwarding-after-resume', 1022n], ['nested', 115n], ['nested-abort', 77n],
                               ['descendant-resume', 42n], ['representations', 3n], ['fun-only', 3n], ['mixed', 10n], ['polymorphic', 4n], ['save-and-return', 42n]])
  await succeeds(name, expected);
await succeeds('captured', 41n, 20n);

for (const name of ['twice', 'call-saved', 'crossing-resume', 'handler-trap', 'body-trap', 'handler-rejection', 'body-rejection', 'handler-wasm-trap', 'body-wasm-trap']) {
  await assert.rejects(host.run(programEntry(program, name)), name.includes('rejection') ? /foreign rejection/ :
    name === 'crossing-resume' ? /originating clause/ : name.includes('wasm-trap') ? /divide by zero/ : name.includes('trap') ? /unreachable|exited/ : /only once/);
  quiescent(name);
  await succeeds('once', 42n);
}

async function until(predicate) {
  for (let i = 0; i < 100 && !predicate(); i++) await new Promise(resolve => setTimeout(resolve, 1));
  assert.ok(predicate(), 'the program reached its expected suspension');
}

const pending = host.run(programEntry(program, 'context'));
await until(() => gates.length === 1);
assert.equal(gates[0].marker, 2);
assert.ok(programEntry(program, 'context').handlers.every(global => global.value === null));
await assert.rejects(host.run(programEntry(program, 'once')), /must not overlap/);
gates[0].resolve();
await until(() => gates.length === 2);
assert.equal(gates[1].marker, 1);
assert.ok(programEntry(program, 'context').handlers.every(global => global.value === null));
gates[1].resolve();
assert.equal(await pending, 107n);
quiescent('context');
assert.ok(errors.some(text => text.includes('handler trap')));
assert.ok(errors.some(text => text.includes('body trap')));
console.log('ctl prototype: 30 cases passed; all JSPI tasks, boundaries and continuations settled');
