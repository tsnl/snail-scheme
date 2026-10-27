#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';
import {linkProgram, wasmImports} from '../browser/load.mjs';
import {createScheduler, taskImports} from '../browser/tasks.mjs';
import {createTcp} from './tcp.mjs';
import {createUdp} from './udp.mjs';
import {socketImports} from './socket-imports.mjs';

// ---- One reactor initialization and one program invocation ----
//
// A program is one linked module, or a modules.json naming the modules of a
// program compiled one library at a time (host/browser/load.mjs). Either may
// load modules while it runs, through (snail-core wasm); a linked module links
// only against what the program kept exported, which for one linked module
// is nothing of the runtime's.

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
  let program, failed = false, status = 1;
  const tcp = createTcp(), udp = createUdp();
  // WASI exits throw an opaque sentinel after printing their diagnostic.
  const scheduler = createScheduler({reportError: error => { failed = true; if (error instanceof Error) console.error(`snail: ${error.message}`); }});
  const host = {'snail.wasm': wasmImports(() => program, file => readFileSync(file)), 'snail.tasks': taskImports(() => scheduler),
                'snail.socket': socketImports(() => program, scheduler, tcp, udp)};
  // A parked JSPI stack is live work even when no OS handle keeps Node alive.
  const keepAlive = setInterval(() => {}, 60_000);
  try {
    program = await loadProgram(resolve(filename), wasi, host);
    status = resultStatus(await runInitializers(program, scheduler));
    if (failed) status = 1;
  } finally {
    try { await scheduler.close(); await Promise.all([tcp.shutdown(), udp.shutdown()]); }
    finally {
      clearInterval(keepAlive);
      if (program) {
        const close = program.runtime.exports[program.names ? 'snail:io/close-all' : 'close-resources'];
        if (close() !== 0 && status === 0) status = 1;
      }
    }
  }
  return status;
}

async function loadProgram(filename, wasi, host) {
  if (filename.endsWith('.json')) return linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  const {instance: runtime} = await WebAssembly.instantiate(await readFile(filename), {...wasi.getImportObject(), ...host});
  wasi.initialize(runtime);
  return {runtime, host, linked: new Map()};
}

// Module initialization remains ordered. Work dispatched by any initializer
// belongs to this runtime and may outlive the program's main invocation.
async function runInitializers(program, scheduler) {
  const modules = program.names ? program.names.map(name => program.linked.get(name)) : [program.runtime];
  let result = 0;
  for (const {exports} of modules) result = await scheduler.start(() => WebAssembly.promising(exports.main)()).done;
  await scheduler.drain();
  return result;
}

// ---- A worker with room to allocate ----

// A small young generation copies long lists repeatedly. Keep the heap
// tuning in one worker; JSPI uses its own finite, engine-managed stacks.
// Tail calls are the language's constant-stack loop mechanism.
const limits = {maxYoungGenerationSizeMb: 384};

if (isMainThread) {
  process.exitCode = 1;
  const worker = new Worker(new URL(import.meta.url), {workerData: process.argv.slice(2), resourceLimits: limits});
  worker.on('message', status => { process.exitCode = status; });
  worker.on('error', error => console.error(`snail: ${error.message}`));
} else {
  const [filename, ...arguments_] = workerData;
  try {
    if (!filename) throw new Error('usage: run-snail.mjs MODULE.wasm [ARGUMENT ...]');
    parentPort.postMessage(await run(filename, arguments_));
  } catch (error) {
    // A WASI exit unwinds as a non-Error value after its message is printed.
    if (error instanceof Error) console.error(`snail: ${error.message}`);
  }
}
