// Exercise the browser resource service with two small published files. Hold part
// of a response to observe progress, fail the next request, then retry and reload.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';
import {blobPartSize, partPath} from '../../host/browser/load.mjs';

const [root] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'tests/apps/static-resources/main.scm'], {cwd: root});
const directory = stdout.trim();
const catalog = JSON.parse(await readFile(join(directory, 'resources.json'), 'utf8'));
const object = ({sha256}) => 'store/sha256/' + sha256.slice(0, 2) + '/' + sha256;
const first = object(catalog['a.txt']), second = object(catalog['b.txt']);
const requests = [];
const held = Promise.withResolvers();
const lastPart = Promise.withResolvers();
const large = Buffer.alloc(blobPartSize + 3, 23);
large.set([10, 11, 12], blobPartSize);
const sha = createHash('sha256').update(large).digest('hex');
const largeCatalog = {sha256: sha, size: large.length};
let transfer;
const server = await serve(directory, async (path, response) => {
  if (path === '') {
    response.writeHead(200, {'content-type': 'text/html'}).end(`<!doctype html><body>
      <script type="module">
        import {startInterface} from './ui.mjs';
        startInterface({url: './main.wasm', container: document.body, storageKey: 'static-resources'});
      </script>`);
    return true;
  }
  if (path.startsWith('store/')) requests.push(path);
  if (transfer && path === 'resources.json') {
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({'big.bin': largeCatalog, 'alias.bin': largeCatalog}));
    return true;
  }
  if (transfer && path === partPath(sha, 0)) {
    response.end(large.subarray(0, blobPartSize));
    return true;
  }
  if (transfer && path === partPath(sha, 1)) {
    if (transfer === 'missing') response.writeHead(404).end();
    else if (transfer === 'short') response.end(large.subarray(blobPartSize + 1));
    else if (transfer === 'corrupt') response.end(Buffer.alloc(3));
    else { await lastPart.promise; response.end(large.subarray(blobPartSize)); }
    return true;
  }
  if (path === first && requests.length === 1) {
    const bytes = await readFile(join(directory, path));
    response.writeHead(200, {'content-type': 'application/octet-stream', 'x-content-type-options': 'nosniff'});
    response.write(bytes.subarray(0, 2));
    await held.promise;
    response.end(bytes.subarray(2));
    return true;
  }
  if (path === second && requests.length === 2) {
    response.writeHead(503).end();
    return true;
  }
  return false;
});

