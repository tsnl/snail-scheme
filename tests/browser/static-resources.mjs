// Exercise the browser resource service with two small published files. Hold part
// of a response to observe progress, fail the next request, then retry and reload.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const [root] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'tests/apps/static-resources/main.scm'], {cwd: root});
const directory = stdout.trim();
const catalog = JSON.parse(await readFile(join(directory, 'resources.json'), 'utf8'));
const object = ({sha256}) => 'store/sha256/' + sha256.slice(0, 2) + '/' + sha256;
const first = object(catalog['a.txt']), second = object(catalog['b.txt']);
const requests = [];
const held = Promise.withResolvers();
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
  console.log('Static resources report byte progress, retry, repair corrupt entries and reload offline');
} finally {
  held.resolve();
  browser.close();
  server.closeAllConnections();
  server.close();
}
