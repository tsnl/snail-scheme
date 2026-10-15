import assert from 'node:assert/strict';
import fs from 'node:fs';
import {WASI} from 'node:wasi';

// ---- Benchmark characters cross the scalar boundary as UTF-8 bytes ----

function writeCharacter(value) {
  assert(Number.isInteger(value) && value >= 0 && value <= 0x10ffff && (value < 0xd800 || value > 0xdfff));
  const bytes = Buffer.from(String.fromCodePoint(value), 'utf8');
  assert.equal(fs.writeSync(1, bytes), bytes.length);
}

// ---- Both layouts finish file setup before entering the original clock ----

const [artifact, specification, providerPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const module = new WebAssembly.Module(fs.readFileSync(artifact));
const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': process.cwd()}, returnOnExit: true});
let provider;
if (providerPath) {
  const scalarModule = new WebAssembly.Module(fs.readFileSync(providerPath));
  assert(WebAssembly.Module.imports(scalarModule).every(item => ['snail.platform', 'wasi_snapshot_preview1'].includes(item.module)));
  provider = new WebAssembly.Instance(scalarModule, {wasi_snapshot_preview1: wasi.wasiImport,
    'snail.platform': {'diagnostics/report-error': (...args) => provider.exports['snail:report-error'](...args)}});
}
const instance = new WebAssembly.Instance(module, {benchmark: {barrier: () => 1,
                                                  write_character: writeCharacter, write_char: writeCharacter},
                                                  'snail.library': provider?.exports,
                                                  wasi_snapshot_preview1: wasi.wasiImport});
const close = () => provider ? provider.exports['snail:io/close-all']() : instance.exports['close-resources']();
let result, seconds, failure;
try {
  wasi.initialize(provider ?? instance);
  instance.exports.main();
  assert.equal(instance.exports['configured-count'](), BigInt(config.count));
  const start = process.hrtime.bigint();
  result = instance.exports.bench(BigInt(config.count));
  assert.equal(result, BigInt(config.expected));
  seconds = Number(process.hrtime.bigint() - start) / 1e9;
} catch (error) { failure = error; }
finally {
  try { assert.equal(close(), 0); }
  catch (error) { failure ??= error; }
}
if (failure) throw failure;
console.log(JSON.stringify({result: Number(result), seconds}));
