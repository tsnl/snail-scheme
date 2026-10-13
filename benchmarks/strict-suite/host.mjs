import fs from 'node:fs';
import assert from 'node:assert/strict';

// Instantiate and construct input lists before starting the workload timer.
const [artifact, specification, mode] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let barriers = 0;
const opacity = mode === '--validate' ? value => { barriers++; return value; } : value => value;
const imports = {benchmark: {
  input_i64: index => BigInt(config.inputs[index]),
  input_f64: index => Number(config.inputs[index]),
  hide_i64: opacity,
  hide_f64: opacity,
  barrier: () => opacity(1),
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
barriers = 0;
const start = process.hrtime.bigint();
const result = instance.exports.bench(BigInt(config.count));
assert.equal(result.toString(), config.expected.toString());
const seconds = Number(process.hrtime.bigint() - start) / 1e9;
if (mode === '--validate') assert.equal(barriers, config.barriers_per_iteration * config.count);
console.log(JSON.stringify({seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null}));
