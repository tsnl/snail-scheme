#!/usr/bin/env node
import {chmodSync, statSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {WASI} from 'node:wasi';
import {commandImports, instantiate, linkedFileImports, runMain, wasmImports} from '../browser/load.mjs';
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
// program compiled one library at a time, which the engine links
// ((snail shell engine), built to build/engine/engine.wasm, or where
// SNAIL_ENGINE_MODULE says): this host starts the engine with the manifest
// in SNAIL_MANIFEST, and the engine reads the objects from the store,
// links them through the Wasm primitives of load.mjs, runs each main, and
// forwards the program's scheduler as its own exports. Either may load
// modules while it runs, through (snail shell wasm); a linked module links
// only against what the program kept exported, which for one linked module
// is nothing of the runtime's. The files a linked module links are objects
// of store/ beside it, read when a task first reads each; the engine serves
// a linked program's.

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
  const freshWasi = (env = {}) => exiting(new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd(), ...env}, preopens: {'/': '/'}}));
  const wasi = freshWasi(filename.endsWith('.json') ? {SNAIL_MANIFEST: resolve(filename)} : {});
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
    program = await loadProgram(resolve(filename), wasi, host, () => tasks);
    program.wasi = () => freshWasi();
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
        const closed = [program.exports['engine:close']?.() ?? 0, program.exports['close-resources']()];
        if (closed.some(result => result !== 0) && status === 0) status = 1;
      }
    }
  }
  return status;
}

// A linked module is the program's runtime and its one module. A manifest
// is run by the engine: the instance started here is the loader, and the
// program's runtime is the instance the engine names snail.core.support,
// whose memory stages the Bytes the host's services read.
async function loadProgram(filename, wasi, host, tasks) {
  const read = file => readFile(resolve(dirname(filename), file));
  const module = await WebAssembly.compile(await readFile(filename.endsWith('.json') ? engineModule() : filename));
  const program = {runtime: null, exports: null, host, linked: new Map()};
  const engine = filename.endsWith('.json');
  const instance = await (engine ? instantiate(module, {...wasi.getImportObject(), ...host})
    : WebAssembly.instantiate(module, {...wasi.getImportObject(), ...host, ...linkedFileImports(read, module, tasks)}));
  wasi.initialize(instance);
  Object.assign(program, {runtime: instance, exports: instance.exports, loader: engine ? instance : null});
  return program;
}

function engineModule() {
  return process.env.SNAIL_ENGINE_MODULE ?? fileURLToPath(new URL('../../build/engine/engine.wasm', import.meta.url));
}

// The program's main, or the engine's, whose first task links the program
// and runs each of its mains in order, keeping the last one's result,
// `engine:status`: its first turn runs that task, whose files are read
// at once, so a WASI exit in a main is the program's status here too.
// Work dispatched by any initializer belongs to this runtime and may
// outlive the program's main invocation: its tasks run once every main
// has returned.
function runInitializers(program) {
  const result = runMain(program.exports);
  if (!program.exports['engine:status']) return result;
  program.exports['engine:turn'](BigInt(Date.now()));
  return Number(program.exports['engine:status']());
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
