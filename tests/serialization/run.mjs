import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Each check receives real linked services and releases its resources ----

const [artifact, probe, expected] = process.argv.slice(2);
const module = new WebAssembly.Module(readFileSync(artifact));
// Raw snapshot helpers retain unused application declarations. Calling any
// such hook would exceed this transport fixture's contract and must fail.
const reducer = Object.fromEntries(
  ['label', 'quad', 'command', 'note', 'write', 'previous-length', 'previous-read', 'length', 'read', 'identity'].map(name => [name, () => {
    throw new Error(`unexpected application host call: ${name}`);
  }]),
);
assert(WebAssembly.Module.imports(module).every(entry =>
  entry.module === 'wasi_snapshot_preview1'
  || (entry.module === 'snail.reducer' && Object.hasOwn(reducer, entry.name))));
const wasi = new WASI({version: 'preview1', args: [], env: {}, returnOnExit: true});
let exitCode;
const imports = {...wasi.wasiImport, proc_exit(code) {
  exitCode = code;
  return wasi.wasiImport.proc_exit(code);
}};
const instance = new WebAssembly.Instance(module, {
  wasi_snapshot_preview1: imports,
  'snail.reducer': reducer,
});
try {
  wasi.initialize(instance);
  if (probe !== 'main') assert.equal(String(instance.exports.main()), '42');
  if (expected === 'trap') {
    // Checked Rust diagnostics exit through WASI's private returnOnExit sentinel.
    assert.throws(() => instance.exports[probe]());
    assert.equal(exitCode, 1);
  }
  else assert.equal(String(instance.exports[probe]()), expected);
} finally {
  assert.equal(instance.exports['close-resources'](), 0);
}
console.log(`PASS ${probe}: ${expected}`);
