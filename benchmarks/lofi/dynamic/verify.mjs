import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- The source intentionally retains every worker input until cleanup ----

const readJson = path => JSON.parse(fs.readFileSync(path, 'utf8'));
const config = readJson('spec.json'), contract = readJson('lifecycle.json');
const input = fs.readFileSync(contract.input_path);
assert.equal(input.length, contract.input_bytes_per_open);
assert.equal(crypto.createHash('sha256').update(input).digest('hex'), contract.input_sha256);
const emptyPhase = () => ({input_opens: 0, input_bytes: 0, input_eof_reads: 0, input_closes: 0, output_opens: 0});
const phases = {setup: emptyPhase(), worker: emptyPhase(), cleanup: emptyPhase()};
const live = new Map();
let memory, phase = 'setup', barriers = 0;
const countAt = address => new DataView(memory.buffer).getUint32(address, true);

function openInput(wasi, args) {
  const path = new TextDecoder().decode(new Uint8Array(memory.buffer, args[2], args[3]));
  assert(['setup', 'worker'].includes(phase));
  assert.equal(path, phase === 'setup' ? 'input.txt' : contract.input_path);
  const status = wasi.wasiImport.path_open(...args);
  assert.equal(status, 0, path);
  const file = {path, bytes: 0, eof_reads: 0, iteration: barriers};
  phases[phase].input_opens++;
  live.set(countAt(args.at(-1)), file);
  return status;
}

function readInput(wasi, args) {
  const file = live.get(args[0]);
  assert(file && file.eof_reads === 0, 'read continued after EOF or without a live input');
  const status = wasi.wasiImport.fd_read(...args);
  assert.equal(status, 0);
  const bytes = countAt(args.at(-1));
  file.bytes += bytes;
  file.eof_reads += Number(bytes === 0);
  phases[phase].input_bytes += bytes;
  phases[phase].input_eof_reads += Number(bytes === 0);
  return status;
}

function closeInput(wasi, descriptor) {
  assert(live.has(descriptor));
  const status = wasi.wasiImport.fd_close(descriptor);
  assert.equal(status, 0);
  phases[phase].input_closes++;
  live.delete(descriptor);
  return status;
}

function verifySetup() {
  assert.deepEqual(phases.setup, {...emptyPhase(), input_opens: 1,
    input_bytes: fs.statSync('input.txt').size, input_closes: contract.setup.input_closes});
  assert.equal(live.size, 0);
  assert.equal(barriers, 0);
}

function verifyWorker() {
  assert.deepEqual(phases.worker, contract.worker);
  assert.equal(barriers, config.count);
  assert.equal(live.size, config.count);
  for (const [index, file] of [...live.values()].entries())
    assert.deepEqual(file, {path: contract.input_path, bytes: contract.input_bytes_per_open,
      eof_reads: 1, iteration: index + 1});
}

// ---- Only the compiled guest parses, infers and checks the complete datum ----

const [programPath, providerPath] = process.argv.slice(2);
const wasi = new WASI({version: 'preview1', args: [], env: {},
  preopens: {'.': process.cwd()}, returnOnExit: true});
const imports = {...wasi.wasiImport, path_open: (...args) => openInput(wasi, args),
  fd_read: (...args) => readInput(wasi, args), fd_close: descriptor => closeInput(wasi, descriptor)};
imports.fd_write = (...args) => {
  assert(!live.has(args[0]), 'the workload wrote to its input');
  return wasi.wasiImport.fd_write(...args);
};
const load = path => new WebAssembly.Module(fs.readFileSync(path));
let provider;
provider = new WebAssembly.Instance(load(providerPath), {
  wasi_snapshot_preview1: imports,
  'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)},
});
memory = provider.exports.memory;
const guest = new WebAssembly.Instance(load(programPath), {
  'snail.library': provider.exports, benchmark: {barrier: () => { barriers++; return 1; }},
});
let result, failure, cleanupFailure;
try {
  wasi.initialize(provider);
  guest.exports.main();
  assert.equal(guest.exports['configured-count'](), BigInt(config.count));
  verifySetup();
  phase = 'worker';
  result = guest.exports.bench(BigInt(config.count));
  assert.equal(result, BigInt(config.expected));
  verifyWorker();
} catch (error) { failure = error; }
finally {
  phase = 'cleanup';
  try {
    assert.equal(provider.exports['snail:io/close-all'](), 0);
    assert.equal(live.size, 0);
    if (!failure) assert.deepEqual(phases.cleanup, {...emptyPhase(), input_closes: contract.cleanup.input_closes});
  } catch (error) { cleanupFailure = error; }
}
console.log(JSON.stringify({passed: !failure && !cleanupFailure, result: String(result), barriers, phases,
  failures: [failure, cleanupFailure].filter(Boolean).map(String)}));
if (failure || cleanupFailure) throw failure ?? cleanupFailure;
