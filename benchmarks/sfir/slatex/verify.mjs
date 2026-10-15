import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Expand the observed source's numbered file names ----

const readJson = path => JSON.parse(fs.readFileSync(path, 'utf8'));
const resolvePath = (path, iteration) => typeof path === 'string' ? path :
  `${path.prefix}${path.index_offset + path.index_step * iteration}${path.suffix}`;

function verifyOutputFile(entry, iteration) {
  const path = resolvePath(entry.path, iteration), bytes = fs.readFileSync(path);
  assert.equal(bytes.length, entry.bytes, path);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), entry.sha256, path);
  return path;
}

function verifyOutputs() {
  const manifest = readJson('output-manifest.json');
  const expected = new Set();
  for (let iteration = 0; iteration < manifest.iterations; iteration++)
    for (const entry of manifest.files) expected.add(verifyOutputFile(entry, iteration));
  assert.deepEqual(new Set(fs.readdirSync('outputs').map(name => `outputs/${name}`)), expected);
}

// ---- A resource belongs to the cycle that opened it ----

class ResourceTrace {
  constructor(wasi) {
    this.wasi = wasi; this.setup = {resources: [], open_close_order: []};
    this.current = this.setup; this.cycles = []; this.live = new Map();
    this.imports = {...wasi.wasiImport, path_open: this.open.bind(this),
      fd_read: this.read.bind(this), fd_write: this.write.bind(this), fd_close: this.close.bind(this)};
  }
  resultCount(address) { return new DataView(this.memory.buffer).getUint32(address, true); }
  open(...args) {
    const path = new TextDecoder().decode(new Uint8Array(this.memory.buffer, args[2], args[3]));
    const status = this.wasi.wasiImport.path_open(...args); assert.equal(status, 0, path);
    const index = this.current.resources.length;
    const resource = {path, read_bytes: 0, eof_reads: 0, write_bytes: 0};
    this.current.resources.push(resource); this.current.open_close_order.push(['open', index]);
    this.live.set(this.resultCount(args.at(-1)), {resource, index, owner: this.current});
    return status;
  }
  read(...args) {
    const status = this.wasi.wasiImport.fd_read(...args); assert.equal(status, 0);
    const entry = this.live.get(args[0]), count = this.resultCount(args.at(-1));
    if (entry) { entry.resource.read_bytes += count; entry.resource.eof_reads += Number(count === 0); }
    return status;
  }
  write(...args) {
    const status = this.wasi.wasiImport.fd_write(...args); assert.equal(status, 0);
    const entry = this.live.get(args[0]);
    if (entry) entry.resource.write_bytes += this.resultCount(args.at(-1));
    return status;
  }
  close(descriptor) {
    const status = this.wasi.wasiImport.fd_close(descriptor); assert.equal(status, 0);
    const entry = this.live.get(descriptor); assert(entry);
    entry.owner.open_close_order.push(['close', entry.index]); this.live.delete(descriptor);
    return status;
  }
  barrier() {
    assert.equal(this.live.size, 0);
    this.current = {resources: [], open_close_order: []}; this.cycles.push(this.current);
    return 1;
  }
}

// ---- The SFIR program performs all 500 source-processing iterations ----

function verifyWorker(programPath, providerPath) {
  const wasi = new WASI({version: 'preview1', args: [], env: {},
    preopens: {'.': process.cwd()}, returnOnExit: true});
  const trace = new ResourceTrace(wasi);
  const {guest, provider} = instantiateProgram(programPath, providerPath, trace);
  runCanonical(guest, provider, wasi, trace); verifyCycles(trace);
}

function instantiateProgram(programPath, providerPath, trace) {
  const load = path => new WebAssembly.Module(fs.readFileSync(path));
  let provider;
  provider = new WebAssembly.Instance(load(providerPath), {
    wasi_snapshot_preview1: trace.imports,
    'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)},
  });
  trace.memory = provider.exports.memory;
  const guest = new WebAssembly.Instance(load(programPath), {
    'snail.library': provider.exports, benchmark: {barrier: trace.barrier.bind(trace)},
  });
  return {guest, provider};
}

function runCanonical(guest, provider, wasi, trace) {
  try {
    wasi.initialize(provider); guest.exports.main();
    assert.equal(guest.exports['configured-count'](), 500n);
    assert.equal(guest.exports.bench(500n), 1n);
    assert.equal(trace.cycles.length, 500); assert.equal(trace.live.size, 0);
  } finally {
    assert.equal(provider.exports['snail:io/close-all'](), 0); assert.equal(trace.live.size, 0);
  }
}

function verifyCycles(trace) {
  assert.deepEqual(trace.setup, {resources: [{path: 'input.txt', read_bytes: fs.statSync('input.txt').size,
    eof_reads: 0, write_bytes: 0}], open_close_order: [['open', 0], ['close', 0]]});
  const contract = readJson('lifecycle.json');
  for (let iteration = 0; iteration < trace.cycles.length; iteration++) {
    const pattern = iteration ? contract.subsequent_worker_cycle : contract.first_worker_cycle;
    const expected = {resources: pattern.resources.map(entry => ({...entry, path: resolvePath(entry.path, iteration)})),
      open_close_order: pattern.open_close_order};
    assert.deepEqual(trace.cycles[iteration], expected, `resource cycle ${iteration}`);
  }
}

if (process.argv[2] !== '--outputs') verifyWorker(process.argv[2], process.argv[3]);
verifyOutputs();
console.log('All 28500 SLaTeX output files passed' + (process.argv[2] === '--outputs' ? '' : '; canonical 500 and every resource cycle passed'));
