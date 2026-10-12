#!/usr/bin/env node
// Expose the working directory at both its relative and absolute WASI paths.
// Scheme arguments and environment variables pass
// through unchanged after the module filename.
import { readFile, realpath, stat } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { dirname, resolve } from 'node:path';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';
import { createBuildEffects } from '../src/runtime/build.mjs';

const command = process.argv.slice(2);
const identity = command[0] === '--identity' ? command.splice(0, 2)[1] : undefined;
const [filename, ...args] = command;
if (!filename) {
  console.error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exit(2);
}
const cwd = process.cwd();
const env = { ...process.env, SNAIL_CWD: cwd };
const preopens = { '/': '/' };
// Resolve the selected payload once. A newer public symlink must not redirect a
// running module's later dependency lookup to a different build generation.
const payload = await realpath(filename);
const artifactRoot = process.env.SNAIL_ARTIFACT_ROOT || resolve(dirname(payload), 'artifacts');
try {
  if ((await stat(artifactRoot)).isDirectory()) {
    preopens['/snail-artifacts'] = artifactRoot;
    env.SNAIL_ARTIFACT_ROOT = artifactRoot;
  }
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
const wasi = new WASI({
  version: 'preview1',
  args: [identity ?? filename, ...args],
  env,
  preopens,
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(payload));
let instance;
const node = { cwd, exports: null };
const build = createBuildEffects(node);
const finalizers = createFinalizers((kind, id) =>
  instance.exports['ports/drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.node': build.imports, 'snail.host': {
  'register-finalizer': finalizers.register,
  'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
node.exports = instance.exports;
try { process.exitCode = wasi.start(instance); }
catch (error) { build.reportFailure(); throw error; }
if (process.exitCode) build.reportFailure();
