#!/usr/bin/env node
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {linkedFileImports, runMain, wasmImports} from '../browser/load.mjs';
import {instantiateProgram} from '../browser/memory.mjs';
import {createTasks, taskExports} from '../browser/tasks.mjs';
import {createTcp} from './tcp.mjs';
import {createUdp} from './udp.mjs';
import {socketImports} from './socket-imports.mjs';
import {createProcesses, createTermination} from './process.mjs';
import {processImports} from './process-imports.mjs';
import {createAsyncFiles} from './async-files.mjs';
import {webImports} from './web-imports.mjs';
import {nodeGpu} from './gpu.mjs';
import {startTrace, traceFile} from '../browser/trace.mjs';

// ---- One reactor initialization and one program invocation ----
//
// A program is one linked module, as every build writes. It may load
// modules while it runs, through (snail shell wasm); a loaded module links
// only against what the program kept exported, which is nothing of the
// runtime's. The files the program links are objects of store/ beside it,
// read when a task first reads each.

// The status: 0 when every task finishes. A WASI exit is its own status,
// and one in the first turn ends the program before its other tasks run.
// A task that traps or exits after the first turn fails the run, status
// 1. A trap in the first turn, or a failure of the host, is status 2,
// told as `snail: MESSAGE`. The compiled compiler is run by this too: a
// compile that fails, or needs an input, exits with status 1.

// Node's WASI keeps an exit's status where only `start` reads it, and a
// program is a reactor, so its `proc_exit` throws an Exit instead.
class Exit { constructor(code) { this.code = code; } }

function exiting(wasi) {
  const imports = wasi.getImportObject();
  const native = imports.wasi_snapshot_preview1;
  imports.wasi_snapshot_preview1 = {...native, proc_exit(code) { throw new Exit(code); },
    // uvwasi resolves SYMLINK_FOLLOW before applying CREAT | EXCL. Clear
    // that lookup flag for exclusive creation so a dangling leaf cannot
    // become a newly created link target before the OS checks exclusivity.
    path_open(fd, lookup, path, length, flags, ...rest) {
      return native.path_open(fd, (flags & 5) === 5 ? lookup & ~1 : lookup, path, length, flags, ...rest);
    },
  };
  return {getImportObject: () => imports, initialize: instance => wasi.initialize(instance)};
}

async function run(filename, arguments_) {
  const freshWasi = () => exiting(new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}}));
  const wasi = freshWasi();
  let program, failed = false, status = 0;
  const tcp = createTcp(), udp = createUdp(), processes = createProcesses();
  const termination = createTermination();
  // A task's exit has told its message already.
  const report = error => { failed = true; if (error instanceof Error) console.error(`snail: ${error.message}`); };
  const tasks = createTasks(() => program && taskExports(program), {reportError: report});
  const asyncFiles = createAsyncFiles(tasks);
  const host = {'snail.runtime.wasm': wasmImports(() => program),
                'snail.runtime.native.async-files': asyncFiles.imports,
                'snail.runtime.native.socket': socketImports(() => program, tasks, tcp, udp),
                'snail.runtime.native.process': processImports(() => program, tasks, processes, termination),
                'snail.runtime.native.web': webImports(tasks),
                'snail.runtime.gpu': nodeGpu(() => program, tasks).imports};
  // A task waiting on a timer or a ticket is live work even when no OS
  // handle keeps Node alive.
  const keepAlive = setInterval(() => {}, 60_000);
  try {
    program = await loadProgram(resolve(filename), wasi, host, () => tasks);
    program.wasi = freshWasi;
    runMain(program.exports, tasks);
    // Main is a task, and its first turn runs here, so a trap in it fails
    // the start.
    tasks.call('tasks:turn', BigInt(Date.now()));
    await tasks.drive().catch(report);
    if (failed) status = 1;
  } catch (error) {
    if (!(error instanceof Exit)) throw error;
    status = error.code;
  } finally {
    try {
      tasks.close(); termination.close();
      await Promise.all([tcp.shutdown(), udp.shutdown(), processes.shutdown(), asyncFiles.close()]);
    }
    finally {
      clearInterval(keepAlive);
      if (program && program.exports['close-resources']() !== 0 && status === 0) status = 1;
    }
  }
  return status;
}

// The program's one module, which holds its runtime.
async function loadProgram(filename, wasi, host, tasks) {
  const read = file => readFile(resolve(dirname(filename), file));
  const module = await WebAssembly.compile(await readFile(filename));
  const imports = {...wasi.getImportObject(), ...host, ...linkedFileImports(read, module, tasks)};
  const instance = await instantiateProgram(module, imports);
  wasi.initialize(instance);
  return {runtime: instance, exports: instance.exports, host};
}

// ---- The program on the main thread ----

// The program runs on Node's main thread, as a page runs one on its own,
// so signals reach its tasks directly and `exec` replaces the process at
// once. With SNAIL_TRACE=FILE, the run writes a trace of its spans to FILE
// as it ends (host/browser/trace.mjs). Tail calls are the language's constant-stack loop mechanism, so
// V8's default stack suits it; a larger young generation, which a caller
// may give with --max-semi-space-size, helps only a program that copies
// long lists. A run that ends without a status failed in its host.
export async function start(filename, arguments_) {
  process.exitCode = 2;
  try {
    if (!filename) throw new Error('usage: run-snail.mjs MODULE.wasm [ARGUMENT ...]');
    const trace = process.env.SNAIL_TRACE;
    if (trace) startTrace();
    process.exitCode = await run(filename, arguments_);
    if (trace) await writeFile(trace, await traceFile());
  } catch (error) {
    console.error(`snail: ${error instanceof Error ? error.message : String(error)}`);
  }
}

// As a command, this runs the module its first argument names; a Node
// package's main.mjs imports it and names its own. Neither waits at the
// top level, so `require` can load the package too, as an executable's
// injected script does (doc/book/snail-scheme/projects.md, "A Node package").
if (import.meta.main) {
  const [filename, ...arguments_] = process.argv.slice(2);
  start(filename, arguments_);
}
