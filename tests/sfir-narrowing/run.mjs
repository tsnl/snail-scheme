import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const [artifact, cases] = process.argv.slice(2);
const {instance} = await WebAssembly.instantiate(readFileSync(artifact));
assert.equal(instance.exports.main(), 42);
let observed = 0;
for (const {kind, input, expected} of JSON.parse(readFileSync(cases, 'utf8'))) {
  for (const indirect of [0, 1]) {
    const operation = () => instance.exports[`narrow-${kind}`](indirect, kind === 'integer' ? BigInt(input) : Number(input));
    if (expected === 'trap') assert.throws(operation, WebAssembly.RuntimeError, input);
    else assert.equal(operation(), Number(expected), input);
    assert.equal(instance.exports['effect-count'](), ++observed, 'evaluate the operand exactly once, even on failure');
  }
}
console.log(`PASS ${observed} direct and first-class conversion calls`);
