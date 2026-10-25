// The local IDE boundary: concrete HTTP requests to the existing project and
// file owners. It owns connections, not source contents or compiler state.
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {basename, join, sep} from 'node:path';
import {developProject} from './project-develop.mjs';
import {FileConflict, ProjectFileError, projectFiles} from './project-files.mjs';

const bodyLimit = 8 * 1024 * 1024;
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const headers = {'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY'};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function json(response, status, value) {
  response.writeHead(status, {...headers, 'Content-Type': 'application/json'});
  response.end(JSON.stringify(value));
}

function authorize(request, origin, navigation = false) {
  if (request.headers.host !== new URL(origin).host) throw new HttpError(403, 'unexpected host');
  if (request.headers.origin !== undefined && request.headers.origin !== origin) throw new HttpError(403, 'unexpected origin');
  const site = request.headers['sec-fetch-site'];
  if (!navigation && site && site !== 'same-origin' && site !== 'none') throw new HttpError(403, 'unexpected fetch context');
  if (request.method !== 'GET' && request.headers.origin !== origin) throw new HttpError(403, 'mutation requires the project origin');
}

function expectedRevision(request) {
  // One strong opaque tag. Lists, wildcards and weak matching are not this API.
  const match = /^"([\x21\x23-\x5b\x5d-\x7e]+)"$/.exec(request.headers['if-match'] ?? '');
  if (!match) throw new HttpError(400, 'save requires one quoted If-Match revision');
  return match[1];
}

function emptyBody(request) {
  if (Number(request.headers['content-length']) || request.headers['transfer-encoding']) throw new HttpError(400, 'command takes no request body');
}

async function readText(request) {
  if (!/^text\/plain(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? '')) throw new HttpError(415, 'save requires UTF-8 text/plain');
  if (Number(request.headers['content-length']) > bodyLimit) throw new HttpError(413, 'request exceeds 8 MiB');
  const chunks = []; let length = 0;
  for await (const chunk of request.iterator({destroyOnReturn: false})) {
    length += chunk.length;
    if (length > bodyLimit) throw new HttpError(413, 'request exceeds 8 MiB');
    chunks.push(chunk);
  }
  try { return decoder.decode(Buffer.concat(chunks, length)); }
  catch { throw new HttpError(400, 'save requires valid UTF-8'); }
}

function errorStatus(error) {
  if (error instanceof HttpError) return error.status;
  if (error instanceof FileConflict) return 409;
  if (error instanceof ProjectFileError) return 400;
  if (error.code === 'ENOENT') return 404;
  if (['EACCES', 'EPERM', 'ELOOP'].includes(error.code)) return 403;
  return 500;
}

const frame = (kind, value) => `event: ${kind}\ndata: ${JSON.stringify(value)}\n\n`;
const editorStatus = ({phase, id, diagnostics}) => ({phase, id, diagnostics});

// Only trusted editor assets share the file API's origin. Project HTML and
// arbitrary paths are never served here; application serving is separate.
function editorAssets(root, tools) {
  const assets = new Map([
    ['/', [join(root, 'src/ide/index.html'), 'text/html']],
    ['/format.wasm', [tools.formatter, 'application/wasm']],
    ['/load.mjs', [join(root, 'src/app/load.mjs'), 'text/javascript']],
    ['/ide.css', [join(root, 'src/ide/ide.css'), 'text/css']],
  ]);
  for (const name of ['ide', 'editor', 'panes', 'formatter']) assets.set(`/${name}.mjs`, [join(root, `src/ide/${name}.mjs`), 'text/javascript']);
  return assets;
}

