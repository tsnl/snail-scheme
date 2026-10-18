// Actual HTTP contracts against the opaque SQLite checkpoint store.
import assert from 'node:assert/strict';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openSaveStore, saveService, maximumCheckpointBytes} from '../../src/save/service.mjs';

const path = join(mkdtempSync(join(tmpdir(), 'snail-saves-')), 'saves.sqlite');
let store = openSaveStore(path), respond = saveService(store, {origin: 'https://game.example'});
const record = {format: 1, application: 'siegework', contract: 'opaque contract', snapshot: {revision: 9, state: ['opaque', '雪']}};
const request = (method, headers = {}, value) => respond(new Request('http://localhost/saves/siegework',
  {method, headers, ...(value === undefined ? {} : {body: typeof value === 'string' ? value : JSON.stringify(value)})}));
try {
  assert.equal((await request('GET')).status, 404);
  assert.equal((await request('PUT', {}, record)).status, 428);
  const first = await request('PUT', {'if-none-match': '*'}, record); assert.equal(first.status, 204);
  const etag = first.headers.get('etag'); assert.ok(etag);
  assert.equal((await request('PUT', {'if-none-match': '*'}, record)).status, 412);
  const read = await request('GET'); assert.deepEqual(await read.json(), record); assert.equal(read.headers.get('etag'), etag);
  const candidates = await Promise.all([1, 2].map(revision => request('PUT', {'if-match': etag},
    {...record, snapshot: {...record.snapshot, revision}})));
  assert.deepEqual(candidates.map(result => result.status).sort(), [204, 412]);
  const committed = await (await request('GET')).json();
  store.close(); store = openSaveStore(path); respond = saveService(store, {origin: 'https://game.example'});
  assert.deepEqual(await (await request('GET')).json(), committed);
  console.log('ok - opaque checkpoints survive SQLite restart; conditional writes reject duplicate and competing replacements');
  assert.equal((await request('GET', {origin: 'https://other.example'})).status, 403);
  const cors = await request('OPTIONS', {origin: 'https://game.example'});
  assert.equal(cors.status, 204); assert.equal(cors.headers.get('access-control-allow-origin'), 'https://game.example');
  assert.match(cors.headers.get('access-control-allow-headers'), /If-Match/);
  assert.equal((await request('POST')).status, 405);
  assert.equal((await request('PUT', {'if-match': etag}, {...record, application: 'other'})).status, 400);
  assert.equal((await request('PUT', {'if-match': etag}, 'x'.repeat(maximumCheckpointBytes + 1))).status, 413);
  assert.deepEqual(await (await request('GET')).json(), committed);
  console.log('ok - origin policy, methods, checkpoint envelope and size limits preserve the last save');
} finally { store.close(); }
