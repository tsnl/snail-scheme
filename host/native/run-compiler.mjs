// A synchronous compiler invocation. A compile that needs an input writes
// its request.datum and exits with status 1, as a failed compile does.
import {readFileSync} from 'node:fs';
import {WASI} from 'node:wasi';

async function compile(filename, args) {
  const wasi = new WASI({version: 'preview1', args: [filename, ...args],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, returnOnExit: true});
  const imports = wasi.getImportObject(), exited = Symbol('compiler exit');
  let status = 0, completed = false;
  imports.wasi_snapshot_preview1.proc_exit = code => { status = code; throw exited; };
  const {instance} = await WebAssembly.instantiate(readFileSync(filename), imports);
  const api = instance.exports;
  try {
    wasi.initialize(instance);
    api.main(); // Initialize module state before any fallible source loading.
    try { api['compiler-compile'](); }
    catch (error) { if (error !== exited) throw error; }
    completed = true;
  } finally {
    try { if (api['close-resources']() !== 0) status = 2; }
    catch (error) { if (completed) throw error; } // Preserve the original failure.
  }
  return status;
}

process.exitCode = 2;
try {
  const [filename, ...args] = process.argv.slice(2);
  process.exitCode = await compile(filename, args);
} catch (error) {
  if (error instanceof Error) console.error(`snail: ${error.message}`);
}
