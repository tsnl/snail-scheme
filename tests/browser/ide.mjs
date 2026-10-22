// The browser IDE in a real page: scripts/build-ide.scm packages it with
// tests/apps/counter as its project, a static server serves the site, and
// headless Chromium adds to the counter in the preview, then types into the
// editor. An edit relinks the preview with the count kept; a broken edit
// puts a squiggle under what the compiler points at; Tab indents as Emacs
// does; saving formats the file and keeps it across a reload; a split shows
// the buffer twice; and opening a folder replaces the project.
//
//   CHROMIUM=... node tests/browser/ide.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {extname, join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, sleep} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm'};

async function until(test, what) {
  for (let i = 0; i < 300; i++) {
    const value = await test();
    if (value) return value;
    await sleep(100);
  }
  throw new Error(`timed out waiting for ${what}`);
}

// Serves the site's files, nothing more.
function serve(site) {
  const server = createServer(async (request, response) => {
    const path = new URL(request.url, 'http://localhost').pathname;
    try {
      const bytes = await readFile(join(site, path.endsWith('/') ? `${path}index.html` : path));
      response.writeHead(200, {'content-type': types[extname(path)] ?? 'text/html'}).end(bytes);
    } catch {
      response.writeHead(404).end();
    }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const site = await mkdtemp(join(tmpdir(), 'lofi-ide-')), folder = await mkdtemp(join(tmpdir(), 'lofi-folder-'));
await promisify(execFile)(process.env.CHIBI ?? 'chibi-scheme', ['-h', '2G', '-I', join(root, 'host/chibi'), '-I', join(root, 'src'),
  join(root, 'scripts/build-ide.scm'), root, join(root, 'tests/apps/counter'), site]);
const server = await serve(site);
const browser = await openBrowser();
const frame = 'document.getElementById("preview").contentDocument';
const text = key => browser.evaluate(`${frame}?.querySelector('[data-key="${key}"] .text')?.textContent`);
const editorText = () => browser.evaluate('document.querySelector(".pane textarea").value');
// Selects the first match of `from` in the first pane and types `to` over it.
const type = (from, to) => browser.evaluate(`(() => { const t = document.querySelector('.pane textarea'), at = t.value.indexOf(${JSON.stringify(from)});
  if (at < 0) return false; t.focus(); t.setSelectionRange(at, at + ${from.length}); return document.execCommand('insertText', false, ${JSON.stringify(to)}); })()`);
const press = (target, init) => browser.evaluate(`${target}.dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  await until(() => browser.evaluate(`${frame}?.body?.dataset.ready`), 'the first build');
  await browser.evaluate(`${frame}.querySelector('[data-key="add"]').click(), ${frame}.querySelector('[data-key="add"]').click()`);
  await until(async () => await text('count') === '2', 'two presses');

  assert.ok(await type('"hello"', '"hello from the editor"'));
  await until(async () => await text('greeting') === 'hello from the editor', 'the new greeting');
  assert.equal(await text('count'), '2', 'the count survives the relink');

  assert.ok(await type('"hello from the editor"', '5'));
  const squiggle = await until(() => browser.evaluate('document.querySelector(".squiggle")?.textContent'), 'the squiggle');
  assert.equal(squiggle, '5');
  assert.match(await browser.evaluate('document.querySelector(".pane-diagnostic").textContent'), /^\d+:\d+: the literal 5 does not fit String/);
  assert.equal(await text('count'), '2', 'the old program keeps running');
  assert.ok(await type('(define greeting 5)', '(define greeting "fixed")'));
  await until(async () => await text('greeting') === 'fixed', 'the fix');
  assert.equal(await browser.evaluate('document.querySelector(".squiggle")'), null);

  assert.ok(await type('(define add-action 1)', '(define add-action\n1)'));
  await browser.evaluate(`(() => { const t = document.querySelector('.pane textarea'), at = t.value.indexOf('\\n1)') + 1; t.setSelectionRange(at, at); })()`);
  await press('document.querySelector(".pane textarea")', {key: 'Tab'});
  assert.match(await editorText(), /\(define add-action\n  1\)/, 'Tab indents the body of a definition');

  await browser.evaluate(`(() => { const t = document.querySelector('.pane textarea'), at = t.value.indexOf('(define add-action\\n  1)') + 18;
    t.setSelectionRange(at, at); document.execCommand('insertText', false, '   '); })()`);
  await press('document.querySelector(".pane textarea")', {key: 'Enter'});
  assert.match(await editorText(), /\(define add-action\n  \n  1\)/, 'Enter drops the spaces it leaves behind and indents the new line');
  assert.ok(await type('(define add-action\n  \n  1)', '(define add-action\n                1)'));
  await press('document', {code: 'KeyS', key: 's', ctrlKey: true});
  assert.match(await editorText(), /\(define add-action\n  1\)/, 'saving formats the file');
  assert.equal(await browser.evaluate('document.querySelector(".pane-title").textContent'), 'main.sld');
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  await until(() => browser.evaluate(`${frame}?.body?.dataset.ready`), 'the reload');
  assert.match(await editorText(), /\(define greeting "fixed"\)/, 'the saved file survives a reload');

  await press(`${frame}.getElementById("view")`, {code: 'KeyB', key: 'b', ctrlKey: true});
  assert.ok(await browser.evaluate('document.querySelector(".workspace").classList.contains("no-files")'), 'a chord in the preview reaches the IDE');
  await browser.evaluate('document.getElementById("toggle-files").click()');

  await browser.evaluate('document.getElementById("split-right").click()');
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane textarea").length'), 2);
  assert.ok(await type('"fixed"', '"twice"'));
  assert.match(await browser.evaluate('document.querySelectorAll(".pane textarea")[1].value'), /"twice"/, 'both panes show the buffer');
  if (screenshot) await browser.screenshot(screenshot);

  // Saved first, since unsaved changes would ask before they are dropped.
  await press('document', {code: 'KeyS', key: 's', ctrlKey: true});
  await cp(join(root, 'tests/apps/counter'), folder, {recursive: true});
  await writeFile(join(folder, 'main.sld'), (await readFile(join(folder, 'main.sld'), 'utf8')).replace('"hello"', '"from a folder"').replace(/\n/g, '\r\n'));
  await browser.evaluate('delete window.showDirectoryPicker; document.getElementById("open-folder").click()');
  const {result: {root: {nodeId}}} = await browser.send('DOM.getDocument');
  const {result: input} = await browser.send('DOM.querySelector', {nodeId, selector: '#folder-input'});
  await browser.send('DOM.setFileInputFiles', {nodeId: input.nodeId, files: [folder]});
  await until(async () => await text('greeting') === 'from a folder', 'the folder\'s project');
  assert.equal(await browser.evaluate('document.querySelector(".pane-title").textContent'), 'main.sld', 'a file with CRLF lines opens unchanged');
  console.log('ide: the page built, relinked, indented, saved and opened a folder');
} finally {
  browser.close();
  server.close();
  await rm(site, {recursive: true, force: true});
  await rm(folder, {recursive: true, force: true});
}
