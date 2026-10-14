import v8 from 'node:v8';
import inspector from 'node:inspector';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';

// Instantiate and prepare runtime inputs before starting the workload timer.
const [artifact, specification, mode, profileDirectory, profileKind] = process.argv.slice(2);
const session = new inspector.Session();
if (profileKind === 'cpu') session.connect();
const post = (method, params = {}) => new Promise((resolve, reject) =>
  session.post(method, params, (error, result) => error ? reject(error) : resolve(result)));
if (profileKind === 'cpu') {
  await post('Profiler.enable');
  await post('Profiler.setSamplingInterval', {interval: 1000});
}
const mark = (phase, edge) => fs.writeSync(1, JSON.stringify({phase, edge, uptime_ms: process.uptime() * 1000}) + '\n');
async function startPhase(phase) {
  if (profileKind === 'cpu') await post('Profiler.start');
  mark(phase, 'start');
}
async function endPhase(phase) {
  mark(phase, 'end');
  if (profileKind === 'cpu') {
    const {profile} = await post('Profiler.stop');
    fs.writeFileSync(path.join(profileDirectory, phase + '.cpuprofile'), JSON.stringify(profile));
  }
  if (profileKind === 'counters') {
    const counts = Object.fromEntries(Object.entries(instance.exports)
      .filter(([name]) => name.startsWith('counter'))
      .map(([name, value]) => [name, value.value.toString()]));
    fs.writeFileSync(path.join(profileDirectory, phase + '.counters.json'), JSON.stringify(counts));
  }
}
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let barriers = 0;
const opacity = mode === '--validate' ? value => { barriers++; return value; } : value => value;
const imports = {benchmark: {
  print_text: code => fs.writeSync(1, config.diagnostic_text[Number(code)]),
  print_size: (code, value) => {
    const [prefix, suffix] = config.diagnostic_sizes[Number(code)];
    fs.writeSync(1, prefix + value.toString() + suffix);
  },
  print_construction: (iters, depth) => fs.writeSync(1, `Creating ${iters} trees of depth ${depth}`),
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
await startPhase('setup');
instance.exports.main();
await endPhase('setup');
const setupBarriers = barriers;
if (mode === '--validate' && config.setup_barriers !== undefined)
  assert.equal(setupBarriers, config.setup_barriers);
barriers = 0;
await startPhase('bench');
const usageBefore = process.resourceUsage();
const start = process.hrtime.bigint();
const result = instance.exports[config.export || 'bench'](BigInt(config.count));
const elapsed = process.hrtime.bigint() - start;
const usageAfter = process.resourceUsage();
await endPhase('bench');
console.log(JSON.stringify({phase:'resources', usageBefore, usageAfter, deltas:Object.fromEntries(['userCPUTime','systemCPUTime','minorPageFault','majorPageFault','voluntaryContextSwitches','involuntaryContextSwitches'].map(key => [key, usageAfter[key] - usageBefore[key]])), spaces:v8.getHeapSpaceStatistics()}));
const checkedFlag = ['i64-list-values', 'f64-vector-values', 'i64-vector-values'].includes(config.result_kind);
assert.equal(result.toString(), checkedFlag ? '1' : config.expected.toString());
const seconds = Number(elapsed) / 1e9;
if (mode === '--validate') assert.equal(barriers, config.barriers_per_iteration * config.count);
console.log(JSON.stringify({seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null,
  setup_barriers: mode === '--validate' ? setupBarriers : null}));

if (profileKind === 'cpu') session.disconnect();
