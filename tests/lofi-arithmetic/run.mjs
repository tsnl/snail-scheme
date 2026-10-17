import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const [artifact, inputs] = process.argv.slice(2);
let effects = [];
const {instance} = await WebAssembly.instantiate(readFileSync(artifact), {
  'instance.probe': {record(value) { effects.push(Number(value)); }},
});
assert.equal(instance.exports.main(), 42);
for (const test of JSON.parse(readFileSync(inputs, 'utf8'))) {
  effects = [];
  const args = [test.route, test.operation, ...test.inputs.map(test.kind === 'i64' ? BigInt : Number)];
  const invoke = test.mode === 'constant' ? () => instance.exports['constant-arithmetic'](test.operation)
    : test.mode === 'value' ? () => instance.exports[`calculate-${test.kind}`](...args)
    : () => instance.exports[`discard-${test.kind}`](Number(test.mode === 'discard'), ...args);
  if (test.expected === 'trap') assert.throws(invoke, WebAssembly.RuntimeError, test.label);
  else assert.equal(invoke(), test.mode !== 'value' ? undefined
    : test.kind === 'i64' ? BigInt(test.expected) : Number(test.expected), test.label);
  assert.deepEqual(effects, test.effects, test.label);
  globalThis.gc?.();
}
console.log(`PASS ${JSON.parse(readFileSync(inputs, 'utf8')).length} arithmetic calls and ordered effects`);
