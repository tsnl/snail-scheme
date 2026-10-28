#!/usr/bin/env node
// The native host owns watchers, timers, HTTP/SSE and application children.
// A persistent worker owns (snail shell develop), its synchronous Wasm compiler,
// assembler and producer runs. Compiler work never occupies this event loop.
//
//   develop.mjs ROOT serve [--port PORT] APP-DIRECTORY
//   develop.mjs ROOT watch [-I DIRECTORY] SOURCE [ARGUMENT ...]
import {spawn, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, watch} from 'node:fs';
import {createServer} from 'node:http';
import {extname, join, relative, resolve} from 'node:path';
import {Worker} from 'node:worker_threads';

const usage = 'usage: ./scripts/snail-tool serve [--port PORT] APP-DIRECTORY | ./scripts/snail-tool watch [-I DIRECTORY] SOURCE [ARGUMENT ...]';

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
  const result = spawnSync(join(root, 'scripts/snail-tool'), ['tools'], {encoding: 'utf8'});
  if (result.status !== 0) throw new Error(result.stderr.trim());
  return JSON.parse(result.stdout);
}

// ---- Compiler worker ----

// Private diagnostic storage belongs to this host. The worker's fs-opened
// descriptor closes when the worker exits; only then remove its directory.
function startLoop(root, tools, request) {
  mkdirSync(join(root, 'build/develop'), {recursive: true});
  const directory = mkdtempSync(join(root, 'build/develop/worker-'));
  const loop = {root, directory, watchers: [], clients: new Set(), stopping: false};
  try {
    loop.worker = new Worker(new URL('./develop-worker.mjs', import.meta.url), {
      workerData: {root, tools, request, errors: join(directory, 'errors.txt')},
      resourceLimits: {maxYoungGenerationSizeMb: 384}, name: 'snail-compiler',
    });
  } catch (error) { rmSync(directory, {recursive: true, force: true}); throw error; }
  loop.worker.on('message', command => {
    if (loop.stopping) return;
    try { perform(loop, command); } catch (error) { fail(loop, error); }
  });
  loop.worker.on('error', error => fail(loop, error));
  loop.worker.on('exit', code => { if (!loop.stopping) fail(loop, new Error(`compiler worker exited with status ${code}`)); });
  return loop;
}

// The loop's events, numbered as `deliver-event!` in src/snail/shell/develop.sld
// numbers them. The worker serializes calls into its one Wasm instance.
const CHANGED = 1, TIMER = 2;

function send(loop, kind, text) {
  if (!loop.stopping) loop.worker.postMessage({kind, text});
}

// ---- Commands ----

// Only commands whose results the Snail-Core loop discards cross this boundary.
// Immediate assembler and producer results stay beside their Wasm caller.
function perform(loop, {command, args, number}) {
  switch (command) {
    case 'watch': {
      const watcher = watch(args[0], {recursive: true}, (event, name) => { if (name) send(loop, CHANGED, join(args[0], name)); });
      watcher.on('error', error => fail(loop, error));
      loop.watchers.push(watcher);
      break;
    }
    case 'schedule':
      clearTimeout(loop.timer);
      loop.timer = setTimeout(() => send(loop, TIMER, ''), number);
      break;
    case 'serve': serve(loop, JSON.parse(readFileSync(args[0], 'utf8')), args[1], number); break;
    case 'broadcast': broadcast(loop, args[0]); break;
    case 'run': runProgram(loop, args[0], args.slice(1)); break;
    default: throw new Error(`unknown compiler command ${command}`);
  }
}

// ---- Serving ----

// Files come from the routes the loop wrote: a path's exact route, then
// each directory whose prefix the path starts with, in order, the first
// that has the file. Nothing is cached. A page that opens the event stream
// gets the latest event first.
function serve(loop, routes, name, port) {
  const server = loop.server = createServer((incoming, response) => {
    const path = decodeURIComponent(new URL(incoming.url, 'http://localhost').pathname);
    if (path === routes.events) return openEvents(loop, response);
    const file = routeFile(routes, path);
    try {
      const bytes = readFileSync(file);
      response.writeHead(200, {'Content-Type': routes.types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'}).end(bytes);
    } catch { response.writeHead(404, {'Cache-Control': 'no-store'}).end(); }
  });
  server.on('error', error => fail(loop, error));
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
  for (const response of loop.clients) writeEvent(response, event);
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
    if (loop.stopping) return;
    const child = spawn(process.env.NODE ?? 'node', ['--no-warnings', join(loop.root, 'host/native/run-snail.mjs'), manifest, ...args], {stdio: 'inherit'});
    child.on('error', error => fail(loop, error));
    child.on('exit', (code, signal) => { if (!signal) console.error(`\x1b[2m-- exited with status ${code}\x1b[0m`); });
    loop.child = child;
  };
  if (!previous || previous.exitCode !== null || previous.signalCode !== null) loop.next();
  else if (!previous.killed) { previous.once('exit', () => loop.next()); previous.kill(); }
}

// ---- Shutdown ----

function fail(loop, error) {
  if (loop.stopping) return;
  console.error(`snail: ${error.message}`);
  void stop(loop, 1);
}

async function stop(loop, status) {
  if (loop.stopping) return;
  loop.stopping = true;
  process.exitCode = status;
  clearTimeout(loop.timer);
  for (const watcher of loop.watchers) watcher.close();
  for (const response of loop.clients) response.end();
  loop.server?.close();
  loop.server?.closeAllConnections();
  await Promise.all([loop.worker.terminate(), stopChild(loop.child)]);
  rmSync(loop.directory, {recursive: true, force: true});
}

function stopChild(child) {
  if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return;
  return new Promise(resolve => {
    const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
    child.once('exit', () => { clearTimeout(timer); resolve(); });
    child.kill();
  });
}

try {
  const [root, ...request] = process.argv.slice(2);
  const parsed = loopRequest(request);
  const loop = startLoop(root, buildTools(root), parsed);
  process.on('SIGINT', () => { void stop(loop, 130); });
  process.on('SIGTERM', () => { void stop(loop, 143); });
} catch (error) {
  console.error(`snail: ${error.message}`);
  process.exitCode = 1;
}
