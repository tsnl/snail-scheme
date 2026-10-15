import fs from 'node:fs';
import assert from 'node:assert/strict';

// ---- Decode and initialize before the optional workload clock ----

const [artifact, specification, mode = '--validate'] = process.argv.slice(2);
assert(['--validate', '--time'].includes(mode));
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

// The guest includes the complete numerical predicate. Serialization follows.
const before = mode === '--time' ? process.hrtime.bigint() : null;
const result = instance.exports.bench(BigInt(config.count));
const seconds = before === null ? null : Number(process.hrtime.bigint() - before) / 1e9;
assert.equal(result, BigInt(config.predicate ?? (config.count > 0 ? 1 : 0)));
assert.equal(barriers, 3 * config.count);
if (!config.per_iteration) instance.exports.observe();
assert.equal(output, config.output);
process.stdout.write(output);
if (seconds !== null)
  console.log(`+!CSVLINE!+snail-integer,${config.name}:${config.count},${seconds.toFixed(9)}`);
