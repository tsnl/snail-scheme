#!/usr/bin/env node
// The host of the development loop. The loop, (lofi develop), runs as
// WebAssembly (bootstrap/develop.sld) and decides everything: what to watch,
// when to build, what each build writes and what pages are told. This file
// binds what WebAssembly cannot reach in Node: file watching, timers, an HTTP
// server with an event stream, the in-process assembler and child
// processes. It performs the loop's commands and reports events back.
//
//   develop.mjs ROOT serve [--port PORT] APP-DIRECTORY
//   develop.mjs ROOT watch [-I DIRECTORY] SOURCE [ARGUMENT ...]
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {closeSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, watch, writeFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {extname, join, relative, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {createAssembler} from './assemble.mjs';

const usage = 'usage: lofi serve [--port PORT] APP-DIRECTORY | lofi watch [-I DIRECTORY] SOURCE [ARGUMENT ...]';

// ---- Requests ----

// The loop's request, with every path made absolute: `serve PORT APP` or
// `watch SOURCE DIRECTORY ... -- ARGUMENT ...`.
function loopRequest([command, ...rest]) {
  if (command === 'serve') {
    const port = rest[0] === '--port' ? rest.splice(0, 2)[1] : '8000';
    if (rest.length !== 1) throw new Error(usage);
    return ['serve', port, resolve(rest[0])];
  }
  if (command !== 'watch') throw new Error(usage);
  const directories = [];
  while (rest[0] === '-I' && rest.length > 1) directories.push(resolve(rest.splice(0, 2)[1]));
  if (!rest.length) throw new Error(usage);
  return ['watch', resolve(rest[0]), ...directories, '--', ...rest.slice(1)];
}

// The loop, the reload client, the runtime and the assembler, which the
// driver builds when their sources change.
function buildTools(root) {
  const result = spawnSync(join(root, 'lofi'), ['tools'], {encoding: 'utf8'});
  if (result.status !== 0) throw new Error(result.stderr.trim());
  return JSON.parse(result.stdout);
}

// ---- The loop ----

// The loop's standard error goes to a file, so the message of a panic,
// which ends the call that raised it, can be read back and reported to the
// loop as a failed build. The loop keeps its state between calls.
async function startLoop(root, tools, request) {
  mkdirSync(join(root, 'build/develop'), {recursive: true});
  const errors = openSync(join(root, 'build/develop/errors.txt'), 'w+');
  const wasi = new WASI({version: 'preview1', args: ['develop', root, tools.runtime, tools.client, ...request], env: process.env,
                         preopens: {'/': '/'}, returnOnExit: true, stderr: errors});
  const loop = {exports: null, staged: [], current: '', errors, read: 0, root};
  const develop = {
    'argument-character': code => { loop.current += String.fromCodePoint(code); },
    'argument-end': () => { loop.staged.push(loop.current); loop.current = ''; },
    command: (code, number) => commands[code](loop.staged.splice(0), number, loop) ?? 0,
  };
  const {instance} = await WebAssembly.instantiate(readFileSync(tools.develop), {...wasi.getImportObject(), 'snail.develop': develop});
  Object.assign(loop, {exports: instance.exports, assemble: await createAssembler(readFileSync(tools.assembler))});
  wasi.initialize(instance);
  enter(loop, () => instance.exports.main());
  return loop;
}

// Event 1 is a changed file, 2 the timer, 3 a build that panicked; the
// event's text goes first, a character at a time.
function send(loop, kind, text) {
  enter(loop, () => {
    for (const character of text) loop.exports.develop_character(character.codePointAt(0));
    loop.exports.develop_event(kind);
  });
}

function enter(loop, call) {
  try {
    call();
    printErrors(loop);
  } catch {
    const message = printErrors(loop).trim().replace(/^lofi: /, '');
    send(loop, 3, message || 'the build failed');
  }
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

// ---- Commands ----

// Numbered as the `develop` effect's commands in src/lofi/develop.sld.
const commands = [
  null,
  ([directory], _, loop) => {
    watch(directory, {recursive: true}, (event, name) => { if (name) send(loop, 1, join(directory, name)); });
  },
  (_, milliseconds, loop) => {
    clearTimeout(loop.timer);
    loop.timer = setTimeout(() => send(loop, 2, ''), milliseconds);
  },
  ([text, module], _, loop) => {
    try { writeFileSync(module, loop.assemble(readFileSync(text, 'utf8'))); return 0; }
    catch (error) { console.error(error.message); return 1; }
  },
  ([routes, name], port, loop) => serve(loop, JSON.parse(readFileSync(routes, 'utf8')), name, port),
  ([event], _, loop) => broadcast(loop, event),
  ([manifest, ...args], _, loop) => runProgram(loop, manifest, args),
  ([path]) => { try { return createHash('sha256').update(readFileSync(path)).digest().readInt32LE(0); } catch { return 0; } },
  () => Math.round(performance.now()) | 0,
  ([directory, output]) => { let names = []; try { names = readdirSync(directory); } catch {} writeFileSync(output, names.join('\n')); },
  ([directory]) => { mkdirSync(directory, {recursive: true}); },
];

// ---- Serving ----

// Files come from the routes the loop wrote: exact paths, then directories
// by their prefix. Nothing is cached. A page that opens the event stream
// gets the latest event first.
function serve(loop, routes, name, port) {
  loop.clients = new Set();
  const server = createServer((incoming, response) => {
    const path = decodeURIComponent(new URL(incoming.url, 'http://localhost').pathname);
    if (path === routes.events) return openEvents(loop, response);
    const file = routes.files[path] ?? directoryFile(routes.directories, path);
    if (!file) return response.writeHead(404, {'Cache-Control': 'no-store'}).end();
    try {
      const bytes = readFileSync(file);
      response.writeHead(200, {'Content-Type': routes.types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'}).end(bytes);
    } catch { response.writeHead(404, {'Cache-Control': 'no-store'}).end(); }
  });
  server.listen(port, '127.0.0.1', () => console.log(`serving ${name} at http://127.0.0.1:${server.address().port}/`));
}

function directoryFile(directories, path) {
  const prefix = Object.keys(directories).sort((a, b) => b.length - a.length).find(entry => path.startsWith(entry));
  if (!prefix) return null;
  const file = join(directories[prefix], path.slice(prefix.length));
  return relative(directories[prefix], file).startsWith('..') ? null : file;
}

function openEvents(loop, response) {
  response.writeHead(200, {'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive'});
  response.write('retry: 1000\n\n');
  if (loop.latest) writeEvent(response, loop.latest);
  loop.clients.add(response);
  response.on('close', () => loop.clients.delete(response));
}

function broadcast(loop, event) {
  loop.latest = event;
  for (const response of loop.clients ?? []) writeEvent(response, event);
}

function writeEvent(response, event) {
  response.write(`${event.split('\n').map(line => `data: ${line}`).join('\n')}\n\n`);
}

// ---- Running programs ----

// A program still running is stopped, and the new run starts once it has
// exited, so a server can bind its port again.
function runProgram(loop, manifest, args) {
  const previous = loop.child;
  const start = () => {
    const child = spawn(process.env.NODE ?? 'node', ['--no-warnings', join(loop.root, 'scripts/run-lofi.mjs'), manifest, ...args], {stdio: 'inherit'});
    child.on('exit', (code, signal) => { if (!signal) console.error(`\x1b[2m-- exited with status ${code}\x1b[0m`); });
    loop.child = child;
  };
  if (previous && previous.exitCode === null && previous.signalCode === null) { previous.once('exit', start); previous.kill(); }
  else start();
}

try {
  const [root, ...request] = process.argv.slice(2);
  const loop = await startLoop(root, buildTools(root), loopRequest(request));
  process.on('exit', () => closeSync(loop.errors));
} catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
