import fs from 'node:fs';
import assert from 'node:assert/strict';

// ---- Decimal text is transported after its complete guest predicate ----

const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let output = '';
const imports = {benchmark: {
  input_i64: index => BigInt(config.inputs[index]),
  expected_count: () => BigInt(config.expected.length),
  expected_length: index => BigInt(config.expected[Number(index)].length),
  expected_character: (index, at) => config.expected[Number(index)].codePointAt(Number(at)),
  hide_i64: value => value,
  emit_character: scalar => { output += String.fromCodePoint(scalar); },
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
const start = process.hrtime.bigint();
const result = instance.exports.bench(BigInt(config.count));
assert.equal(result, 1n);
const seconds = Number(process.hrtime.bigint() - start) / 1e9;
instance.exports.observe();
assert.equal(output, config.output);
process.stdout.write(output);
console.log(JSON.stringify({result: result.toString(), seconds}));
