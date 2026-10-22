// The development loop in a browser worker: src/ide/develop.sld, linked
// from its modules, which is the loop `lofi serve` runs with its files here.
// The worker holds every file the loop can open: the standard library under
// /lib, the project under /project as the editor has it, and what builds
// write. This file binds the loop's `files` effect and `develop` commands to
// those files, timers, the assembler and messages to the page. It decides
// nothing.
import {instantiateRuntime, linkModules, loadManifest, runModules} from './load.mjs';
import {createAssembler} from './assemble.mjs';

const encoder = new TextEncoder(), decoder = new TextDecoder();

// ---- Files ----

// The `files` effect: (lofi io)'s file operations over `files`, a map from
// path to bytes. A path arrives a character at a time. An input port reads
// the file as it was opened, a UTF-8 character or a byte at a time; an
// output port gathers text and bytes in order and stores them when it
// closes.
function filesImports(files) {
  const ports = new Map();
  let path = '', next = 1;
  const open = port => { ports.set(next, port); return next++; };
  return {
    'path-begin': () => { path = ''; },
    'path-character': code => { path += String.fromCodePoint(code); },
    exists: () => (files.has(path) ? 1 : 0),
    'open-input': () => {
      if (!files.has(path)) throw new Error(`${path}: no such file`);
      return open({bytes: files.get(path), at: 0});
    },
    'open-output': () => open({path, chunks: [], text: ''}),
    read: port => readCharacter(ports.get(port)),
    'read-byte': port => { const input = ports.get(port); return input.at < input.bytes.length ? input.bytes[input.at++] : -1; },
    write: (port, code) => { ports.get(port).text += String.fromCodePoint(code); },
    'write-byte': (port, byte) => { const output = ports.get(port); keepText(output); output.chunks.push(Uint8Array.of(byte)); },
    close: port => { const output = ports.get(port); if ('chunks' in output) files.set(output.path, joined(output)); ports.delete(port); },
  };
}

// The next character of UTF-8 input, or -1 at its end.
function readCharacter(input) {
  const {bytes} = input;
  if (input.at >= bytes.length) return -1;
  const first = bytes[input.at], length = first < 0x80 ? 1 : first < 0xe0 ? 2 : first < 0xf0 ? 3 : 4;
  let code = first & [0, 0x7f, 0x1f, 0x0f, 0x07][length];
  for (let i = 1; i < length; i++) code = (code << 6) | (bytes[input.at + i] & 0x3f);
  input.at += length;
  return code;
}

function keepText(output) {
  if (output.text) output.chunks.push(encoder.encode(output.text));
  output.text = '';
}

function joined(output) {
  keepText(output);
  const bytes = new Uint8Array(output.chunks.reduce((total, chunk) => total + chunk.length, 0));
  output.chunks.reduce((at, chunk) => { bytes.set(chunk, at); return at + chunk.length; }, 0);
  return bytes;
}

// The names in a directory, as the desktop host lists them: files and
// subdirectories, one level down.
function listing(files, directory) {
  const prefix = `${directory}/`, names = new Set();
  for (const path of files.keys()) if (path.startsWith(prefix)) names.add(path.slice(prefix.length).split('/')[0]);
  return [...names].join('\n');
}

// FNV-1a over the bytes, which change when the file does.
function digest(bytes) {
  let hash = 0x811c9dc5;
  for (const byte of bytes ?? []) hash = Math.imul(hash ^ byte, 0x01000193);
  return hash | 0;
}

// ---- WASI ----

