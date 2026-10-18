// HTTP save/load of opaque application checkpoints. Storage revisions describe
// replacements, independently of a game's own revision or state representation.
import {DatabaseSync} from 'node:sqlite';
import {randomUUID} from 'node:crypto';

export function openSaveStore(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS saves (application TEXT PRIMARY KEY, etag TEXT NOT NULL, record TEXT NOT NULL)');
  const read = db.prepare('SELECT etag, record FROM saves WHERE application=?');
  const insert = db.prepare('INSERT OR IGNORE INTO saves VALUES (?, ?, ?)');
  const update = db.prepare('UPDATE saves SET etag=?, record=? WHERE application=? AND etag=?');
  return {
    load: application => read.get(application),
    put(application, expected, record) {
      const etag = `"${randomUUID()}"`;
      if (expected === '*') {
        if (insert.run(application, etag, record).changes !== 1) return undefined;
      } else if (update.run(etag, record, application, expected).changes !== 1) return undefined;
      return etag;
    },
    close: () => db.close(),
  };
}

async function readCheckpoint(request) {
  const reader = request.body?.getReader(); if (!reader) throw new Error('Expected a checkpoint');
  const chunks = []; let length = 0;
  try {
    for (;;) {
      const {value, done} = await reader.read(); if (done) break;
      if ((length += value.byteLength) > 1048576) throw Object.assign(new Error('Checkpoint too large'), {status: 413});
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
}
function checkpointEnvelope(record, application) {
  if (record?.format !== 1 || record.application !== application || typeof record.contract !== 'string'
      || !record.snapshot || !Number.isSafeInteger(record.snapshot.revision) || record.snapshot.revision < 0)
    throw new Error('Invalid checkpoint envelope');
  return JSON.stringify(record);
}
async function replaceCheckpoint(request, store, application, headers) {
  try {
    const match = request.headers.get('if-match');
    if (match === '*' || (match && request.headers.has('if-none-match'))) return new Response(null, {status: 400, headers});
    const expected = match ?? (request.headers.get('if-none-match') === '*' ? '*' : undefined);
    if (!expected) return new Response(null, {status: 428, headers});
    const record = checkpointEnvelope(await readCheckpoint(request), application), etag = store.put(application, expected, record);
    return new Response(null, {status: etag ? 204 : 412, headers: {...headers, ...(etag ? {etag} : {})}});
  } catch (error) { return new Response(JSON.stringify({error: error.message}), {status: error.status ?? 400, headers}); }
}

export function saveService(store, {origin} = {}) {
  return async function respondHttp(request) {
    const clientOrigin = request.headers.get('origin');
    if (clientOrigin && clientOrigin !== origin) return new Response('Origin not allowed', {status: 403});
    const headers = {'cache-control': 'no-store', 'content-type': 'application/json',
      ...(clientOrigin ? {'access-control-allow-origin': clientOrigin, 'vary': 'Origin',
        'access-control-expose-headers': 'ETag'} : {})};
    const application = new URL(request.url).pathname.match(/^\/saves\/([a-z][a-z0-9.-]{0,79})$/)?.[1];
    if (!application) return new Response(null, {status: 404, headers});
    if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: {...headers,
      'access-control-allow-methods': 'GET, PUT', 'access-control-allow-headers': 'Content-Type, If-Match, If-None-Match'}});
    if (request.method === 'GET') {
      const saved = store.load(application);
      return new Response(saved?.record, {status: saved ? 200 : 404, headers: {...headers, ...(saved ? {etag: saved.etag} : {})}});
    }
    if (request.method !== 'PUT') return new Response(null, {status: 405, headers: {...headers, allow: 'GET, PUT, OPTIONS'}});
    return replaceCheckpoint(request, store, application, headers);
  };
}
