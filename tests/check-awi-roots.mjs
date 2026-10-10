// Execute the Rust extension example, then inspect the root table. Host current
// input/output/error ports own three roots; all temporary roots must be released.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers } from '../src/runtime/host.mjs';

const [filename, expected] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename],
  env: process.env, preopens: { '.': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['snail:drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.host': {
  'register-finalizer': finalizers.register,
  'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
const status = wasi.start(instance);
if (status !== 0) throw new Error(`program exited ${status}`);
const actual = instance.exports.awi_live_roots.value;
if (actual !== Number(expected)) throw new Error(`expected ${expected} live roots, got ${actual}`);
