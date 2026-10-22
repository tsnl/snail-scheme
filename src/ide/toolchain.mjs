// The development loop in a browser worker: src/ide/develop.sld, linked
// from its modules, which is the loop `lofi serve` runs with its files here.
// The worker holds every file the loop can open: the standard library under
// /lib, the project under /project as the editor has it, and what builds
// write. This file binds the loop's `files` effect and `develop` commands to
// those files, timers, the assembler and messages to the page. It decides
// nothing.
import {commandImports, createWasi, linkProgram, programExports, runProgram} from './load.mjs';
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

// ---- The loop ----

// The loop's events, numbered as `deliver-event!` in src/lofi/develop.sld
// numbers them. An event's text goes first, a character at a time.
const CHANGED = 1, TIMER = 2, FAILED = 3;

function send(loop, kind, text) {
  enter(loop, () => {
    const {develop_character, develop_event} = programExports(loop.program);
    for (const character of text) develop_character(character.codePointAt(0));
    develop_event(kind);
  });
}

// A panic prints its message before it exits; a file the loop cannot open
// throws from here, with its own.
function enter(loop, call) {
  loop.errors = '';
  try {
    call();
  } catch (error) {
    send(loop, FAILED, loop.errors.trim().replace(/^lofi: /, '') || error.message);
  }
}

// The `develop` effect's commands, by the names src/lofi/develop.sld gives
// them. Edits arrive as messages, so nothing is watched; a browser runs no
// programs and its directories need no making.
function commands(loop) {
  const {files} = loop;
  return {
    watch() {},
    schedule(_, milliseconds) {
      clearTimeout(loop.timer);
      loop.timer = setTimeout(() => send(loop, TIMER, ''), milliseconds);
    },
    assemble([text, module]) {
      try { files.set(module, loop.assemble(decoder.decode(files.get(text)))); return 0; }
      catch (error) { postMessage({type: 'log', text: error.message, error: true}); return 1; }
    },
    serve([routes]) { loop.routes = JSON.parse(decoder.decode(files.get(routes))); },
    broadcast([event]) { postMessage({type: 'event', text: event}); },
    digest: ([path]) => digest(files.get(path)),
    now: () => Math.round(performance.now()) | 0,
    'list-directory'([directory, output]) { files.set(output, encoder.encode(listing(files, directory))); },
    'make-directory'() {},
    'remove-file'([path]) { files.delete(path); },
  };
}

// The library's and the project's files go in before the loop starts,
// which builds first. The loop's arguments are those `lofi serve` passes
// (bootstrap/develop.sld): the root is '', so the standard library is under
// /lib and builds write under /build; the runtime is the one fetched here;
// and the reload client is the preview's own, from the IDE's site, so the
// loop's route to /reload.wasm is never asked for.
async function startLoop({library, project}) {
  const fetchBytes = async url => new Uint8Array(await (await fetch(url)).arrayBuffer());
  const toolchain = new URL('toolchain/', import.meta.url);
  const loop = {errors: '', files: new Map()};
  for (const [path, text] of Object.entries(library)) loop.files.set(path, encoder.encode(text));
  for (const [path, text] of Object.entries(project)) loop.files.set(`/project/${path}`, encoder.encode(text));
  loop.files.set('/runtime.wasm', await fetchBytes(new URL('runtime.wasm', toolchain)));
  loop.assemble = await createAssembler(await fetchBytes(new URL('assembler.wasm', import.meta.url)));
  const wasi = createWasi({args: ['develop', '', '/runtime.wasm', '/reload.wasm', 'serve', '0', '/project'], print: (fd, line) => {
    if (fd === 2) loop.errors += `${line}\n`;
    postMessage({type: 'log', text: line, error: fd === 2});
  }});
  const host = {'snail.develop': commandImports(commands(loop)), 'snail.files': filesImports(loop.files)};
  loop.program = await linkProgram(file => fetchBytes(new URL(file, toolchain)), 'modules.json', wasi, host);
  enter(loop, () => runProgram(loop.program));
  return loop;
}

// ---- Messages ----

// The routes the loop served map a page's request to a file, as a server's
// would: the path's exact route, then each directory whose prefix it
// starts with, in order, the first that has the file.
function routeFile(loop, path) {
  const exact = loop.routes.files.find(([route]) => route === path);
  if (exact) return exact[1];
  for (const [prefix, directory] of loop.routes.directories) {
    const file = directory + path.slice(prefix.length);
    if (path.startsWith(prefix) && loop.files.has(file)) return file;
  }
  return null;
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
    send(loop, CHANGED, `/project/${data.path}`);
  } else if (data.type === 'connect') {
    ports[0].onmessage = ({data: request}) => {
      const file = routeFile(loop, request.path), bytes = file ? loop.files.get(file) : null;
      ports[0].postMessage({id: request.id, bytes: bytes ?? null});
    };
  }
};
