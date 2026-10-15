import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Scalar inputs and untimed complete-value observations ----

const [artifact, specification, mode] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => ['benchmark', 'wasi_snapshot_preview1'].includes(entry.module)));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
let barriers = 0;
const values = [];
const imports = {benchmark: {
  barrier: () => { if (mode === '--validate') barriers++; return 1; },
  input_i64: index => BigInt(config.inputs[index]),
  input_f64: index => Number(config.inputs[index]),
  emit_i64: value => values.push(['i', value.toString()]),
  emit_f64: value => values.push(['f', Object.is(value, -0) ? '-0.0' : value.toString()]),
}, wasi_snapshot_preview1: wasi.wasiImport};
const instance = new WebAssembly.Instance(module, imports);
let failure, observation;
try {
  wasi.initialize(instance);
  instance.exports.main();
  if (mode === '--validate') assert.equal(barriers, config.setup_barriers);
  const start = process.hrtime.bigint();
  const result = instance.exports[config.export || 'bench'](BigInt(config.command ?? config.count));
  const seconds = Number(process.hrtime.bigint() - start) / 1e9;
  assert.equal(result, BigInt(config.expected));
  if (mode === '--validate') assert.equal(barriers, config.barriers_per_iteration * Math.max(0, Number(config.count)));
  observation = {seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null};
  if (config.export === 'probe') observation.values = values;
} catch (error) { failure = error; }
finally {
  try { assert.equal(instance.exports['close-resources'](), 0); }
  catch (error) { failure ??= error; }
}
if (failure) throw failure;
console.log(JSON.stringify(observation));
