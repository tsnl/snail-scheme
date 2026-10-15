import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';

// Instantiate and prepare runtime inputs before starting the workload timer.
const [artifact, specification, mode] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let barriers = 0;
const opacity = mode === '--validate' ? value => { barriers++; return value; } : value => value;
const imports = {benchmark: {
  count: () => BigInt(config.count),
  input_i64: index => BigInt(config.inputs[index]),
  input_f64: index => Number(config.inputs[index]),
  vector_length: index => BigInt(config.inputs[index].length),
  vector_f64: (index, element) => Number(config.inputs[index][Number(element)]),
  vector_i64: (index, element) => BigInt(config.inputs[index][Number(element)]),
  expected_length: () => BigInt(config.expected.length),
  expected_i64: index => BigInt(config.expected[Number(index)]),
  expected_f64: index => Number(config.expected[Number(index)]),
  tolerance: () => Number(config.tolerance),
  hide_i64: opacity,
  hide_f64: opacity,
  barrier: () => opacity(1),
}};
if (config.math_provider) {
  const providerPath = path.resolve(path.dirname(artifact), config.math_provider);
  const module = new WebAssembly.Module(fs.readFileSync(providerPath));
  assert.deepEqual(WebAssembly.Module.imports(module), [], 'sine provider must implement its math inside Wasm');
  imports.math = new WebAssembly.Instance(module).exports;
}
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
// main installs staged procedures and generates quicksort's base vector here.
instance.exports.main();
const setupBarriers = barriers;
if (mode === '--validate' && config.setup_barriers !== undefined)
  assert.equal(setupBarriers, config.setup_barriers);
barriers = 0;
const start = process.hrtime.bigint();
const result = instance.exports[config.export || 'bench'](BigInt(config.count));
const checkedFlag = ['i64-list-values', 'f64-vector-values', 'i64-vector-values'].includes(config.result_kind);
assert.equal(result.toString(), checkedFlag ? '1' : config.expected.toString());
const seconds = Number(process.hrtime.bigint() - start) / 1e9;
if (mode === '--validate') assert.equal(barriers, config.barriers_per_iteration * config.count);
console.log(JSON.stringify({seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null,
  setup_barriers: mode === '--validate' ? setupBarriers : null}));
