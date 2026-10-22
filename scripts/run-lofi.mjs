#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {WASI} from 'node:wasi';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';
import {instantiateRuntime, linkModules, loadManifest, runModules} from '../src/app/load.mjs';

// ---- One reactor initialization and one program invocation ----
//
// A program is one linked module, or a modules.json naming the modules of a
// program compiled one library at a time (src/app/load.mjs).

function resultStatus(value) {
  if (value === undefined) return 0;
  if ((typeof value === 'number' || typeof value === 'bigint') && value >= 0 && value <= 255) {
    return Number(value);
  }
  return 1;
}

async function run(filename, arguments_) {
  const wasi = new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, returnOnExit: true});
  if (filename.endsWith('.json')) return runLinked(filename, wasi);
  const {instance} = await WebAssembly.instantiate(await readFile(filename), wasi.getImportObject());
  let status = 1;
  try {
    wasi.initialize(instance);
    status = resultStatus(instance.exports.main());
  } finally {
    if (instance.exports['close-resources']() !== 0 && status === 0) status = 1;
  }
  return status;
}

// A modules.json names a program compiled one library at a time; the
// runtime is its own instance, which the modules import from.
async function runLinked(manifest, wasi) {
  const {runtime, modules} = await loadManifest(file => readFile(join(dirname(manifest), file)));
  const instance = await instantiateRuntime(runtime, wasi.getImportObject());
  wasi.initialize(instance);
  let status = 1;
  try {
    status = resultStatus(runModules(await linkModules(instance, modules, {}), modules.map(entry => entry.name)));
  } finally {
    if (instance.exports['snail:io/close-all']() !== 0 && status === 0) status = 1;
  }
  return status;
}

// ---- A worker with room to recurse and allocate ----

// V8's defaults suit JavaScript: a 1 MB stack overflows on recursion a few
// tens of thousands of calls deep, and a small young generation copies long
// lists over and over. The operating system fixes the main thread's stack,
// so the program runs in a worker that sets its own. Browsers keep their
// limits.
const limits = {stackSizeMb: 256, maxYoungGenerationSizeMb: 384};

if (isMainThread) {
  process.exitCode = 1;
  const worker = new Worker(new URL(import.meta.url), {workerData: process.argv.slice(2), resourceLimits: limits});
  worker.on('message', status => { process.exitCode = status; });
  worker.on('error', error => console.error(`lofi: ${error.message}`));
} else {
  const [filename, ...arguments_] = workerData;
  try {
    if (!filename) throw new Error('usage: run-lofi.mjs MODULE.wasm [ARGUMENT ...]');
    parentPort.postMessage(await run(filename, arguments_));
  } catch (error) {
    // A WASI exit unwinds as a non-Error value after its message is printed.
    if (error instanceof Error) console.error(`lofi: ${error.message}`);
  }
}
