import fs from 'node:fs';
import assert from 'node:assert/strict';
import {WASI} from 'node:wasi';
const [artifact, fixture] = process.argv.slice(2);
const cases = JSON.parse(fs.readFileSync(fixture, 'utf8'));
let args = [], output = '';
const imports = {oracle: {
  argument_length: index => BigInt(args[index].length),
  argument_character: (index, at) => args[index].codePointAt(Number(at)),
  emit_character: scalar => { output += String.fromCodePoint(scalar); },
}};
const bits = new DataView(new ArrayBuffer(8));
function fromBits(value) { bits.setBigUint64(0, BigInt(value)); return bits.getFloat64(0); }
function toBits(value) { bits.setFloat64(0, value); return bits.getBigUint64(0).toString(); }
const module = await WebAssembly.compile(fs.readFileSync(artifact));
const linked = WebAssembly.Module.imports(module).some(item => item.module === 'wasi_snapshot_preview1');
function close(instance) {
  if (instance.exports['close-resources']) assert.equal(instance.exports['close-resources'](), 0);
}
function initialize() {
  const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
  const instance = new WebAssembly.Instance(module, {...imports, wasi_snapshot_preview1: wasi.wasiImport});
  try {
    if (linked) wasi.initialize(instance);
    instance.exports.main();
    return instance;
  } catch (error) { close(instance); throw error; }
}
const positive = initialize();
try {
  for (const item of cases) {
    // A trap ends an invocation. Its resources close before the instance is
    // discarded; later cases never resume Scheme in a failed instance.
    const instance = item.error ? initialize() : positive;
    args = [item.a, item.b]; output = '';
    try {
      let trapped = false, answer;
      try { answer = instance.exports.probe(BigInt(item.operation), fromBits(item.input)); }
      catch (error) {
        if (!(error instanceof WebAssembly.RuntimeError)) throw error;
        trapped = true;
      }
      assert.equal(trapped, Boolean(item.error), item.label);
      if (!trapped) {
        assert.equal(toBits(answer), item.bits, item.label);
        assert.equal(output, item.text, item.label);
      }
    } finally { if (item.error) close(instance); }
  }
} finally { close(positive); }
console.log(JSON.stringify({cases: cases.length, passed: true}));
