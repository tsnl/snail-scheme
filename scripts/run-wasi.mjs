#!/usr/bin/env node
// Expose the working directory at both its relative and absolute WASI paths.
// Scheme arguments and environment variables, including SNAIL_GC_STRESS, pass
// through unchanged after the module filename.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';

const [filename, ...args] = process.argv.slice(2);
if (!filename) {
  console.error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exit(2);
}
const cwd = process.cwd();
const wasi = new WASI({
  version: 'preview1',
  args: [filename, ...args],
  env: process.env,
  preopens: { '.': cwd, [cwd]: cwd },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(filename));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
