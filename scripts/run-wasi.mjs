#!/usr/bin/env node
// Expose the working directory at both its relative and absolute WASI paths.
// Scheme arguments and environment variables pass
// through unchanged after the module filename.
import { readFile, realpath, stat } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { dirname, resolve } from 'node:path';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';

const [filename, ...args] = process.argv.slice(2);
if (!filename) {
  console.error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exit(2);
}
const cwd = process.cwd();
const env = { ...process.env };
const preopens = { '.': cwd, [cwd]: cwd };
// Resolve the selected payload once. A newer public symlink must not redirect a
// running module's later dependency lookup to a different build generation.
const payload = await realpath(filename);
const artifactRoot = process.env.SNAIL_ARTIFACT_ROOT || resolve(dirname(payload), 'artifacts');
try {
  if ((await stat(artifactRoot)).isDirectory()) {
    preopens['/snail-artifacts'] = artifactRoot;
    env.SNAIL_ARTIFACT_ROOT = '/snail-artifacts';
  }
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
const wasi = new WASI({
  version: 'preview1',
  args: [filename, ...args],
  env,
  preopens,
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(payload));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['snail:drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.host': {
  'register-finalizer': finalizers.register,
  'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
process.exitCode = wasi.start(instance);
