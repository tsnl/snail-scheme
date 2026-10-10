#!/usr/bin/env node
// Expose the working directory at both its relative and absolute WASI paths.
// Scheme arguments and environment variables pass
// through unchanged after the module filename.
import { mkdir, readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { resolve } from 'node:path';
import { createFinalizers } from '../runtime/host.mjs';

const [filename, ...args] = process.argv.slice(2);
if (!filename) {
  console.error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exit(2);
}
const cwd = process.cwd();
const traceDirectory = resolve(process.env.SNAIL_TRACE_DIR || 'build/traces');
// Give standalone WASI programs the same tracing destination as native ones,
// including overrides outside the working directory. Failure remains nonfatal.
const env = { ...process.env, SNAIL_TRACE_DIR: '/snail-traces' };
const preopens = { '.': cwd, [cwd]: cwd };
try {
  await mkdir(traceDirectory, { recursive: true });
  preopens['/snail-traces'] = traceDirectory;
} catch (error) {
  // WASI's cwd preopen can otherwise resolve /snail-traces inside cwd and
  // silently record to a different destination. Forward the original failure.
  env.SNAIL_TRACE_OPEN_ERROR = error.message;
}
const wasi = new WASI({
  version: 'preview1',
  args: [filename, ...args],
  env,
  preopens,
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(filename));
let instance;
const finalizers = createFinalizers((kind, id) =>
  instance.exports['snail:drop-resource'](kind, id));
const imports = { ...wasi.getImportObject(), 'snail.host': {
  'register-finalizer': finalizers.register,
  'unregister-finalizer': finalizers.unregister,
} };
instance = await WebAssembly.instantiate(module, imports);
process.exitCode = wasi.start(instance);