export async function serveProject({root, project, tools, port = 0}) {
  const files = projectFiles(project), development = developProject({root, project: files.project, tools});
  const assets = editorAssets(root, tools);
  const clients = new Set(), closed = Promise.withResolvers();
  closed.promise.catch(() => {}); // Callers may inspect it later or call close().
  let stopping = false, failure = null, compilerEvent = null, runsEvent = null;
  const server = createServer({requestTimeout: 15_000, headersTimeout: 15_000}, (request, response) => {
    void route(request, response).catch(error => {
      request.resume();
      if (response.destroyed) return;
      if (response.headersSent) response.destroy();
      else { response.setHeader('Connection', 'close'); json(response, errorStatus(error), {message: error.message}); }
    });
  });
  server.maxConnections = 128;
  const origin = () => `http://127.0.0.1:${server.address().port}`;

  // One pending response write, no application queue. A large initial status
  // may legitimately need drain; a later event closes a still-blocked
  // stream. Reconnect obtains current status and an unconditional invalidation.
  function send(response, text) {
    if (response.writableNeedDrain) { response.destroy(); return; }
    try { response.write(text); }
    catch { response.destroy(); }
  }

  function broadcast(text) {
    for (const response of clients) send(response, text);
  }

  function events(response) {
    if (clients.size >= 64) throw new HttpError(429, 'too many event connections');
    clients.add(response);
    response.on('close', () => clients.delete(response));
    response.on('error', () => response.destroy());
    response.writeHead(200, {...headers, 'Content-Type': 'text/event-stream', Connection: 'keep-alive'});
    const status = development.status;
    send(response, 'retry: 1000\n\n' + frame('status', editorStatus(status)) + frame('runs', status.runs) + frame('files', null));
  }

  async function route(request, response) {
    if (stopping) throw new HttpError(503, 'project development is closing');
    const base = origin();
    const url = new URL(request.url, base), path = url.searchParams.get('path');
    if (url.origin !== base) throw new HttpError(403, 'unexpected request origin');
    const navigation = request.method === 'GET' && url.pathname === '/' && request.headers['sec-fetch-mode'] === 'navigate' && request.headers['sec-fetch-dest'] === 'document';
    authorize(request, base, navigation);
    if (request.method === 'GET' && assets.has(url.pathname)) return serveAsset(response, assets.get(url.pathname));
    switch (`${request.method} ${url.pathname}`) {
      case 'GET /api/project': return json(response, 200, {name: basename(files.project), directory: files.project, files: files.list()});
      case 'GET /api/file': return json(response, 200, files.read(path));
      case 'GET /api/events': return events(response);
      case 'POST /api/build':
        emptyBody(request);
        development.requestBuild();
        return json(response, 202, editorStatus(development.status));
      case 'POST /api/run/start':
      case 'POST /api/run/stop':
      case 'POST /api/run/restart': {
        emptyBody(request);
        const action = url.pathname.split('/').at(-1);
        const run = development.status.runs.find(run => run.target === url.searchParams.get('target'));
        if (!run || (action !== 'stop' && !run.available)) throw new HttpError(404, 'unknown accepted run target');
        const controls = {start: development.startRun, stop: development.stopRun, restart: development.restartRun};
        controls[action](run.target);
        response.writeHead(204, headers);
        return response.end(); // Acknowledge the command; SSE owns observed run state.
      }
      case 'PUT /api/file': {
        const revision = expectedRevision(request), text = await readText(request);
        if (stopping) throw new HttpError(503, 'project development is closing');
        return json(response, 200, files.save(path, revision, text)); // Only disk writes; no Build call.
      }
      default: throw new HttpError(404, 'unknown project endpoint');
    }
  }

  async function serveAsset(response, [path, type]) {
    if (!path) throw new HttpError(404, 'editor formatter is unavailable');
    const bytes = await readFile(path);
    if (stopping || response.destroyed) return;
    response.writeHead(200, {...headers, 'Content-Type': type,
      'Content-Security-Policy': "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; worker-src 'none'"});
    response.end(bytes);
  }

  const stopStatus = development.subscribe(status => {
    // Compiler evidence is independent of process output. Repeating a compiler
    // status for each log chunk would cause needless editor reads and redraws.
    const compiler = frame('status', editorStatus(status)), runs = frame('runs', status.runs);
    const changed = (compiler === compilerEvent ? '' : compiler) + (runs === runsEvent ? '' : runs);
    compilerEvent = compiler; runsEvent = runs;
    if (changed) broadcast(changed); // One observation gets one opportunity to drain.
    if (status.phase === 'fatal') fail(new Error(status.diagnostics[0].message));
  });
  const stopFiles = development.files.subscribe(event => {
    if (event.kind === 'changed' && event.paths.some(path => path === files.project || path.startsWith(files.project + sep))) broadcast(frame('files', null));
  });

  function fail(error) {
    failure ??= error;
    void close().catch(() => {});
  }

  // File saves are synchronous after request decoding: close cannot interleave
  // them, and a body completing afterward sees stopping before it can mutate.
  function close() {
    if (stopping) return closed.promise;
    stopping = true;
    stopStatus(); stopFiles();
    const http = server.listening ? new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())) : Promise.resolve();
    for (const response of clients) response.destroy();
    server.closeAllConnections();
    void Promise.allSettled([http, development.close()]).then(results => {
      failure ??= results.find(result => result.status === 'rejected')?.reason;
      if (failure) closed.reject(failure); else closed.resolve();
    });
    return closed.promise;
  }

  server.on('error', fail);
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); });
    });
    if (stopping) { await closed.promise; throw new Error('project development closed during startup'); }
    return {url: origin(), development, closed: closed.promise, close};
  } catch (error) { try { await close(); } catch {} throw error; }
}
