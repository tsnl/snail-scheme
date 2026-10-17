import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let output = '', barriers = 0;
const imports = {benchmark: {
  input_i64: index => BigInt(config.inputs[index]),
  expected_count: () => BigInt(config.expected.length),
  expected_length: index => BigInt(config.expected[Number(index)].length),
  expected_character: (index, at) => config.expected[Number(index)].codePointAt(Number(at)),
  hide_i64: value => { barriers++; return value; },
  emit_character: scalar => { output += String.fromCodePoint(scalar); },
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
assert.equal(instance.exports.bench(BigInt(config.count)), 1n);
assert.equal(barriers, 3 * config.count);
instance.exports.observe();
assert.equal(output, config.output);
process.stdout.write(output);
