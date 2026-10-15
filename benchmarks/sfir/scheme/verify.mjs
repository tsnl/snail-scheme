import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- The ordinary SFIR interpreter performs every observed operation ----

const [programPath, providerPath] = process.argv.slice(2);
const wasi = new WASI({version: 'preview1', args: [], env: {},
  preopens: {'.': process.cwd()}, returnOnExit: true});
const phases = {setup: [], probes: [], worker: [], cleanup: []}, live = new Map();
let phase = 'setup', memory;
const countAt = address => new DataView(memory.buffer).getUint32(address, true);
const imports = {...wasi.wasiImport};
imports.path_open = (...args) => {
  const path = new TextDecoder().decode(new Uint8Array(memory.buffer, args[2], args[3]));
  assert.equal(path, {setup: 'input.txt', probes: 'probes.scm'}[phase]);
  const status = wasi.wasiImport.path_open(...args);
  assert.equal(status, 0, path);
  live.set(countAt(args.at(-1)), path);
  phases[phase].push(['open', path]);
  return status;
};
imports.fd_read = (...args) => {
  assert(live.has(args[0]) && ['setup', 'probes'].includes(phase));
  return wasi.wasiImport.fd_read(...args);
};
imports.fd_close = descriptor => {
  assert(live.has(descriptor));
  const status = wasi.wasiImport.fd_close(descriptor);
  assert.equal(status, 0);
  phases[phase].push(['close', live.get(descriptor)]);
  live.delete(descriptor);
  return status;
};
const load = path => new WebAssembly.Module(fs.readFileSync(path));
let provider, barriers = 0;
provider = new WebAssembly.Instance(load(providerPath), {
  wasi_snapshot_preview1: imports,
  'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)},
});
memory = provider.exports.memory;
const guest = new WebAssembly.Instance(load(programPath), {
  'snail.library': provider.exports, benchmark: {barrier: () => { barriers++; return 1; }},
});
let failure, cleanupFailure;
try {
  wasi.initialize(provider);
  guest.exports.main();
  assert.equal(guest.exports['configured-count'](), 100000n);
  verifyPhase('setup', 'input.txt');
  phase = 'probes';
  assert.equal(guest.exports.observe(), 26n);
  verifyPhase('probes', 'probes.scm');
  assert.equal(barriers, 0);
  phase = 'worker';
  assert.equal(guest.exports.bench(100000n), 1n);
  assert.equal(barriers, 100000);
  verifyPhase('worker');
} catch (error) { failure = error; }
finally {
  phase = 'cleanup';
  try {
    assert.equal(provider.exports['snail:io/close-all'](), 0);
    assert.equal(live.size, 0);
    if (!failure) verifyPhase('cleanup');
  } catch (error) { cleanupFailure = error; }
}
console.log(JSON.stringify({passed: !failure && !cleanupFailure, barriers, phases,
  failures: [failure, cleanupFailure].filter(Boolean).map(String)}));
if (failure || cleanupFailure) throw failure ?? cleanupFailure;
console.log('26 interpreter probes and canonical 100000 passed');

function verifyPhase(name, path) {
  assert.deepEqual(phases[name], path ? [['open', path], ['close', path]] : []);
  assert.equal(live.size, 0);
}
