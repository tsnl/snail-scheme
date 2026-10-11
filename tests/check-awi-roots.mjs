// Execute the Rust interop example, then inspect the root table. Host current
// input/output/error ports own three roots; all temporary roots must be released.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';

const [filename, expected, ...arguments_] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename, ...arguments_],
  env: process.env, preopens: { '.': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['snail:drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.host': {
  'register-finalizer': finalizers.register,
  'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
const status = wasi.start(instance);
if (status !== 0) throw new Error(`program exited ${status}`);
// Every payload bit survives boxing. Synthetic IDs test representation only;
// they never reach the name registry, which has far fewer than 2^31 entries.
const awi = instance.exports;
for (const id of [0, 0x3fffffff, 0x40000000, 0x7fffffff]) {
  const tag = id | 0x80000000;
  const a = awi.atom(tag), b = awi.atom(tag), character = awi.atom(256 + 955);
  if (awi.kind(a) !== 10 || awi.atom_value(a) !== tag || !awi.same(a, b) ||
      awi.same(a, character) || awi.identity_hash(a) !== awi.identity_hash(b))
    throw new Error(`symbol tag boundary ${id}`);
  for (const root of [a, b, character]) awi.release(root);
}
const names = awi.literal_symbol_names();
for (let id = 0; id < awi.length(names); id++) {
  const name = awi.at(names, id), symbol = awi.atom(id | 0x80000000);
  if (awi.length(name) !== awi.length(symbol)) throw new Error('symbol scalar length');
  for (let index = 0; index < awi.length(name); index++)
    if (awi.char_at(name, index) !== awi.char_at(symbol, index)) throw new Error('symbol scalar');
  awi.release(name); awi.release(symbol);
}
awi.release(names);
const actual = instance.exports.awi_live_roots.value;
if (actual !== Number(expected)) throw new Error(`expected ${expected} live roots, got ${actual}`);
