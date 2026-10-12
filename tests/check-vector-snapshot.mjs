// Exercise real ABI envelopes, including singleton envelopes that the Rust SDK
// normally normalizes. Retained roots keep their mutable backing arrays alive.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';
import { createBuildEffects } from '../src/runtime/build.mjs';

const [filename, mode] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename], env: process.env,
  preopens: { '.': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
let instance, abi, outer, inner;
const roots = [];
const keep = root => { roots.push(root); return root; };
const node = { cwd: process.cwd(), exports: null };
const build = createBuildEffects(node);
const finalizers = createFinalizers((kind, id) => instance.exports['ports/drop-resource'](kind, id));

function backing(count, value) {
  const result = keep(abi.vector_new(count));
  for (let i = 0; i < count; i++) abi.vector_set(result, i, value);
  return result;
}

function input() {
  const one = keep(abi.integer(1n)), two = keep(abi.integer(2n));
  inner = backing(mode === 'bad-inner' ? 2 : 1, two);
  const nested = mode !== 'single';
  outer = backing(mode === 'bad-outer' ? 2 : 1, nested ? keep(abi.values(inner)) : two);
  const result = abi.vector_new(2);
  abi.vector_set(result, 0, one);
  abi.vector_set(result, 1, keep(abi.values(outer)));
  return result; // Transfer this root to the Scheme foreign-call wrapper.
}

function mutate() {
  // Correct nesting keeps the inner envelope until the later callback: 3.
  // Discarding the first normalization would see 9; unwrapping twice sees 2.
  abi.vector_set(outer, 0, keep(abi.integer(9n)));
  abi.vector_set(inner, 0, keep(abi.integer(3n)));
  return abi.atom(3);
}

const imports = { ...wasi.getImportObject(), 'snail.node': build.imports,
  'snail.test': { 'snail:snapshot-input': input, 'snail:snapshot-mutate!': mutate },
  'snail.host': { 'register-finalizer': finalizers.register,
    'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister } };
instance = await WebAssembly.instantiate(module, imports);
abi = node.exports = instance.exports;
try { process.exitCode = wasi.start(instance); }
finally { for (const root of roots) abi.release(root); }
