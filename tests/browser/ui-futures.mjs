// An owned browser model polls its futures after a generic wake. Hold
// server replies so input, replacement, late replies and reload happen
// while real host I/O is pending, rather than relying on timer ordering.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {cp, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {basename, extname, join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until, sleep} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const directory = await mkdtemp(join(tmpdir(), 'snail-ui-futures-'));
const app = join(directory, 'app');
await cp(join(root, 'tests/apps/futures'), app, {recursive: true, filter: path => basename(path) !== 'build'});
const built = (await promisify(execFile)(join(root, 'snail'), ['build', app, 'site'])).stdout.trim();
const waiting = [];
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.wasm': 'application/wasm'};
const server = createServer(async (request, response) => {
  if (request.url === '/api/text') { waiting.push(response); return; }
  const path = new URL(request.url, 'http://localhost').pathname;
  try {
    const file = path === '/' ? 'index.html' : path.slice(1);
    if (file.split('/').includes('..')) throw new Error('invalid path');
    const bytes = await readFile(join(built, file));
    response.writeHead(200, {'content-type': types[extname(file)] ?? 'application/octet-stream'});
    response.end(bytes);
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await openBrowser();
const url = `http://127.0.0.1:${server.address().port}/`;
const shown = id => browser.evaluate(`document.getElementById('${id}')?.textContent`);
const click = id => browser.evaluate(`document.getElementById('${id}').click()`);
const ready = () => until(() => browser.evaluate('document.body.dataset.error || document.body.dataset.ready'), 'the reactor');
const request = async () => {
  await click('load');
  await until(() => waiting.length > 0, 'the request on the server');
  return waiting.shift();
};
try {
  await browser.navigate(url);
  assert.equal(await ready(), 'true');
  assert.equal(await shown('result'), 'idle');
  // The shared save timer reaches an idle reactor too. A hard navigation
  // restores only its durable snapshot, independently of graceful refresh.
  await click('click');
  await until(async () => await shown('clicks') === '1', 'the value to save');
  await until(() => browser.evaluate(`import('./storage.mjs').then(({loadSave}) =>
    loadSave('futures')).then(bytes => bytes !== undefined)`), 'the periodic reactor save');
  await browser.navigate(url);
  assert.equal(await ready(), 'true');
  assert.equal(await shown('clicks'), '1', 'the periodic snapshot restored');
  const old = await request();
  assert.equal(await shown('result'), 'loading');
  await click('click');
  await until(async () => await shown('clicks') === '2', 'input while the future is pending');
  await click('cancel');
  await until(async () => await shown('result') === 'canceled', 'receiver cancellation');
  const next = await request();
  next.end('new result');
  await until(async () => await shown('result') === 'new result', 'the completion wake');
  old.end('obsolete result');
  await until(() => browser.evaluate(`performance.getEntriesByName(location.origin + '/api/text').length === 2`), 'the late host reply');
  await sleep(100);
  assert.equal(await shown('result'), 'new result', 'a canceled receiver cannot install a late result');

  // A graceful refresh checkpoints the owned model, drops its pending
  // future and closes its producer. The next instance restores only Save.
  const interrupted = await request();
  await browser.evaluate('void application.refresh()');
  await until(async () => await shown('result') === 'interrupted', 'the pending request restored as interrupted');
  assert.equal(await ready(), 'true');
  assert.equal(await shown('clicks'), '2');
  interrupted.end('after shutdown');
  const restored = await request();
  restored.end('loading');
  await until(() => browser.evaluate(`document.querySelector('main')?.getAttribute('aria-busy') === 'false'`), 'the literal loading reply collected');
  // The display string is data. Only a tagged Waiting snapshot represents
  // interrupted work; a completed reply named "loading" survives refresh.
  await browser.evaluate('application.refresh().then(() => true)');
  await until(async () => await shown('result') === 'loading' && await shown('clicks') === '2', 'the completed loading reply restored');
  const final = await request();
  final.end('restored and responsive');
  await until(async () => await shown('result') === 'restored and responsive', 'work after restoration');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('linear UI futures handle input, completion, cancellation, late replies, periodic saves and checkpoint restoration');
} finally {
  for (const response of waiting) response.end();
  browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await rm(directory, {recursive: true, force: true});
}
