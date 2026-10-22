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
import {closeSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, rmSync, statSync, watch, writeFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {extname, join, relative, resolve} from 'node:path';
import {WASI} from 'node:wasi';
import {commandImports} from '../src/app/load.mjs';
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
  const loop = {exports: null, errors, read: 0, root};
  const imports = {...wasi.getImportObject(), 'snail.develop': commandImports(commands(loop))};
  const {instance} = await WebAssembly.instantiate(readFileSync(tools.develop), imports);
  Object.assign(loop, {exports: instance.exports, assemble: await createAssembler(readFileSync(tools.assembler))});
  wasi.initialize(instance);
  enter(loop, () => instance.exports.main());
  return loop;
}

// The loop's events, numbered as `deliver-event!` in src/lofi/develop.sld
// numbers them. An event's text goes first, a character at a time.
const CHANGED = 1, TIMER = 2, FAILED = 3;

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
    send(loop, FAILED, message || 'the build failed');
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

// The `develop` effect's commands, by the names src/lofi/develop.sld gives
// them.
function commands(loop) {
  return {
    watch([directory]) {
      watch(directory, {recursive: true}, (event, name) => { if (name) send(loop, CHANGED, join(directory, name)); });
    },
    schedule(_, milliseconds) {
      clearTimeout(loop.timer);
      loop.timer = setTimeout(() => send(loop, TIMER, ''), milliseconds);
    },
    assemble([text, module]) {
      try { writeFileSync(module, loop.assemble(readFileSync(text, 'utf8'))); return 0; }
      catch (error) { console.error(error.message); return 1; }
    },
    serve([routes, name], port) { serve(loop, JSON.parse(readFileSync(routes, 'utf8')), name, port); },
    broadcast([event]) { broadcast(loop, event); },
    run([manifest, ...args]) { runProgram(loop, manifest, args); },
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
  };
}

// ---- Serving ----

// Files come from the routes the loop wrote: a path's exact route, then
// each directory whose prefix the path starts with, in order, the first
// that has the file. Nothing is cached. A page that opens the event stream
// gets the latest event first.
function serve(loop, routes, name, port) {
  loop.clients = new Set();
  const server = createServer((incoming, response) => {
    const path = decodeURIComponent(new URL(incoming.url, 'http://localhost').pathname);
    if (path === routes.events) return openEvents(loop, response);
    const file = routeFile(routes, path);
    try {
      const bytes = readFileSync(file);
      response.writeHead(200, {'Content-Type': routes.types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'}).end(bytes);
    } catch { response.writeHead(404, {'Cache-Control': 'no-store'}).end(); }
  });
  server.listen(port, '127.0.0.1', () => console.log(`serving ${name} at http://127.0.0.1:${server.address().port}/`));
}

function routeFile(routes, path) {
  const exact = routes.files.find(([route]) => route === path);
  if (exact) return exact[1];
  for (const [prefix, directory] of routes.directories) {
    const file = join(directory, path.slice(prefix.length));
    if (path.startsWith(prefix) && !relative(directory, file).startsWith('..') && statSync(file, {throwIfNoEntry: false})?.isFile()) return file;
  }
  return null;
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

// A program still running is stopped, and the newest run starts once it has
// exited, so a server can bind its port again. Runs asked for while it stops
// replace one another: only the latest starts.
function runProgram(loop, manifest, args) {
  const previous = loop.child;
  loop.next = () => {
    const child = spawn(process.env.NODE ?? 'node', ['--no-warnings', join(loop.root, 'scripts/run-lofi.mjs'), manifest, ...args], {stdio: 'inherit'});
    child.on('exit', (code, signal) => { if (!signal) console.error(`\x1b[2m-- exited with status ${code}\x1b[0m`); });
    loop.child = child;
  };
  if (!previous || previous.exitCode !== null || previous.signalCode !== null) loop.next();
  else if (!previous.killed) { previous.once('exit', () => loop.next()); previous.kill(); }
}

try {
  const [root, ...request] = process.argv.slice(2);
  const loop = await startLoop(root, buildTools(root), loopRequest(request));
  process.on('exit', () => closeSync(loop.errors));
} catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
