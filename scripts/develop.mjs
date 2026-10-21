#!/usr/bin/env node
// The development loop. `serve` builds a (lofi app) application, serves it
// and builds it again whenever its sources change; each page it serves swaps
// in the new module without losing its state (src/app/reload.mjs). `watch`
// builds a program whenever its sources change and runs it again.
//
//   develop.mjs ROOT serve [--port PORT] [--release] APP-DIRECTORY
//   develop.mjs ROOT watch [--release] [-I DIRECTORY] SOURCE [ARGUMENT ...]
//
// Building stays with the driver that `make site` and `lofi compile` use;
// this script only decides when to build and tells pages what changed.
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {watch} from 'node:fs';
import {readFile, readdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {basename, dirname, extname, join, relative, resolve, sep} from 'node:path';

const usage = 'usage: lofi serve [--port PORT] [--release] APP-DIRECTORY | lofi watch [--release] [-I DIRECTORY] SOURCE [ARGUMENT ...]';

// ---- Requests ----

// The options before the first other argument, which names the application
// or the program; a program's arguments follow it.
function parseRequest([root, command, ...rest]) {
  if (!['serve', 'watch'].includes(command)) throw new Error(usage);
  const request = {root, command, port: 8000, release: false, libraries: [], target: null, arguments: []};
  while (rest.length) {
    const word = rest.shift();
    if (word === '--release') request.release = true;
    else if (word === '--port' && command === 'serve' && rest.length) request.port = Number(rest.shift());
    else if (word === '-I' && command === 'watch' && rest.length) request.libraries.push(resolve(rest.shift()));
    else { request.target = resolve(word); request.arguments = rest; break; }
  }
  if (!request.target || (command === 'serve' && request.arguments.length)) throw new Error(usage);
  return request;
}

// ---- Watching sources ----

// Editors save in steps, through temporary files, renames and backups, so a
// build starts once changes have been quiet for 100 milliseconds. Their
// temporary files never start one, and neither does anything under build/,
// where the builds write.
function ignored(root, path) {
  const name = basename(path);
  return path.startsWith(join(root, 'build') + sep) || path.split(sep).includes('.git')
    || name.startsWith('.') || name.startsWith('#') || name.endsWith('~') || /^\d+$/.test(name);
}

function watchSources(root, directories, changed) {
  let timer = null;
  for (const directory of directories)
    watch(directory, {recursive: true}, (event, name) => {
      if (!name || ignored(root, join(directory, name))) return;
      clearTimeout(timer);
      timer = setTimeout(changed, 100);
    });
}

// ---- Building ----

// Runs a command to completion, resolving to its status and everything it
// printed.
function capture(command, args) {
  return new Promise(done => {
    const child = spawn(command, args, {stdio: ['ignore', 'pipe', 'pipe']});
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; });
    child.stderr.on('data', chunk => { output += chunk; });
    child.on('error', error => done({status: 1, output: error.message}));
    child.on('close', status => done({status, output}));
  });
}

// One build at a time: changes during a build queue one more build after it.
function serialize(build) {
  let running = null, again = false;
  return function rebuild() {
    if (running) { again = true; return running; }
    running = (async () => {
      do { again = false; await build(); } while (again);
      running = null;
    })();
    return running;
  };
}

// The driver that `make site` runs: Chibi with the compiler's host
// libraries, running scripts/build-app.scm.
function buildApplication({root, release, target}, output) {
  const chibi = process.env.CHIBI ?? 'chibi-scheme';
  return capture(chibi, ['-h', process.env.LOFI_HEAP ?? '2G', '-I', join(root, 'host/chibi'), '-I', join(root, 'src'),
                         join(root, 'scripts/build-app.scm'), root, ...(release ? ['--release'] : []), target, output]);
}

// A digest of each file a build wrote, so a page learns which ones changed.
async function fingerprints(directory) {
  const digests = new Map();
  for (const name of await readdir(directory).catch(() => []))
    digests.set(name, createHash('sha256').update(await readFile(join(directory, name))).digest('hex'));
  return digests;
}

function changedFiles(before, after) {
  return [...after.keys()].filter(name => before.get(name) !== after.get(name));
}

// ---- Events ----