// The loop needs its arguments, randomness, and standard output and error,
// which become messages; the runtime answers the rest with ENOSYS.
function wasiImports(loop) {
  const memory = () => new DataView(loop.runtime.exports.memory.buffer);
  const bytes = (pointer, length) => new Uint8Array(loop.runtime.exports.memory.buffer, pointer, length);
  const encoded = loop.arguments.map(argument => encoder.encode(`${argument}\0`));
  return {
    args_sizes_get(count, size) {
      memory().setUint32(count, encoded.length, true);
      memory().setUint32(size, encoded.reduce((total, argument) => total + argument.length, 0), true);
      return 0;
    },
    args_get(pointers, buffer) {
      for (const argument of encoded) {
        memory().setUint32(pointers, buffer, true);
        bytes(buffer, argument.length).set(argument);
        pointers += 4;
        buffer += argument.length;
      }
      return 0;
    },
    environ_sizes_get(count, size) { memory().setUint32(count, 0, true); memory().setUint32(size, 0, true); return 0; },
    environ_get() { return 0; },
    random_get(pointer, length) { crypto.getRandomValues(bytes(pointer, length)); return 0; },
    fd_write(fd, iovs, count, written) {
      let total = 0, text = '';
      for (let i = 0; i < count; i++) {
        const length = memory().getUint32(iovs + 8 * i + 4, true);
        text += decoder.decode(bytes(memory().getUint32(iovs + 8 * i, true), length));
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

// A panic prints its message before it exits; a file the loop cannot open
// throws from here, with its own.
function enter(loop, call) {
  loop.errors = '';
  try {
    call();
  } catch (error) {
    send(loop, 3, loop.errors.trim().replace(/^lofi: /, '') || error.message);
  }
}

// Numbered as the `develop` effect's commands in src/lofi/develop.sld. Edits
// arrive as messages, so nothing is watched; a browser runs no programs and
// its directories need no making.
function commands(loop) {
  const {files} = loop;
  return [
    null,
    () => {},
    (_, milliseconds) => { clearTimeout(loop.timer); loop.timer = setTimeout(() => send(loop, 2, ''), milliseconds); },
    ([text, module]) => {
      try { files.set(module, loop.assemble(decoder.decode(files.get(text)))); return 0; }
      catch (error) { postMessage({type: 'log', text: error.message, error: true}); return 1; }
    },
    ([routes]) => { loop.routes = JSON.parse(decoder.decode(files.get(routes))); },
    ([event]) => broadcast(loop, event),
    () => 1,
    ([path]) => digest(files.get(path)),
    () => Math.round(performance.now()) | 0,
    ([directory, output]) => { files.set(output, encoder.encode(listing(files, directory))); },
    () => {},
  ];
}

// Each build names a module's file after its text, so the files of earlier
// builds pile up. Once a build is served, the modules of it and the build
// before stay, the latter for a relink that is still reading them.
function broadcast(loop, event) {
  postMessage({type: 'event', text: event});
  if (!event.startsWith('(built')) return;
  const manifest = JSON.parse(decoder.decode(loop.files.get(routeFile(loop.routes, '/modules.json'))));
  const current = new Set(manifest.modules.map(entry => routeFile(loop.routes, entry.file)));
  const directory = loop.routes.directories['/modules/'];
  for (const path of loop.files.keys()) {
    if (path.startsWith(directory) && !current.has(path) && !loop.previous.has(path)) loop.files.delete(path);
  }
  loop.previous = current;
}

// The library's and the project's files go in before the loop starts,
// which builds first.
async function startLoop({library, project}) {
  const fetchBytes = async url => new Uint8Array(await (await fetch(url)).arrayBuffer());
  const toolchain = new URL('toolchain/', import.meta.url);
  const loop = {arguments: ['develop', '', '/runtime.wasm', '/reload.wasm', 'serve', '0', '/project'], errors: '', files: new Map(),
                previous: new Set(), staged: [], current: ''};
  for (const [path, text] of Object.entries(library)) loop.files.set(path, encoder.encode(text));
  for (const [path, text] of Object.entries(project)) loop.files.set(`/project/${path}`, encoder.encode(text));
  loop.files.set('/runtime.wasm', await fetchBytes(new URL('runtime.wasm', toolchain)));
  loop.assemble = await createAssembler(await fetchBytes(new URL('assembler.wasm', import.meta.url)));
  await linkLoop(loop, await loadManifest(file => fetchBytes(new URL(file, toolchain)), 'modules.json'));
  return loop;
}

// The loop's modules, linked with the runtime and the worker's bindings,
// then run, which starts the loop.
async function linkLoop(loop, loaded) {
  loop.runtime = await instantiateRuntime(loaded.runtime, {wasi_snapshot_preview1: wasiImports(loop)});
  loop.runtime.exports._initialize();
  loop.commands = commands(loop);
  const develop = {
    'argument-character': code => { loop.current += String.fromCodePoint(code); },
    'argument-end': () => { loop.staged.push(loop.current); loop.current = ''; },
    command: (code, number) => loop.commands[code](loop.staged.splice(0), number) ?? 0,
  };
  const linked = await linkModules(loop.runtime, loaded.modules, {'snail.develop': develop, 'snail.files': filesImports(loop.files)});
  loop.main = linked.get('main').exports;
  enter(loop, () => runModules(linked, loaded.modules.map(entry => entry.name)));
}

// ---- Messages ----

// The routes the loop served map a page's request to a file, as a server's
// would.
function routeFile(routes, path) {
  if (routes.files[path]) return routes.files[path];
  const prefix = Object.keys(routes.directories).sort((a, b) => b.length - a.length).find(entry => path.startsWith(entry));
  return prefix ? routes.directories[prefix] + path.slice(prefix.length) : null;
}

// The IDE starts the loop and sends each change to a project file, saved or
// not; its preview connects a port, through which it reads the files builds
// write. Messages that arrive while the loop starts wait for it, in order.
let started = null;
onmessage = async ({data, ports}) => {
  if (data.type === 'start') { started = startLoop(data); return; }
  const loop = await started;
  if (data.type === 'write') {
    loop.files.set(`/project/${data.path}`, encoder.encode(data.text));
    send(loop, 1, `/project/${data.path}`);
  } else if (data.type === 'connect') {
    ports[0].onmessage = ({data: request}) => {
      const file = routeFile(loop.routes, request.path), bytes = file ? loop.files.get(file) : null;
      ports[0].postMessage({id: request.id, bytes: bytes ?? null});
    };
  }
};
