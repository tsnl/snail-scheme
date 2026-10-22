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
// this script only decides when to build and tells pages what was built.
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {watch} from 'node:fs';
import {readFile, readdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {basename, dirname, extname, join, relative, resolve, sep} from 'node:path';

const usage = 'usage: lofi serve [--port PORT] [--release] APP-DIRECTORY | lofi watch [--release] [-I DIRECTORY] SOURCE [ARGUMENT ...]';

// ---- Requests ----

function parseRequest([root, command, ...rest]) {
  if (!['serve', 'watch'].includes(command)) throw new Error(usage);
  const request = {root, command, port: 8000, release: false, libraries: [], target: null, arguments: []};
  while (rest.length && !request.target) takeWord(request, rest);
  if (!request.target || (command === 'serve' && request.arguments.length)) throw new Error(usage);
  return request;
}

// Takes one option, or the application or program, which ends the options;
// a program's arguments follow it.
function takeWord(request, rest) {
  const word = rest.shift();
  if (word === '--release') request.release = true;
  else if (word === '--port' && request.command === 'serve' && rest.length) request.port = Number(rest.shift());
  else if (word === '-I' && request.command === 'watch' && rest.length) request.libraries.push(resolve(rest.shift()));
  else Object.assign(request, {target: resolve(word), arguments: rest});
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

// A build's manifest: each file it wrote, with a digest of its bytes. A page
// compares the manifest it loaded with the latest one to learn what changed.
async function manifestOf(directory) {
  const manifest = {};
  for (const name of await readdir(directory).catch(() => []))
    manifest[name] = createHash('sha256').update(await readFile(join(directory, name))).digest('hex').slice(0, 16);
  return manifest;
}

function changedFiles(before, after) {
  return Object.keys(after).filter(name => before[name] !== after[name]);
}

// ---- Events ----

// Pages listen at /.lofi/events. Every event names the build's state,
// `building`, `built` or `failed`, and carries the manifest of the build
// being served; a page that connects first receives the latest event. So
// any one event tells a page all it missed, whether it connected late or
// the server restarted.
function createEvents() {
  const listeners = new Set();
  let latest = null;
  const write = (response, event) => response.write(`data: ${JSON.stringify(event)}\n\n`);
  return {
    listen(response) {
      response.writeHead(200, {'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive'});
      response.write('retry: 1000\n\n');
      if (latest) write(response, latest);
      listeners.add(response);
      response.on('close', () => listeners.delete(response));
    },
    send(event) {
      latest = event;
      for (const response of listeners) write(response, event);
    },
  };
}

// ---- Serving ----

const contentTypes = {
  '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css',
  '.wasm': 'application/wasm', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8',
};

// Every page gets the live reload client and the manifest of the build it
// came from. Before the first build succeeds there is no index.html, so a
// placeholder page with an empty manifest waits for one.
const placeholder = '<!doctype html>\n<meta charset="utf-8">\n<title>Building</title>\n<body></body>\n';

function withClient(html, manifest) {
  const tags = `<script type="application/json" id="lofi-manifest">${JSON.stringify(manifest)}</script>`
    + '<script type="module" src="/.lofi/reload.mjs"></script>';
  return html.includes('</body>') ? html.replace('</body>', `${tags}</body>`) : html + tags;
}

// Files come only from `directory`, and nothing is cached, so a page always
// fetches what the latest build wrote.
async function serveFile(response, directory, pathname, manifest) {
  const path = join(directory, pathname === '/' ? 'index.html' : decodeURIComponent(pathname));
  if (relative(directory, path).startsWith('..')) { response.writeHead(403).end(); return; }
  const headers = {'Content-Type': contentTypes[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'};
  const bytes = await readFile(path).catch(() => null);
  if (extname(path) === '.html') response.writeHead(200, headers).end(withClient(bytes?.toString() ?? placeholder, bytes ? manifest : {}));
  else if (bytes) response.writeHead(200, headers).end(bytes);
  else response.writeHead(404, {'Cache-Control': 'no-store'}).end();
}

// Serves an application from build/serve/NAME and builds it again whenever
// its directory, the standard library or the browser host changes. The
// site starts from what an earlier server left there.
async function serve(request) {
  const output = join(request.root, 'build/serve', basename(request.target));
  const site = {events: createEvents(), manifest: await manifestOf(output)};
  const rebuild = serialize(() => buildSite(request, output, site));
  await rebuild();
  listen(request, output, site);
  watchSources(request.root, [request.target, join(request.root, 'lib'), join(request.root, 'src/app')], rebuild);
}

// A failed build leaves the manifest of the last one that succeeded.
async function buildSite(request, output, site) {
  const started = performance.now(), previous = site.manifest;
  site.events.send({state: 'building', manifest: previous});
  const {status, output: printed} = await buildApplication(request, output);
  const milliseconds = Math.round(performance.now() - started);
  if (status !== 0) { console.error(printed.trimEnd()); site.events.send({state: 'failed', manifest: previous, message: printed.trimEnd()}); return; }
  site.manifest = await manifestOf(output);
  const changed = changedFiles(previous, site.manifest);
  console.log(`built ${basename(request.target)} in ${milliseconds} ms${changed.length ? `: ${changed.join(', ')}` : ', unchanged'}`);
  site.events.send({state: 'built', manifest: site.manifest, milliseconds});
}

function listen({root, target, port}, output, site) {
  const server = createServer((incoming, response) => {
    const {pathname} = new URL(incoming.url, 'http://localhost');
    if (pathname === '/.lofi/events') site.events.listen(response);
    else if (pathname === '/.lofi/reload.mjs') serveFile(response, join(root, 'src/app'), '/reload.mjs', {});
    else serveFile(response, output, pathname, site.manifest);
  });
  server.listen(port, '127.0.0.1', () => console.log(`serving ${basename(target)} at http://127.0.0.1:${server.address().port}/`));
}

// ---- Running programs ----

// Builds the program with `lofi compile` and runs it as `lofi run` would.
// When a new build succeeds, a program still running is stopped, and the
// new one starts once it has exited, so a server can bind its port again;
// a failed build leaves it running.
function watchProgram(request) {
  const program = join(request.root, 'build/lofi-watch/program.wasm');
  const running = {child: null};
  const rebuild = serialize(async () => {
    if (await compileProgram(request, program)) await restartProgram(request, program, running);
  });
  rebuild();
  watchSources(request.root, [dirname(request.target), ...request.libraries, join(request.root, 'lib')], rebuild);
}

async function compileProgram({root, release, libraries, target}, program) {
  console.error(`\x1b[2m-- building ${relative(process.cwd(), target)}\x1b[0m`);
  const flags = [...(release ? ['--release'] : []), ...libraries.flatMap(directory => ['-I', directory])];
  const {status, output} = await capture(join(root, 'lofi'), ['compile', ...flags, '-o', program, target]);
  if (status !== 0) process.stderr.write(output);
  return status === 0;
}

// A running program's child is cleared when it exits, so one that is set
// has an exit still to come.
async function restartProgram({root, arguments: args}, program, running) {
  if (running.child) { const exited = once(running.child, 'exit'); running.child.kill(); await exited; }
  running.child = spawn(process.env.NODE ?? 'node', ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), program, ...args],
                        {stdio: 'inherit'});
  running.child.on('exit', (code, signal) => {
    running.child = null;
    if (!signal) console.error(`\x1b[2m-- exited with status ${code}\x1b[0m`);
  });
}

try {
  const request = parseRequest(process.argv.slice(2));
  await (request.command === 'serve' ? serve(request) : watchProgram(request));
} catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