const url = 'http://127.0.0.1:' + server.address().port + '/';
const browser = await openBrowser();
const progress = () => browser.evaluate('document.body?.dataset.progress');
const result = () => browser.evaluate('document.body?.dataset.result');
try {
  await browser.navigate(url);
  await until(async () => await progress() === '2/0/8', 'partial download without Content-Length');
  held.resolve();
  const error = await until(result, 'failure of the second object');
  assert.match(error, /b\.txt.*503/);

  await browser.navigate(url);
  await until(async () => await result() === '2', 'retry');
  assert.equal(await progress(), '4/4/8');
  assert.deepEqual(requests, [first, second, second]);
  await browser.send('Network.enable');
  await browser.send('Network.setBlockedURLs', {urls: ['*/store/sha256/*']});
  await browser.navigate(url);
  await until(async () => await progress() === '0/8/8' && await result() === '2', 'fully cached reload');
  assert.deepEqual(requests, [first, second, second]);

  // Keep the finished IndexedDB objects alive. Autosave must release its
  // handlers as soon as the transaction completes, independently of GC.
  assert.equal(await browser.evaluate(`(async () => {
    const {storeSave} = await import('./storage.mjs');
    const open = IDBFactory.prototype.open, transaction = IDBDatabase.prototype.transaction;
    let request, tx;
    try {
      IDBFactory.prototype.open = function(...args) { return request = open.apply(this, args); };
      IDBDatabase.prototype.transaction = function(...args) { return tx = transaction.apply(this, args); };
      await storeSave('handler-lifetime-test', new Uint8Array([1]));
      return [request.onsuccess, request.onerror, request.onupgradeneeded, tx.oncomplete, tx.onabort].every(fn => fn === null);
    } finally {
      IDBFactory.prototype.open = open;
      IDBDatabase.prototype.transaction = transaction;
    }
  })()`), true);

  const cache = await browser.evaluate(`(async () => {
    const {readLinkedFile, readImmutable} = await import('./storage.mjs');
    const hash = async b => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b)), n => n.toString(16).padStart(2, '0')).join('');
    const a = Uint8Array.of(13, 42), b = Uint8Array.of(14, 42);
    const first = await hash(a), second = await hash(b);
    let calls = 0, rejected = false;
    try { await readLinkedFile(first, async () => b); } catch { rejected = true; }
    const get = () => readLinkedFile(first, async () => { calls++; return a; });
    await Promise.all([get(), get()]); await get();
    const changed = await readLinkedFile(second, async () => b);
    const store = await caches.open('snail-static-resources-v1');
    await store.put('/.snail/sha256/' + first, new Response(b));
    let repairs = 0;
    const repaired = await readImmutable(first, a.length, async () => { repairs++; return a; });
    const c = Uint8Array.of(15, 42), third = await hash(c), put = Cache.prototype.put;
    let uncached;
    try {
      Cache.prototype.put = () => Promise.reject(new DOMException('full', 'QuotaExceededError'));
      uncached = await readImmutable(third, c.length, async () => c);
    } finally { Cache.prototype.put = put; }
    return [rejected, calls, changed[0], repairs, repaired[0], uncached[0], !!await store.match('/.snail/sha256/' + third)];
  })()`);
  assert.deepEqual(cache, [true, 1, 14, 1, 13, 15, false]);
  await browser.send('Network.setBlockedURLs', {urls: []});
  for (const [mode, failure] of [['missing', /404/], ['short', /expected 3 bytes/], ['corrupt', /SHA-256/]]) {
    transfer = mode;
    requests.length = 0;
    await browser.navigate(url);
    assert.match(await until(result, mode + ' second part'), failure);
    assert.deepEqual(requests, [partPath(sha, 0), partPath(sha, 1)]);
  }
  transfer = 'good';
  requests.length = 0;
  await browser.navigate(url);
  await until(async () => await progress() === blobPartSize + '/0/' + large.length, 'progress at the part boundary');
  lastPart.resolve();
  await until(async () => await result() === '2', 'both names acquired');
  assert.equal(await progress(), large.length + '/0/' + large.length);
  assert.deepEqual(requests, [partPath(sha, 0), partPath(sha, 1)]);
  await browser.send('Network.setBlockedURLs', {urls: ['*/store/*']});
  await browser.navigate(url);
  await until(async () => await result() === '2', 'offline multipart cache');
  assert.equal(await progress(), '0/' + large.length + '/' + large.length);
  assert.deepEqual(requests, [partPath(sha, 0), partPath(sha, 1)]);

  const key = '/.snail/sha256/' + sha;
  const sizes = await browser.evaluate(`(async () => {
    const c = await caches.open('snail-static-resources-v1'), key = ${JSON.stringify(key)};
    return [!!await c.match(key), ...await Promise.all(['/0','/1'].map(async p => (await (await c.match(key+'/' + ${blobPartSize} + p)).arrayBuffer()).byteLength))];
  })()`);
  assert.deepEqual(sizes, [false, blobPartSize, 3]);
  // An evicted tail makes the cache a miss, and the parts are fetched again.
  await browser.evaluate(`caches.open('snail-static-resources-v1').then(c => c.delete(${JSON.stringify(key + '/' + blobPartSize + '/1')}))`);
  await browser.send('Network.setBlockedURLs', {urls: []});
  requests.length = 0;
  await browser.navigate(url);
  await until(async () => await result() === '2', 'evicted tail fetched again');
  assert.deepEqual(requests, [partPath(sha, 0), partPath(sha, 1)]);
  console.log('Static resources verify multipart transfers, report progress, retry and reuse complete files offline');
} finally {
  held.resolve();
  lastPart.resolve();
  browser.close();
  server.closeAllConnections();
  server.close();
}
