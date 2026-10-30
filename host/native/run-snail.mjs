#!/usr/bin/env node
import {chmodSync, statSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {commandImports, linkedFileImports, linkProgram, wasmImports} from '../browser/load.mjs';
import {createTasks, taskExports} from '../browser/tasks.mjs';
import {createTcp} from './tcp.mjs';
import {createUdp} from './udp.mjs';
import {socketImports} from './socket-imports.mjs';
import {createProcesses, createTermination} from './process.mjs';
import {processImports} from './process-imports.mjs';
import {createHints} from './hints.mjs';

// ---- One reactor initialization and one program invocation ----
//
// A program is one linked module, or a modules.json naming the modules of a
// program compiled one library at a time (host/browser/load.mjs). Either may
// load modules while it runs, through (snail shell wasm); a linked module links
// only against what the program kept exported, which for one linked module
// is nothing of the runtime's. The files a program links are read from
// resources/ beside it before it starts.

// The status: the last `main`'s result when it is 0 to 255, and 1
// otherwise. A WASI exit in a `main` is its own status, and ends the
// program before its tasks run. A task that traps or exits fails the run,
// status 1, while its siblings go on. A trap or a failure of the host is
// status 2, told as `snail: MESSAGE`. crates/snail/src/program.rs keeps
// the same protocol on wasmtime, and the compiled compiler is run by it
// too: a compile that fails, or needs an input, exits with status 1.

// The `modes` effect of src/snail/shell/project/files.sld: a file's
// permission bits, which WASI cannot reach. A failure answers -1.
const modeCommands = {
  mode([path]) { try { return statSync(path).mode & 0o777; } catch { return -1; } },
  chmod([path], mode) { try { chmodSync(path, mode); return 0; } catch { return -1; } },
};

function resultStatus(value) {
  if (value === undefined) return 0;
  if ((typeof value === 'number' || typeof value === 'bigint') && value >= 0 && value <= 255) {
    return Number(value);
  }
  return 1;
}

// Node's WASI keeps an exit's status where only `start` reads it, and a
// program is a reactor, so its `proc_exit` throws an Exit instead.
class Exit { constructor(code) { this.code = code; } }

function exiting(wasi) {
  const imports = wasi.getImportObject();
  imports.wasi_snapshot_preview1 = {...imports.wasi_snapshot_preview1, proc_exit(code) { throw new Exit(code); }};
  return {getImportObject: () => imports, initialize: instance => wasi.initialize(instance)};
}

async function run(filename, arguments_) {
  const wasi = exiting(new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}}));
  let program, failed = false, status = 0;
  const tcp = createTcp(), udp = createUdp(), processes = createProcesses(), hints = createHints();
  const termination = createTermination();
  // A task's exit has told its message already.
  const report = error => { failed = true; if (error instanceof Error) console.error(`snail: ${error.message}`); };
  const tasks = createTasks(() => program && taskExports(program), {reportError: report});
  const host = {'snail.runtime.wasm': wasmImports(() => program),
                'snail.runtime.native.socket': socketImports(() => program, tasks, tcp, udp),
                'snail.runtime.native.process': processImports(() => program, tasks, processes, termination),
                'snail.runtime.native.files': {...commandImports({...modeCommands, ...hints.commands}), ...hints.waits(tasks)}};
  // A task waiting on a timer or a ticket is live work even when no OS
  // handle keeps Node alive.
  const keepAlive = setInterval(() => {}, 60_000);
  try {
    program = await loadProgram(resolve(filename), wasi, host);
    status = resultStatus(runInitializers(program));
    await tasks.drive().catch(report);
    if (failed) status = 1;
  } catch (error) {
    if (!(error instanceof Exit)) throw error;
    status = error.code;
  } finally {
    try {
      tasks.close(); hints.shutdown(); termination.close();
      await Promise.all([tcp.shutdown(), udp.shutdown(), processes.shutdown()]);
    }
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
// belongs to this runtime and may outlive the program's main invocation:
// its tasks run once every main has returned.
function runInitializers(program) {
  const modules = program.names ? program.names.map(name => program.linked.get(name)) : [program.runtime];
  let result = 0;
  for (const {exports} of modules) result = exports.main();
  return result;
}

// ---- The program on the main thread ----

// The program runs on Node's main thread, as a page runs one on its own,
// so signals reach its tasks directly and `exec` replaces the process at
// once. Tail calls are the language's constant-stack loop mechanism, so
// V8's default stack suits it; a larger young generation, which a caller
// may give with --max-semi-space-size, helps only a program that copies
// long lists. A run that ends without a status failed in its host.
process.exitCode = 2;
const [filename, ...arguments_] = process.argv.slice(2);
try {
  if (!filename) throw new Error('usage: run-snail.mjs MODULE.wasm [ARGUMENT ...]');
  process.exitCode = await run(filename, arguments_);
} catch (error) {
  console.error(`snail: ${error instanceof Error ? error.message : String(error)}`);
}
