import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const [artifact, cases] = process.argv.slice(2);
let hostEffects = 0;
const {instance} = await WebAssembly.instantiate(readFileSync(artifact), {
  'instance.probe': {record(value) { assert.equal(value, 1n); hostEffects++; }},
});
assert.equal(instance.exports.main(), 42);
let observed = 0;
for (const {kind, input, expected} of JSON.parse(readFileSync(cases, 'utf8'))) {
  for (const indirect of [0, 1]) {
    const operation = () => instance.exports[`narrow-${kind}`](indirect, kind === 'integer' ? BigInt(input) : Number(input));
    if (expected === 'trap') assert.throws(operation, WebAssembly.RuntimeError, input);
    else assert.equal(operation(), Number(expected), input);
    observed += Number(kind !== 'control' || expected === 'trap');
    assert.equal(instance.exports['effect-count'](), observed, 'evaluate only the selected operand, exactly once');
    assert.equal(hostEffects, observed, 'the effect must escape the guest before it traps');
  }
}
console.log(`PASS direct/first-class conversions and selected operand effects (${observed})`);
