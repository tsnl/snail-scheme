// One persistent Wasm development loop and compiler, which does its own
// file work through the runtime's WASI and assembles its modules in-process.
// Producer runs are immediate here; watcher/server/process commands go to
// the parent.
import {spawnSync} from 'node:child_process';
import {fstatSync, openSync, readFileSync, readSync, writeSync} from 'node:fs';
import {join} from 'node:path';
import {WASI} from 'node:wasi';
import {parentPort, workerData} from 'node:worker_threads';
import {commandImports} from '../browser/load.mjs';

// ---- Program entries ----

async function startLoop({root, tools, request, errors: filename}) {
  const errors = openSync(filename, 'w+');
  const wasi = new WASI({version: 'preview1', args: ['develop', root, tools.runtime, tools.client, ...request],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, returnOnExit: true, stderr: errors});
  const loop = {root, errors, read: 0, exports: null};
  const imports = {...wasi.getImportObject(), 'snail.runtime.native.develop': commandImports(commands(loop))};
  const {instance} = await WebAssembly.instantiate(readFileSync(tools.develop), imports);
  loop.exports = instance.exports;
  wasi.initialize(instance);
  enter(loop, () => instance.exports.main());
  return loop;
}

// Text enters before its event, as the existing exposed Snail-Core API requires.
function deliver(loop, kind, text) {
  for (const character of text) loop.exports.develop_character(character.codePointAt(0));
  loop.exports.develop_event(kind);
}

function enter(loop, call) {
  try { call(); }
  catch (error) {
    const message = printErrors(loop).trim().replace(/^snail: /, '') || error?.message;
    // A compiler panic preserves the instance/session. Failure of this
    // report is a broken worker and escapes to the parent's fatal path.
    deliver(loop, 3, message || 'the build failed');
    return;
  }
  printErrors(loop);
}

function printErrors(loop) {
  const size = fstatSync(loop.errors).size;
  if (size <= loop.read) return '';
  const bytes = Buffer.alloc(size - loop.read);
  readSync(loop.errors, bytes, 0, bytes.length, loop.read);
  loop.read = size;
  process.stderr.write(bytes);
  return bytes.toString();
}

// ---- Concrete host operations ----

function commands(loop) {
  const forward = command => (args, number) => parentPort.postMessage({command, args, number});
  return {
    watch: forward('watch'), schedule: forward('schedule'), serve: forward('serve'),
    broadcast: forward('broadcast'), run: forward('run'),
    // A producer runs to completion before the build goes on. What it
    // printed on failure joins the loop's diagnostics, ahead of its panic.
    produce([manifest, output]) {
      const result = spawnSync(process.execPath, ['--no-warnings', join(loop.root, 'host/native/run-snail.mjs'), manifest, output],
        {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
      if (result.status === 0) return 0;
      writeSync(loop.errors, result.stderr || `${result.error?.message ?? `the producer exited with ${result.signal}`}\n`);
      return 1;
    },
  };
}

const loop = await startLoop(workerData);
parentPort.on('message', ({kind, text}) => enter(loop, () => deliver(loop, kind, text)));
