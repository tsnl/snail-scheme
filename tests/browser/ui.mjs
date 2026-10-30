// A document interface in a real page: `snail build` builds a copy of
// tests/apps/notes, a static server serves it, and headless Chromium types
// notes, adds them by the button and by Enter, which the listener's chord
// keeps from its default action, and removes one. The count of notes added
// arrives by a command's wake, and the command focuses the field it finds
// by id. Another command inserts text into the field as typing would,
// which the page can undo, and Tab inserts at a caret past an astral
// scalar, an offset of 2 to the page and 1 to Snail. Escape on the window
// clears the draft. The page asks its server for a greeting as it starts,
// shares its notes with headers and a body, and hears a stream of events
// until the server ends it. Hiding the page stores the save, a fresh load
// restores the notes from it, and clearing them asks first.
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

// The interface's server: a greeting, notes it echoes back with the headers
// that came with them, and a stream of events of three kinds, one of which
// the page does not hear, that ends for good, as the second connection is
// refused.
let streams = 0;
async function answerApi(request, response) {
  if (request.url === '/api/greeting') { response.writeHead(200, {'content-type': 'text/plain'}); response.end('hello from the server'); return; }
  if (request.url === '/api/notes' && request.method === 'POST') {
    let body = '';
    for await (const chunk of request) body += chunk;
    response.writeHead(201, {'content-type': 'text/plain'});
    response.end(`${request.headers['content-type']} ${request.headers['if-match']} ${JSON.stringify(body)}`);
    return;
  }
  if (request.url === '/api/events' && streams++ === 0) {
    response.writeHead(200, {'content-type': 'text/event-stream', 'cache-control': 'no-store'});
    response.end('retry: 100\ndata: one\n\nevent: note\ndata: two\n\nevent: unheard\ndata: three\n\n');
    return;
  }
  response.writeHead(204);
  response.end();
}

// Serves a directory's files, and nothing outside it, and the API.
function serve(directory) {
  const server = createServer(async (request, response) => {
    if (request.url.startsWith('/api/')) { await answerApi(request, response); return; }
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
  await browser.evaluate(`document.getElementById('add').focus(), document.getElementById('add').click()`);
  await until(async () => await notes() === 'milk', 'the first note');
  await until(async () => await added() === '1 added', 'the command that counts it');
  assert.equal(await browser.evaluate(`document.getElementById('draft').value`), '', 'the field empties');
  await until(() => browser.evaluate(`document.activeElement?.id === 'draft'`), 'the command focusing the field');

  await type('eggs');
  await browser.evaluate(`document.getElementById('bullet').click()`);
  const draft = () => browser.evaluate(`document.getElementById('draft').value`);
  await until(async () => await draft() === '- eggs', 'the inserted bullet');
  await browser.evaluate(`document.getElementById('draft').focus(), document.execCommand('undo')`);
  await until(async () => await draft() === 'eggs', 'the bullet undone');
  await browser.evaluate(`document.execCommand('redo')`);
  await until(async () => await draft() === '- eggs', 'the bullet redone');
  const prevented = await browser.evaluate(`!document.getElementById('draft').dispatchEvent(
    new KeyboardEvent('keydown', {key: 'Enter', bubbles: true, cancelable: true}))`);
  assert.equal(prevented, true, 'the Enter chord prevents the default action');
  await until(async () => await notes() === 'milk,- eggs', 'the note Enter adds');
  const other = await browser.evaluate(`!document.getElementById('draft').dispatchEvent(
    new KeyboardEvent('keydown', {key: 'a', bubbles: true, cancelable: true}))`);
  assert.equal(other, false, 'other keys keep their default action');

  await browser.evaluate(`document.getElementById('remove-0').click()`);
  await until(async () => await notes() === '- eggs', 'the removal');
  await until(async () => await added() === '2 added', 'the second count');

  const said = id => browser.evaluate(`document.getElementById('${id}').textContent`);
  await until(async () => await said('greeting') === '200 hello from the server', 'the greeting it starts with');

  await type('😀x');
  await browser.evaluate(`document.getElementById('draft').setSelectionRange(2, 2)`);
  const tab = await browser.evaluate(`!document.getElementById('draft').dispatchEvent(
    new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))`);
  assert.equal(tab, true, 'the Tab chord prevents the default action');
  await until(async () => await draft() === '😀  x', 'the spaces Tab inserts at the caret');
  await browser.evaluate(`document.body.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))`);
  await until(async () => await draft() === '', 'the draft Escape on the window clears');
  await type('tea');
  await browser.evaluate(`document.getElementById('add').click()`);
  await until(async () => await notes() === '- eggs,tea', 'the note to share');
  await browser.evaluate(`document.getElementById('share').click()`);
  assert.equal(await until(async () => (await said('shared')) || false, 'the shared notes'), '201 text/plain 3 "- eggs\\ntea"');
  await browser.evaluate(`document.getElementById('listen').click()`);
  await until(async () => await said('heard') === 'message:one,note:two,ended', 'the stream heard to its end');
  await browser.evaluate(`document.getElementById('remove-2').click()`);
  await until(async () => await notes() === '- eggs', 'the shared note removed');

  await browser.evaluate(`Object.defineProperty(document, 'hidden', {configurable: true, get: () => true}),
    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))`);
  await until(() => browser.evaluate(`new Promise(resolve => {
    const request = indexedDB.open('snail-applications', 1);
    request.onsuccess = () => { const get = request.result.transaction('saves').objectStore('saves').get('notes');
      get.onsuccess = () => resolve(get.result !== undefined); get.onerror = () => resolve(false); };
    request.onerror = () => resolve(false); })`), 'the stored save');

  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  assert.equal(await ready(), 'true');
  await until(async () => await notes() === '- eggs', 'the restored notes');
  await type('tea');
  await browser.evaluate(`document.getElementById('add').click()`);
  await until(async () => await notes() === '- eggs,tea', 'a note after the restore');
  await browser.evaluate(`window.confirm = question => (window.asked = question, false), document.getElementById('clear').click()`);
  assert.equal(await until(() => browser.evaluate('window.asked'), 'the question'), 'Remove every note?');
  assert.equal(await notes(), '- eggs,tea', 'declining keeps the notes');
  await browser.evaluate(`window.confirm = () => true, document.getElementById('clear').click()`);
  await until(async () => await notes() === '', 'the notes cleared once agreed');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('a document interface types, adds, removes, saves and restores');
} finally {
  browser.close();
  server.close();
  await rm(directory, {recursive: true, force: true});
}
