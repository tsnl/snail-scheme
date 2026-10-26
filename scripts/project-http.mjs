// The local IDE boundary: concrete HTTP requests to the existing project and
// file owners. It owns connections, not source contents or compiler state.
import {createServer} from 'node:http';
import {basename, sep} from 'node:path';
import {developProject} from './project-develop.mjs';
import {FileConflict, ProjectFileError, projectFiles} from './project-files.mjs';

const bodyLimit = 8 * 1024 * 1024;
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const headers = {'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function json(response, status, value) {
  response.writeHead(status, {...headers, 'Content-Type': 'application/json'});
  response.end(JSON.stringify(value));
}

function authorize(request, origin) {
  if (request.headers.host !== new URL(origin).host) throw new HttpError(403, 'unexpected host');
  if (request.headers.origin !== undefined && request.headers.origin !== origin) throw new HttpError(403, 'unexpected origin');
  const site = request.headers['sec-fetch-site'];
  if (site && site !== 'same-origin' && site !== 'none') throw new HttpError(403, 'unexpected fetch context');
  if (request.method !== 'GET' && request.headers.origin !== origin) throw new HttpError(403, 'mutation requires the project origin');
}

function expectedRevision(request) {
  // One strong opaque tag. Lists, wildcards and weak matching are not this API.
  const match = /^"([\x21\x23-\x5b\x5d-\x7e]+)"$/.exec(request.headers['if-match'] ?? '');
  if (!match) throw new HttpError(400, 'save requires one quoted If-Match revision');
  return match[1];
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

export async function serveProject({root, project, tools, port = 0}) {
  const files = projectFiles(project), development = developProject({root, project: files.project, tools});
  const clients = new Set(), closed = Promise.withResolvers();
  closed.promise.catch(() => {}); // Callers may inspect it later or call close().
  let stopping = false, failure = null;
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
  // may legitimately need drain; a later event or a deadline closes a blocked
  // stream. Reconnect obtains current status and an unconditional invalidation.
  function send(client, text) {
    if (client.timer) { client.response.destroy(); return; }
    try {
      if (client.response.write(text)) return;
      client.timer = setTimeout(() => client.response.destroy(), 5000);
      client.response.once('drain', () => { clearTimeout(client.timer); client.timer = null; });
    } catch { client.response.destroy(); }
  }

  function broadcast(kind, value) {
    const text = frame(kind, value);
    for (const client of clients) send(client, text);
  }

  function events(response) {
    if (clients.size >= 64) throw new HttpError(429, 'too many event connections');
    const client = {response, timer: null};
    clients.add(client);
    response.on('close', () => { clearTimeout(client.timer); clients.delete(client); });
    response.on('error', () => response.destroy());
    response.writeHead(200, {...headers, 'Content-Type': 'text/event-stream', Connection: 'keep-alive'});
    send(client, 'retry: 1000\n\n' + frame('status', development.status) + frame('files', null));
  }

  async function route(request, response) {
    if (stopping) throw new HttpError(503, 'project development is closing');
    const base = origin();
    authorize(request, base);
    const url = new URL(request.url, base), path = url.searchParams.get('path');
    if (url.origin !== base) throw new HttpError(403, 'unexpected request origin');
    switch (`${request.method} ${url.pathname}`) {
      case 'GET /api/project': return json(response, 200, {name: basename(files.project), files: files.list()});
      case 'GET /api/file': return json(response, 200, files.read(path));
      case 'GET /api/events': return events(response);
      case 'POST /api/build':
        if (Number(request.headers['content-length']) || request.headers['transfer-encoding']) throw new HttpError(400, 'build takes no request body');
        development.requestBuild();
        return json(response, 202, development.status);
      case 'PUT /api/file': {
        const revision = expectedRevision(request), text = await readText(request);
        if (stopping) throw new HttpError(503, 'project development is closing');
        return json(response, 200, files.save(path, revision, text)); // Only disk writes; no Build call.
      }
      default: throw new HttpError(404, 'unknown project endpoint');
    }
  }

  const stopStatus = development.subscribe(status => {
    broadcast('status', status);
    if (status.phase === 'fatal') fail(new Error(status.diagnostics[0].message));
  });
  const stopFiles = development.files.subscribe(event => {
    if (event.kind === 'changed' && event.paths.some(path => path === files.project || path.startsWith(files.project + sep))) broadcast('files', null);
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
    for (const client of clients) client.response.destroy();
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
