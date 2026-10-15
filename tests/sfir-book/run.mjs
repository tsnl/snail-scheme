import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const [path, cases = '[]'] = process.argv.slice(2);
const {instance} = await WebAssembly.instantiate(readFileSync(path));
assert.equal(instance.exports.main(), 42);
for (const [input, expected] of JSON.parse(cases)) {
  if (expected === 'trap')
    assert.throws(() => instance.exports.convert(Number(input)), WebAssembly.RuntimeError, input);
  else
    assert.equal(instance.exports.convert(Number(input)), expected, input);
}
console.log('PASS published example or F32 conversion cases');
