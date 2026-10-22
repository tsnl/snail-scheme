// The development loop in a browser worker: the same program `lofi serve`
// runs (bootstrap/develop.sld), linked from its modules, with the runtime
// keeping files in memory (src/runtime/src/files.rs). The page sends edits
// and asks for the files builds write; the loop's events go back to it. This
// file binds the loop's commands to the worker: timers, memory files, the
// assembler and messages. It decides nothing.
import {instantiateRuntime, linkModules, loadManifest, runModules} from './load.mjs';
import {createAssembler} from './assemble.mjs';

// ---- Memory files ----

// Paths and contents cross through the runtime's transfer buffer.
function memoryFiles(runtime) {
  const encoder = new TextEncoder();
  const exports = runtime.exports;
  return {
    put(path, bytes) {
      const name = encoder.encode(path);
      const address = exports['snail:files/buffer'](name.length + bytes.length);
      new Uint8Array(exports.memory.buffer, address, name.length + bytes.length).set([...name, ...bytes]);
      exports['snail:files/put'](name.length, bytes.length);
    },
    get(path) {
      const name = encoder.encode(path);
      new Uint8Array(exports.memory.buffer, exports['snail:files/buffer'](name.length), name.length).set(name);
      const length = exports['snail:files/get'](name.length);
      if (length < 0) return null;
      return new Uint8Array(exports.memory.buffer, exports['snail:files/buffer'](length), length).slice();
    },
  };
}

// ---- WASI ----

// The loop needs its arguments, randomness, and standard output and error,
// which become messages; the runtime answers the rest with ENOSYS.
function wasiImports(loop) {
  const memory = () => new DataView(loop.runtime.exports.memory.buffer);
  const encoded = loop.arguments.map(argument => new TextEncoder().encode(`${argument}\0`));
  return {
    args_sizes_get(count, size) {
      memory().setUint32(count, encoded.length, true);
      memory().setUint32(size, encoded.reduce((total, bytes) => total + bytes.length, 0), true);
      return 0;
    },
    args_get(pointers, buffer) {
      for (const bytes of encoded) {
        memory().setUint32(pointers, buffer, true);
        new Uint8Array(loop.runtime.exports.memory.buffer, buffer, bytes.length).set(bytes);
        pointers += 4;
        buffer += bytes.length;
      }
      return 0;
    },
    environ_sizes_get(count, size) { memory().setUint32(count, 0, true); memory().setUint32(size, 0, true); return 0; },
    environ_get() { return 0; },
    random_get(pointer, length) { crypto.getRandomValues(new Uint8Array(loop.runtime.exports.memory.buffer, pointer, length)); return 0; },
    fd_write(fd, iovs, count, written) {
      let total = 0, text = '';
      for (let i = 0; i < count; i++) {
        const pointer = memory().getUint32(iovs + 8 * i, true), length = memory().getUint32(iovs + 8 * i + 4, true);
        text += new TextDecoder().decode(new Uint8Array(loop.runtime.exports.memory.buffer, pointer, length));
        total += length;
      }
      if (fd === 2) loop.errors += text;
      postMessage({type: 'log', text, error: fd === 2});
      memory().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`the development loop exited with status ${code}`); },
  };
}

// ---- The loop ----

// Event 1 is a changed file, 2 the timer, 3 a build that panicked, with the
// panic's message; the event's text goes first, a character at a time.
function send(loop, kind, text) {
  enter(loop, () => {
    for (const character of text) loop.main.develop_character(character.codePointAt(0));
    loop.main.develop_event(kind);
  });
}

function enter(loop, call) {
  loop.errors = '';
  try {
    call();
  } catch {
    send(loop, 3, loop.errors.trim().replace(/^lofi: /, '') || 'the build failed');
  }
}

