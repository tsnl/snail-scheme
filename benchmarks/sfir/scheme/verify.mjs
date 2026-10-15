import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- The ordinary SFIR interpreter performs every observed operation ----

const [programPath, providerPath] = process.argv.slice(2);
const wasi = new WASI({version: 'preview1', args: [], env: {},
  preopens: {'.': process.cwd()}, returnOnExit: true});
const load = path => new WebAssembly.Module(fs.readFileSync(path));
let provider, barriers = 0;
provider = new WebAssembly.Instance(load(providerPath), {
  wasi_snapshot_preview1: wasi.wasiImport,
  'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)},
});
const guest = new WebAssembly.Instance(load(programPath), {
  'snail.library': provider.exports, benchmark: {barrier: () => { barriers++; return 1; }},
});
try {
  wasi.initialize(provider);
  guest.exports.main();
  assert.equal(guest.exports['configured-count'](), 100000n);
  assert.equal(guest.exports.observe(), 26n);
  assert.equal(barriers, 0);
  assert.equal(guest.exports.bench(100000n), 1n);
  assert.equal(barriers, 100000);
} finally {
  assert.equal(provider.exports['snail:io/close-all'](), 0);
}
console.log('26 interpreter probes and canonical 100000 passed');
