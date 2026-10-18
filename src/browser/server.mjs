// Shared local development authority: HTTP + event stream, SQLite snapshot,
// serial Scheme transitions, and code replacement at message boundaries.
import {createServer} from 'node:http';
import {readFileSync, existsSync} from 'node:fs';
import {resolve, join, extname} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ReducerRuntime, endpoint, parseCommand} from '../application/runtime.mjs';
import {Authority} from '../application/authority.mjs';
import {openStore} from '../application/sqlite.mjs';

const directory = resolve(process.argv[2] ?? '.'), port = Number(process.env.PORT ?? 4173);
let manifest = JSON.parse(readFileSync(join(directory, 'manifest.json')));
if (manifest.target !== 'cloud') throw new Error('The authority server requires a cloud package');
const runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(readFileSync(join(directory, manifest.module)), manifest));
await runtime.initialize(1); await runtime.initialize(2);
const rejectedGenerations = new Set();
const store = openStore(join(directory, 'match.sqlite')), streams = new Map(), sessions = new Set();
const broadcast = value => { for (const {response} of streams.values()) response.write(`data: ${JSON.stringify(value)}\n\n`); };
const authority = await Authority.open(runtime, {saved: store.load(), commit: (snapshot, expected) => store.commit(snapshot, expected),
  publish: broadcast, resetHandler: endpoint(manifest, 'match', manifest.settings.reset).id, runMarker: manifest.settings.runMarker});
const clockClient = '__clock';
function send(response, status, value) {
  response.writeHead(status, {'content-type': 'application/json', 'cache-control': 'no-store'}); response.end(JSON.stringify(value));
}
async function body(request) {
  let source = ''; for await (const chunk of request) { source += chunk; if (source.length > 8192) throw new Error('request too large'); }
  return source ? JSON.parse(source) : {};
}
function allowed(command) {
  const {handler} = parseCommand(manifest, 'match', command);
  if (!manifest.settings.remoteHandlers.includes(handler.binding)) throw new Error('endpoint is authority-only');
}
async function route(request, response) {
  const url = new URL(request.url, `http://127.0.0.1:${port}`);
  if (request.method === 'POST' && url.pathname === '/session') {
    const input = await body(request);
    // A first command can still be in flight when its tab reloads. Reuse that
    // live session too, so reload cannot turn one purchase into two identities.
    const client = typeof input.client === 'string' && /^[0-9a-f-]{36}$/.test(input.client)
      && (sessions.has(input.client) || Object.hasOwn(authority.clients, input.client)) ? input.client : randomUUID();
    sessions.add(client); send(response, 200, {client, next: (authority.clients[client]?.sequence ?? 0) + 1, ...authority.snapshot()}); return;
  }
  if (url.pathname === '/events') {
    const client = url.searchParams.get('client'); if (!sessions.has(client)) throw new Error('unknown session');
    response.writeHead(200, {'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive'});
    const connection = randomUUID(); streams.set(connection, {response, client, visible: true});
    response.write(`data: ${JSON.stringify({type: 'snapshot', ...authority.snapshot()})}\n\n`);
    request.on('close', () => streams.delete(connection)); return;
  }
  if (request.method === 'POST' && url.pathname === '/presence') {
    const input = await body(request);
    for (const stream of streams.values()) if (stream.client === input.client) stream.visible = input.visible === true;
    send(response, 200, {}); return;
  }
  if (request.method === 'POST' && url.pathname === '/command') {
    const input = await body(request); if (!sessions.has(input.client)) throw new Error('unknown session'); allowed(input.command);
    send(response, 200, await authority.submit(input)); return;
  }
  if (url.pathname === '/manifest.json') { send(response, 200, manifest); return; }
  if (url.pathname === '/snapshot') { send(response, 200, authority.snapshot()); return; }
  const file = resolve(directory, `.${url.pathname === '/' ? '/index.html' : url.pathname}`);
  if (!file.startsWith(`${directory}/`) || ['.sqlite', '.db'].includes(extname(file)) || file.includes('sqlite-') || !existsSync(file)) {
    send(response, 404, {error: 'not found'}); return;
  }
  const type = {'.html': 'text/html', '.css': 'text/css', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.wgsl': 'text/plain'}[extname(file)];
  if (!type) { send(response, 404, {error: 'not found'}); return; }
  response.writeHead(200, {'content-type': type, 'cache-control': 'no-store'}); response.end(readFileSync(file));
}
function recoverCode() {
  if (manifest.generation === runtime.manifest.generation) return;
  rejectedGenerations.add(manifest.generation); manifest = runtime.manifest;
  authority.resetHandler = endpoint(manifest, 'match', manifest.settings.reset).id;
  broadcast({type: 'reload', generation: manifest.generation});
}
const server = createServer((request, response) => {
  route(request, response).catch(error => {
    recoverCode(); send(response, 400, {error: error.message, ...authority.snapshot()});
  });
});
let stopping = false, ticking, reloading;
async function tick() {
  try {
    if ([...streams.values()].some(stream => stream.visible))
      await authority.submit({client: clockClient, command: runtime.command('match', manifest.settings.tick)}, {internal: true});
  } catch (error) { recoverCode(); broadcast({type: 'error', error: error.message}); }
  finally { if (!stopping) ticking = setTimeout(tick, manifest.settings.tickMilliseconds); }
}
async function reload() {
  try {
    const next = JSON.parse(readFileSync(join(directory, 'manifest.json')));
    if (next.generation === manifest.generation || rejectedGenerations.has(next.generation)) return;
    if (next.target !== 'cloud' || next.settings.id !== manifest.settings.id) throw new Error('incompatible application package');
    if (next.settings.runMarker !== manifest.settings.runMarker) throw new Error('incompatible run marker offset');
    const candidate = runtime.prepare(readFileSync(join(directory, next.module)), next);
    try { await runtime.replace(candidate); }
    catch (error) { runtime.discard(candidate); throw error; }
    manifest = next; authority.resetHandler = endpoint(manifest, 'match', manifest.settings.reset).id;
    broadcast({type: 'reload', generation: manifest.generation});
  } catch (error) { broadcast({type: 'reload-error', error: error.message}); }
  finally { if (!stopping) reloading = setTimeout(reload, 1000); }
}
ticking = setTimeout(tick, manifest.settings.tickMilliseconds);
reloading = setTimeout(reload, 1000);
server.listen(port, '127.0.0.1', () => console.log(`${manifest.settings.title}: http://127.0.0.1:${port} (single authority, SQLite, two-client ready)`));
async function close() {
  if (stopping) return;
  stopping = true; clearTimeout(ticking); clearTimeout(reloading);
  for (const stream of streams.values()) stream.response.end();
  streams.clear(); server.close();
  await runtime.close(); // Drain admitted saves before closing their durable adapter.
  store.close();
}
process.once('SIGTERM', () => void close()); process.once('SIGINT', () => void close());
