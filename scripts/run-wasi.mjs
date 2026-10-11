#!/usr/bin/env node
// Expose the working directory at both its relative and absolute WASI paths.
// Scheme arguments and environment variables pass
// through unchanged after the module filename.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';

const [filename, ...args] = process.argv.slice(2);
if (!filename) {
  console.error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exit(2);
}
const cwd = process.cwd();
const preopens = { '.': cwd, [cwd]: cwd };
const wasi = new WASI({
  version: 'preview1',
  args: [filename, ...args],
  env: process.env,
  preopens,
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(filename));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['snail:drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.host': {
  'register-finalizer': finalizers.register,
  'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
process.exitCode = wasi.start(instance);
