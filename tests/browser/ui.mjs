// A document interface in a real page: `snail build` builds a copy of
// tests/apps/notes, a static server serves it, and headless Chromium types
// notes, adds them by the button and by Enter, which the listener's chord
// keeps from its default action, and removes one. The count of notes added
// arrives by a command's wake. Hiding the page stores the save, and a fresh
// load restores the notes from it.
//
//   CHROMIUM=... node tests/browser/ui.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {cp, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {extname, join, normalize} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm'};

// Serves a directory's files, and nothing outside it.
function serve(directory) {
  const server = createServer(async (request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, 'http://host').pathname)).replace(/^\/+/, '');
    try {
      const bytes = await readFile(join(directory, path === '' ? 'index.html' : path));
      response.writeHead(200, {'content-type': types[extname(path || 'index.html')] ?? 'application/octet-stream'});
      response.end(bytes);
    } catch {
      response.writeHead(404);
      response.end();
    }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const directory = await mkdtemp(join(tmpdir(), 'snail-ui-'));
const app = join(directory, 'notes');
await cp(join(root, 'tests/apps/notes'), app, {recursive: true});
const built = (await promisify(execFile)(join(root, 'snail'), ['build', app, 'site'])).stdout.trim();
const server = await serve(built);
const browser = await openBrowser();
const notes = () => browser.evaluate(`[...document.querySelectorAll('#notes li')].map(item => item.firstChild.data).join(',')`);
const added = () => browser.evaluate(`document.getElementById('added').textContent`);
const type = text => browser.evaluate(`(() => { const field = document.getElementById('draft');
  field.value = ${JSON.stringify(text)}; field.dispatchEvent(new Event('input', {bubbles: true})); })()`);
const ready = () => until(() => browser.evaluate('document.body.dataset.ready || document.body.dataset.error'), 'the interface');
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  assert.equal(await ready(), 'true');
  assert.equal(await notes(), '');

  await type('milk');
  await browser.evaluate(`document.getElementById('add').click()`);
  await until(async () => await notes() === 'milk', 'the first note');
  await until(async () => await added() === '1 added', 'the command that counts it');
  assert.equal(await browser.evaluate(`document.getElementById('draft').value`), '', 'the field empties');

  await type('eggs');
  const prevented = await browser.evaluate(`!document.getElementById('draft').dispatchEvent(
    new KeyboardEvent('keydown', {key: 'Enter', bubbles: true, cancelable: true}))`);
  assert.equal(prevented, true, 'the Enter chord prevents the default action');
  await until(async () => await notes() === 'milk,eggs', 'the note Enter adds');
  const other = await browser.evaluate(`!document.getElementById('draft').dispatchEvent(
    new KeyboardEvent('keydown', {key: 'a', bubbles: true, cancelable: true}))`);
  assert.equal(other, false, 'other keys keep their default action');

  await browser.evaluate(`document.getElementById('remove-0').click()`);
  await until(async () => await notes() === 'eggs', 'the removal');
  await until(async () => await added() === '2 added', 'the second count');

  await browser.evaluate(`Object.defineProperty(document, 'hidden', {configurable: true, get: () => true}),
    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))`);
  await until(() => browser.evaluate(`new Promise(resolve => {
    const request = indexedDB.open('snail-applications', 1);
    request.onsuccess = () => { const get = request.result.transaction('saves').objectStore('saves').get('notes');
      get.onsuccess = () => resolve(get.result !== undefined); get.onerror = () => resolve(false); };
    request.onerror = () => resolve(false); })`), 'the stored save');

  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  assert.equal(await ready(), 'true');
  await until(async () => await notes() === 'eggs', 'the restored notes');
  await type('tea');
  await browser.evaluate(`document.getElementById('add').click()`);
  await until(async () => await notes() === 'eggs,tea', 'a note after the restore');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('a document interface types, adds, removes, saves and restores');
} finally {
  browser.close();
  server.close();
  await rm(directory, {recursive: true, force: true});
}
