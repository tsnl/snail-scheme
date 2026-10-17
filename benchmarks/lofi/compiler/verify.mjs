import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Observe compiler errors, recovery, and the complete canonical worker ----

const [programPath, providerPath, mode] = process.argv.slice(2);
const wasi = new WASI({version: 'preview1', args: [], env: {},
  preopens: {'.': process.cwd()}, returnOnExit: true});
const load = path => new WebAssembly.Module(fs.readFileSync(path));
const imports = {...wasi.wasiImport}, written = [];
let provider, barriers = 0;
imports.fd_write = (descriptor, vectors, count, result) => {
  if (descriptor === 1) {
    const memory = provider.exports.memory, view = new DataView(memory.buffer);
    for (let index = 0; index < count; index++) {
      const address = view.getUint32(vectors + index * 8, true);
      const length = view.getUint32(vectors + index * 8 + 4, true);
      written.push(Buffer.from(new Uint8Array(memory.buffer, address, length)));
    }
  }
  return wasi.wasiImport.fd_write(descriptor, vectors, count, result);
};
provider = new WebAssembly.Instance(load(providerPath), {
  wasi_snapshot_preview1: imports,
  'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)},
});
const guest = new WebAssembly.Instance(load(programPath), {
  'snail.library': provider.exports, benchmark: {barrier: () => { barriers++; return 1; }},
});
try {
  wasi.initialize(provider);
  guest.exports.main();
  assert.equal(guest.exports['configured-count'](), 2000n);
  if (mode === 'fatal') {
    guest.exports['observe-fatal']();
    throw new Error('fatal compiler handler returned');
  }
  assert.equal(guest.exports.observe(), 22n);
  const expected = fs.readFileSync('expected-observations.txt', 'utf8');
  assert.equal(Buffer.concat(written).toString('utf8') + '22\n', expected);
  assert.equal(barriers, 0);
  assert.equal(guest.exports.bench(2000n), 1n);
  assert.equal(barriers, 6000);
} finally {
  assert.equal(provider.exports['snail:io/close-all'](), 0);
}
console.log('22 compiler observations and canonical 2000 passed');
