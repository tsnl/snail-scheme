import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';

// ---- Standalone WASI command ----

const [filename, ...args] = process.argv.slice(2);
if (!filename) throw new Error('usage: run-wasi.mjs MODULE.wasm [ARGUMENT ...]');
const wasi = new WASI({
  version: 'preview1',
  args: [filename, ...args],
  env: process.env,
  preopens: { '/': process.cwd() },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(filename));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
