// Execute the Rust interop example, then inspect the root table. Host current
// input/output/error ports own three roots; all temporary roots must be released.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';

import { createBuildEffects } from '../src/runtime/build.mjs';

const [filename, expected, ...arguments_] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename, ...arguments_],
  env: process.env, preopens: { '.': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['ports/drop-resource'](kind, id));
const node = { cwd: process.cwd(), exports: null };
const build = createBuildEffects(node);
const imports = { ...wasi.getImportObject(), 'snail.node': build.imports, 'snail.host': {
  'register-finalizer': finalizers.register,
  'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
node.exports = instance.exports;
const status = wasi.start(instance);
if (status !== 0) throw new Error(`program exited ${status}`);
// Every payload bit survives boxing. Synthetic IDs test representation only;
// they never reach the name registry, which has far fewer than 2^31 entries.
const abi = instance.exports;
for (const id of [0, 0x3fffffff, 0x40000000, 0x7fffffff]) {
  const tag = id | 0x80000000;
  const a = abi.atom(tag), b = abi.atom(tag), character = abi.atom(256 + 955);
  if (abi.kind(a) !== 10 || abi.atom_value(a) !== tag || !abi.same(a, b) ||
      abi.same(a, character) || abi.identity_hash(a) !== abi.identity_hash(b))
    throw new Error(`symbol tag boundary ${id}`);
  for (const root of [a, b, character]) abi.release(root);
}
const names = abi.literal_symbol_names();
for (let id = 0; id < abi.length(names); id++) {
  const name = abi.at(names, id), symbol = abi.atom(id | 0x80000000);
  if (abi.length(name) !== abi.length(symbol)) throw new Error('symbol scalar length');
  for (let index = 0; index < abi.length(name); index++)
    if (abi.char_at(name, index) !== abi.char_at(symbol, index)) throw new Error('symbol scalar');
  abi.release(name); abi.release(symbol);
}
abi.release(names);
const actual = instance.exports.abi_live_roots.value;
if (actual !== Number(expected)) throw new Error(`expected ${expected} live roots, got ${actual}`);