// Numbered as the `develop` effect's commands in src/lofi/develop.sld; a
// browser watches nothing and runs no programs, and its directories need
// no making.
function commands(loop) {
  return [
    null,
    () => {},
    (_, milliseconds) => { clearTimeout(loop.timer); loop.timer = setTimeout(() => send(loop, 2, ''), milliseconds); },
    ([text, module]) => {
      try { loop.files.put(module, loop.assemble(new TextDecoder().decode(loop.files.get(text)))); return 0; }
      catch (error) { postMessage({type: 'log', text: error.message, error: true}); return 1; }
    },
    ([routes]) => { loop.routes = JSON.parse(new TextDecoder().decode(loop.files.get(routes))); },
    ([event]) => postMessage({type: 'event', text: event}),
    () => {},
    ([path]) => digest(loop.files.get(path)),
    () => Math.round(performance.now()) | 0,
    ([directory, output]) => loop.files.put(output, new TextEncoder().encode(listing(loop, directory))),
    () => {},
  ];
}

// FNV-1a over the bytes, which change when the file does.
function digest(bytes) {
  let hash = 0x811c9dc5;
  for (const byte of bytes ?? []) hash = Math.imul(hash ^ byte, 0x01000193);
  return hash | 0;
}

function listing(loop, directory) {
  const prefix = `${directory}/`;
  return [...loop.paths].filter(path => path.startsWith(prefix) && !path.slice(prefix.length).includes('/'))
    .map(path => path.slice(prefix.length)).join('\n');
}

async function startLoop({files, application}) {
  const fetchBytes = async url => new Uint8Array(await (await fetch(url)).arrayBuffer());
  const toolchain = new URL('toolchain/', import.meta.url);
  // The repository's root is empty, so the library is at /lib.
  const loop = {arguments: ['develop', '', '/runtime.wasm', '/reload.wasm', 'serve', '0', application], errors: '', paths: new Set()};
  const loaded = await loadManifest(file => fetchBytes(new URL(file, toolchain)), 'modules.json');
  loop.runtime = await instantiateRuntime(loaded.runtime, {wasi_snapshot_preview1: wasiImports(loop)});
  loop.runtime.exports._initialize();
  loop.runtime.exports['snail:files/use-memory']();
  loop.files = memoryFiles(loop.runtime);
  for (const [path, text] of Object.entries(files)) { loop.files.put(path, new TextEncoder().encode(text)); loop.paths.add(path); }
  loop.files.put('/runtime.wasm', await fetchBytes(new URL('runtime.wasm', toolchain)));
  loop.assemble = await createAssembler(await fetchBytes(new URL('assembler.wasm', import.meta.url)));
  const develop = {
    'argument-character': code => { loop.current += String.fromCodePoint(code); },
    'argument-end': () => { loop.staged.push(loop.current); loop.current = ''; },
    command: (code, number) => loop.commands[code](loop.staged.splice(0), number) ?? 0,
  };
  Object.assign(loop, {staged: [], current: '', commands: commands(loop)});
  const linked = await linkModules(loop.runtime, loaded.modules, {'snail.develop': develop});
  loop.main = linked.get('main').exports;
  enter(loop, () => runModules(linked, loaded.modules.map(entry => entry.name)));
  return loop;
}

// ---- Messages ----

// The routes the loop served map a page's request to a memory file, as a
// server's would.
function routeFile(routes, path) {
  if (routes.files[path]) return routes.files[path];
  const prefix = Object.keys(routes.directories).sort((a, b) => b.length - a.length).find(entry => path.startsWith(entry));
  return prefix ? routes.directories[prefix] + path.slice(prefix.length) : null;
}

let loop = null;
onmessage = async ({data}) => {
  if (data.type === 'start') loop = await startLoop(data);
  else if (data.type === 'edit') {
    loop.files.put(data.path, new TextEncoder().encode(data.text));
    send(loop, 1, data.path);
  } else if (data.type === 'read') {
    const file = routeFile(loop.routes, data.path);
    postMessage({type: 'read', id: data.id, bytes: file ? loop.files.get(file) : null});
  }
};
