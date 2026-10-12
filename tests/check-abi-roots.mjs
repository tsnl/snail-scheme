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

function checkKind(root, expectedKind) {
  const retained = abi.retain(root), live = abi.abi_live_roots.value;
  if (abi.kind(root) !== expectedKind) throw new Error(`kind: expected ${expectedKind}`);
  for (const kind of [...Array(18).keys(), 99, 0xffffffff]) {
    if (abi.is_kind(root, kind) !== Number(kind === expectedKind))
      throw new Error(`is_kind: expected ${expectedKind}, tested ${kind}`);
  }
  if (abi.abi_live_roots.value !== live || !abi.same(root, retained))
    throw new Error('category tests changed root ownership or value');
  abi.release(retained);
}

for (const [tag, kind] of [[0, 1], [1, 1], [2, 2], [3, 0], [4, 3], [5, 16],
  [6, 6], [255, 6], [256, 6], [0x7fffffff, 6], [-1, 10], [-0x80000000, 10]]) {
  const root = abi.atom(tag);
  checkKind(root, kind);
  abi.release(root);
}
const small = abi.integer(1n), large = abi.integer(1n << 40n), vector = abi.vector_new(0);
const roots = [[small, 4], [large, 4], [vector, 8], [abi.real(1.5), 5],
  [abi.pair(small, large), 7], [abi.string_new(0), 9], [abi.bytes_new(0), 11],
  [abi.extension(0, 0), 14], [abi.values(vector), 15], [abi.complex(small, small), 17]];
for (const [root, kind] of roots) checkKind(root, kind);
for (const [root] of roots) abi.release(root);
for (const invalid of [roots.at(-1)[0], 0xffffffff]) {
  let trapped = false;
  try { abi.is_kind(invalid, 99); } catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
  }
  if (!trapped) throw new Error('invalid root did not trap for unknown category');
}

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
