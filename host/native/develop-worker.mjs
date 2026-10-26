// One persistent Wasm development loop and compiler. Immediate native
// helpers run here; watcher/server/process commands go to the parent.
import {createHash} from 'node:crypto';
import {fstatSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {WASI} from 'node:wasi';
import {parentPort, workerData} from 'node:worker_threads';
import {commandImports} from '../browser/load.mjs';
import {createAssembler} from './assemble.mjs';

// ---- Program entries ----

async function startLoop({root, tools, request, errors: filename}) {
  const errors = openSync(filename, 'w+');
  const wasi = new WASI({version: 'preview1', args: ['develop', root, tools.runtime, tools.client, ...request], env: process.env,
    preopens: {'/': '/'}, returnOnExit: true, stderr: errors});
  const loop = {errors, read: 0, exports: null, assemble: await createAssembler(readFileSync(tools.assembler))};
  const imports = {...wasi.getImportObject(), 'snail.develop': commandImports(commands(loop))};
  const {instance} = await WebAssembly.instantiate(readFileSync(tools.develop), imports);
  loop.exports = instance.exports;
  wasi.initialize(instance);
  enter(loop, () => instance.exports.main());
  return loop;
}

// Text enters before its event, as the existing exposed Lofi API requires.
function deliver(loop, kind, text) {
  for (const character of text) loop.exports.develop_character(character.codePointAt(0));
  loop.exports.develop_event(kind);
}

function enter(loop, call) {
  try { call(); }
  catch (error) {
    const message = printErrors(loop).trim().replace(/^lofi: /, '') || error?.message;
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
    assemble([text, module]) {
      try {
        writeFileSync(`${module}.next`, loop.assemble(readFileSync(text, 'utf8')));
        renameSync(`${module}.next`, module);
        return 0;
      }
      catch (error) { console.error(error.message); return 1; }
    },
    digest([path]) {
      try { return createHash('sha256').update(readFileSync(path)).digest().readInt32LE(0); } catch { return 0; }
    },
    now: () => Math.round(performance.now()) | 0,
    'list-directory'([directory, output]) {
      let names = [];
      try { names = readdirSync(directory); } catch {}
      writeFileSync(output, names.join('\n'));
    },
    'make-directory'([directory]) { mkdirSync(directory, {recursive: true}); },
    'remove-file'([path]) { rmSync(path, {force: true}); },
    'rename-file'([from, to]) { renameSync(from, to); },
  };
}

const loop = await startLoop(workerData);
parentPort.on('message', ({kind, text}) => enter(loop, () => deliver(loop, kind, text)));
