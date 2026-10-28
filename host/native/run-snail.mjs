#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';
import {linkedFileImports, linkProgram, wasmImports} from '../browser/load.mjs';
import {createScheduler, taskImports} from '../browser/tasks.mjs';
import {createTcp} from './tcp.mjs';
import {createUdp} from './udp.mjs';
import {socketImports} from './socket-imports.mjs';
import {createProcesses, createTermination} from './process.mjs';
import {processImports} from './process-imports.mjs';

// ---- One reactor initialization and one program invocation ----
//
// A program is one linked module, or a modules.json naming the modules of a
// program compiled one library at a time (host/browser/load.mjs). Either may
// load modules while it runs, through (snail-core wasm); a linked module links
// only against what the program kept exported, which for one linked module
// is nothing of the runtime's. The files a program links are read from
// resources/ beside it before it starts.

function resultStatus(value) {
  if (value === undefined) return 0;
  if ((typeof value === 'number' || typeof value === 'bigint') && value >= 0 && value <= 255) {
    return Number(value);
  }
  return 1;
}

async function run(filename, arguments_, termination) {
  const wasi = new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, returnOnExit: true});
  let program, failed = false, status = 1;
  const tcp = createTcp(), udp = createUdp(), processes = createProcesses();
  // WASI exits throw an opaque sentinel after printing their diagnostic.
  const scheduler = createScheduler({reportError: error => { failed = true; if (error instanceof Error) console.error(`snail: ${error.message}`); }});
  const host = {'snail.wasm': wasmImports(() => program), 'snail.tasks': taskImports(() => scheduler),
                'snail.socket': socketImports(() => program, scheduler, tcp, udp),
                'snail.process': processImports(() => program, scheduler, processes, termination)};
  // A parked JSPI stack is live work even when no OS handle keeps Node alive.
  const keepAlive = setInterval(() => {}, 60_000);
  try {
    program = await loadProgram(resolve(filename), wasi, host);
    status = resultStatus(await runInitializers(program, scheduler));
    if (failed) status = 1;
  } finally {
    try { await scheduler.close(); await Promise.all([tcp.shutdown(), udp.shutdown(), processes.shutdown()]); }
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
  const read = file => readFile(resolve(dirname(filename), file));
  if (filename.endsWith('.json')) return linkProgram(read, filename, wasi, host);
  const module = await WebAssembly.compile(await readFile(filename));
  const runtime = await WebAssembly.instantiate(module, {...wasi.getImportObject(), ...host, ...await linkedFileImports(read, module)});
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

// ---- Termination signals ----

// SIGINT and SIGTERM reach only the main thread. They go to the program's
// tasks waiting in `termination`, (snail-core process); with none waiting,
// they end the process as Node's default does, by the same signal. The
// worker counts its waiters in shared memory, read when the signal
// arrives, so no message is in flight while a new waiter could miss it.
// Raising a signal again restores the default only because these are the
// main thread's only listeners for it.
const terminations = ['SIGINT', 'SIGTERM'];

function forwardTerminations(worker, waiting) {
  function forward(name) {
    if (Atomics.load(waiting, 0) > 0) { worker.postMessage(name); return; }
    for (const each of terminations) process.removeListener(each, forward);
    process.kill(process.pid, name);
  }
  for (const name of terminations) process.on(name, forward);
}

// ---- A worker with room to allocate ----

// A small young generation copies long lists repeatedly. Keep the heap
// tuning in one worker; JSPI uses its own finite, engine-managed stacks.
// Tail calls are the language's constant-stack loop mechanism.
const limits = {maxYoungGenerationSizeMb: 384};

if (isMainThread) {
  process.exitCode = 1;
  const waiting = new Int32Array(new SharedArrayBuffer(4));
  const worker = new Worker(new URL(import.meta.url), {workerData: {arguments: process.argv.slice(2), waiting}, resourceLimits: limits});
  forwardTerminations(worker, waiting);
  worker.on('message', status => { process.exitCode = status; });
  worker.on('error', error => console.error(`snail: ${error.message}`));
} else {
  const {arguments: [filename, ...arguments_], waiting} = workerData, termination = createTermination(waiting);
  // Forwarded signals must not keep a finished program alive.
  parentPort.on('message', name => termination.deliver(name));
  parentPort.unref();
  try {
    if (!filename) throw new Error('usage: run-snail.mjs MODULE.wasm [ARGUMENT ...]');
    parentPort.postMessage(await run(filename, arguments_, termination));
  } catch (error) {
    // A WASI exit unwinds as a non-Error value after its message is printed.
    if (error instanceof Error) console.error(`snail: ${error.message}`);
  }
}
