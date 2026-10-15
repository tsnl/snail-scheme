import fs from 'node:fs';
import assert from 'node:assert/strict';
import {WASI} from 'node:wasi';

// ---- Decode the pathname and instantiate the scalar interface before timing ----

const [artifact, specification, mode] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const characters = Array.from(config.pathname, character => character.codePointAt(0));
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry =>
  ['benchmark', 'wasi_snapshot_preview1'].includes(entry.module)));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));
const wasi = new WASI({version: 'preview1', args: [], env: {},
  preopens: {'.': process.cwd()}, returnOnExit: true});
let barriers = 0;
const opaque = mode === '--validate' ? value => { barriers++; return value; } : value => value;
const imports = {benchmark: {
  input_i64: index => BigInt(config.inputs[index]),
  input_f64: index => Number(config.inputs[index]),
  hide_i64: opaque,
  barrier: () => opaque(1),
  path_length: () => BigInt(characters.length),
  path_character: index => characters[Number(index)],
}, wasi_snapshot_preview1: wasi.wasiImport};
const events = [], live = new Set();
if (config.trace) {
  imports.wasi_snapshot_preview1 = {...wasi.wasiImport};
  for (const name of ['path_open', 'path_unlink_file', 'fd_close']) {
    imports.wasi_snapshot_preview1[name] = (...arguments_) => {
      const status = wasi.wasiImport[name](...arguments_);
      events.push([name, status]);
      if (status === 0 && name === 'path_open')
        live.add(new DataView(instance.exports.memory.buffer).getUint32(arguments_.at(-1), true));
      if (status === 0 && name === 'fd_close') live.delete(arguments_[0]);
      return status;
    };
  }
}
const instance = new WebAssembly.Instance(module, imports);

// ---- Cleanup brackets reactor initialization, Scheme main and the worker ----

let failure, observation;
try {
  wasi.initialize(instance);
  instance.exports.main();
  const setupBarriers = barriers;
  if (mode === '--validate') assert.equal(setupBarriers, config.setup_barriers);
  barriers = 0;
  const start = process.hrtime.bigint();
  const result = instance.exports[config.export || 'bench'](BigInt(config.count));
  assert.equal(result.toString(), config.expected.toString());
  const seconds = Number(process.hrtime.bigint() - start) / 1e9;
  if (mode === '--validate') assert.equal(barriers, config.barriers_per_iteration * Math.max(0, config.count));
  observation = {seconds, result: result.toString(), barriers: mode === '--validate' ? barriers : null,
    setup_barriers: mode === '--validate' ? setupBarriers : null};
} catch (error) {
  failure = error;
} finally {
  // Preserve the invocation failure if closing its outstanding resources also
  // fails. A trapped instance is terminal; only this cleanup export is called.
  try {
    assert.equal(instance.exports['close-resources'](), 0, 'resource cleanup failed');
  } catch (error) {
    failure ??= error;
  }
}
if (failure) throw failure;
if (config.trace) {
  assert.equal(live.size, 0);
  observation.events = events;
}
console.log(JSON.stringify(observation));