// Pages listen at /.lofi/events. A page that connects first learns the
// outcome of the latest build, so it can show a failure it did not see
// happen.
function createEvents() {
  const listeners = new Set();
  let status = {state: 'building', build: 0};
  const write = (response, kind, data) => response.write(`event: ${kind}\ndata: ${JSON.stringify(data)}\n\n`);
  return {
    listen(response) {
      response.writeHead(200, {'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive'});
      response.write('retry: 1000\n\n');
      write(response, 'status', status);
      listeners.add(response);
      response.on('close', () => listeners.delete(response));
    },
    send(kind, data) {
      if (kind !== 'building') status = {state: kind, ...data};
      for (const response of listeners) write(response, kind, data);
    },
  };
}

// ---- Serving ----

const contentTypes = {
  '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css',
  '.wasm': 'application/wasm', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8',
};

// Every page gets the live reload client. Before the first build succeeds
// there is no index.html, so a placeholder page waits for it.
const client = '<script type="module" src="/.lofi/reload.mjs"></script>';
const placeholder = `<!doctype html>\n<meta charset="utf-8">\n<title>Building</title>\n<body>${client}</body>\n`;

function withClient(html) {
  return html.includes('</body>') ? html.replace('</body>', `${client}</body>`) : html + client;
}

// Files come only from the build's output, and nothing is cached, so a page
// always fetches what the latest build wrote.
async function serveFile(response, output, pathname) {
  const path = join(output, pathname === '/' ? 'index.html' : decodeURIComponent(pathname));
  const headers = {'Content-Type': contentTypes[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'};
  if (relative(output, path).startsWith('..')) { response.writeHead(403).end(); return; }
  try {
    const bytes = await readFile(path);
    response.writeHead(200, headers).end(extname(path) === '.html' ? withClient(bytes.toString()) : bytes);
  } catch {
    if (extname(path) === '.html') response.writeHead(200, headers).end(placeholder);
    else response.writeHead(404, {'Cache-Control': 'no-store'}).end();
  }
}

// Serves an application from build/serve/NAME and builds it again whenever
// its directory, the standard library or the browser host changes.
async function serve(request) {
  const {root, target, port} = request;
  const output = join(root, 'build/serve', basename(target));
  const events = createEvents();
  let built = 0;
  const rebuild = serialize(async () => {
    const before = await fingerprints(output), started = performance.now(), build = ++built;
    events.send('building', {build});
    const {status, output: printed} = await buildApplication(request, output);
    const milliseconds = Math.round(performance.now() - started);
    if (status !== 0) { console.error(printed.trimEnd()); events.send('failed', {build, message: printed.trimEnd()}); return; }
    const changed = changedFiles(before, await fingerprints(output));
    console.log(`built ${basename(target)} in ${milliseconds} ms${changed.length ? `: ${changed.join(', ')}` : ', unchanged'}`);
    events.send('built', {build, changed, milliseconds});
  });
  const server = createServer((incoming, response) => {
    const {pathname} = new URL(incoming.url, 'http://localhost');
    if (pathname === '/.lofi/events') events.listen(response);
    else if (pathname === '/.lofi/reload.mjs') serveFile(response, join(root, 'src/app'), '/reload.mjs');
    else serveFile(response, output, pathname);
  });
  await rebuild();
  server.listen(port, '127.0.0.1', () => console.log(`serving ${basename(target)} at http://127.0.0.1:${server.address().port}/`));
  watchSources(root, [target, join(root, 'lib'), join(root, 'src/app')], rebuild);
}

// ---- Running programs ----

// Builds the program with `lofi compile` and runs it as `lofi run` would.
// A program still running when a new build succeeds is stopped first, so
// a server comes back with the new code; a failed build leaves it running.
function watchProgram(request) {
  const {root, release, libraries, target} = request;
  const program = join(root, 'build/lofi-watch/program.wasm');
  const flags = [...(release ? ['--release'] : []), ...libraries.flatMap(directory => ['-I', directory])];
  let child = null;
  const rebuild = serialize(async () => {
    console.error(`\x1b[2m-- building ${relative(process.cwd(), target)}\x1b[0m`);
    const {status, output} = await capture(join(root, 'lofi'), ['compile', ...flags, '-o', program, target]);
    if (status !== 0) { process.stderr.write(output); return; }
    child?.kill();
    child = spawn(process.env.NODE ?? 'node', ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), program, ...request.arguments],
                  {stdio: 'inherit'});
    child.on('exit', (code, signal) => { if (!signal) console.error(`\x1b[2m-- exited with status ${code}\x1b[0m`); });
  });
  rebuild();
  watchSources(root, [dirname(target), ...libraries, join(root, 'lib')], rebuild);
}

try {
  const request = parseRequest(process.argv.slice(2));
  await (request.command === 'serve' ? serve(request) : watchProgram(request));
} catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
