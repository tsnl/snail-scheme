// Live reload in a real page: `snail dev` serves a copy of tests/apps/counter
// on its applications' origin, and headless Chromium adds to the counter
// while the test edits the source. A new greeting arrives with the count kept, the
// state passing as it is; a broken edit is shown over the page; a changed
// state type passes the count through the save; a state and save that
// both change keep the old program running until the developer starts
// over; and a linked file's edit relinks the page from the module that
// links it.
//
//   CHROMIUM=... node tests/browser/reload.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);

async function edit(path, ...replacements) {
  let text = await readFile(path, 'utf8');
  for (let i = 0; i < replacements.length; i += 2) text = text.replace(replacements[i], replacements[i + 1]);
  await writeFile(path, text);
}

// Adds an I64 field, which every construction sets to 0, to the counter's
// state, so its layout changes.
const addStateField = (source, field) => edit(source, /\(height I32\)((?:\n   \(\w+ I64\))*)\)\)/, `(height I32)$1\n   (${field} I64)))`,
  /\(Counter 0 width height((?: 0)*)\)/, '(Counter 0 width height$1 0)',
  /\(Counter \(Counter-count counter\) width height((?: 0)*)\)/, '(Counter (Counter-count counter) width height$1 0)',
  /\(Counter \(Save-count saved\) 0 0((?: 0)*)\)/, '(Counter (Save-count saved) 0 0$1 0)');

const directory = await realpath(await mkdtemp(join(tmpdir(), 'snail-reload-')));
const app = join(directory, 'counter'), source = join(app, 'main.sld');
await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
const service = await startDevelopment(root, app);
const browser = await openBrowser();
// The page's own modules, from the build its base names.
const pageModule = name => `import(new URL('${name}', document.baseURI).href)`;
const text = key => browser.evaluate(`document.querySelector('[data-key="${key}"] .text')?.textContent`);
const notice = () => browser.evaluate(`document.querySelector('[role="status"]')?.style.display === 'block'
  ? document.querySelector('[role="status"]').textContent : ''`);
try {
  const base = (await service.settled(0)).published.targets.find(target => target.name === 'site').url;
  await browser.navigate(base);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the application');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click(), document.querySelector('[data-key="add"]').click()`);
  assert.equal(await until(async () => await text('count') === '2' && '2', 'two presses'), '2');

  await edit(source, '"hello"', '"hello again"');
  await until(async () => await text('greeting') === 'hello again', 'the new greeting');
  assert.equal(await text('count'), '2', 'the count survives the new module');

  await edit(source, '"hello again"', '5');
  assert.match(await until(async () => (await notice()).match(/main\.sld:\d+:\d+: .*/)?.[0], 'the failure'), /main\.sld/);
  await edit(source, '(define greeting 5)', '(define greeting "fixed")');
  await until(async () => await text('greeting') === 'fixed', 'the fix');
  assert.equal(await text('count'), '2');

  await addStateField(source, 'extra');
  await until(async () => (await notice()).startsWith('Reloaded'), 'the state passed through the save');
  assert.equal(await text('count'), '2', 'the save carries the count to a state of another shape');

  await addStateField(source, 'more');
  await edit(source, '((count I64))\n  (deriving', '((count I64)\n   (extra I64))\n  (deriving', '(Save (Counter-count counter))', '(Save (Counter-count counter) 0)');
  await until(async () => (await notice()).includes('could not take over'), 'the refused state');
  assert.equal(await text('count'), '2', 'the old program keeps running');
  await browser.evaluate(`[...document.querySelectorAll('[role="status"] button')].find(b => b.textContent.startsWith('Start over')).click()`);
  await until(async () => await text('count') === '0', 'the fresh start');
  // A candidate whose first view traps must leave the old entry usable.
  await edit(source, '(define (draw counter)\n', '(define (draw counter)\n  (panic "first view trap")\n');
  await until(async () => (await notice()).includes('first view trap'), 'the rejected first view');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click()`);
  await until(async () => await text('count') === '1', 'the old entry after rollback');
  await edit(source, '  (panic "first view trap")\n', '');
  await until(async () => (await notice()).startsWith('Reloaded'), 'the repaired view');

  // A consumed failing event is dropped; unread actions cross to the fix.
  const increment = '(Counter-count-set counter (+ (Counter-count counter) 1))';
  await edit(source, increment, '(panic "update trap")', '"fixed"', '"ready to trap"');
  await until(async () => await text('greeting') === 'ready to trap', 'the trapping update');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click()`);
  await until(async () => (await notice()).includes('application stopped'), 'the stopped entry');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click(), document.querySelector('[data-key="add"]').click()`);
  await edit(source, '(panic "update trap")', increment, '"ready to trap"', '"recovered"');
  await until(async () => await text('greeting') === 'recovered' && await text('count') === '3', 'the checkpoint and unread actions');

  // A cold first-frame failure still registers its owner for a source fix.
  await edit(source, '(define (draw counter)\n', '(define (draw counter)\n  (panic "cold first view trap")\n');
  await until(async () => (await notice()).includes('cold first view trap'), 'the view before a page reload');
  await browser.navigate(base);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the stopped cold application');
  await until(async () => (await notice()).includes('application stopped'), 'the cold trap notice');
  await edit(source, '  (panic "cold first view trap")\n', '');
  await until(async () => await text('count') === '3' && (await notice()).startsWith('Reloaded'), 'the fixed cold application');

  // Hold the first IndexedDB open across a build. A corrupt save forces the
  // cold retry; relinking must wait for that entire startup, including retry.
  await browser.evaluate(`${pageModule('storage.mjs')}.then(({storeSave}) => storeSave('counter', new Uint8Array([0])))`);
  const gate = await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: `
    const openSave = indexedDB.open.bind(indexedDB);
    let firstSaveOpen = true;
    indexedDB.open = (...args) => {
      const request = openSave(...args);
      if (firstSaveOpen) {
        firstSaveOpen = false;
        Object.defineProperty(request, 'onsuccess', {set(handler) {
          request.addEventListener('success', event => { globalThis.resumeSavedLoad = () => handler.call(request, event); }, {once: true});
        }});
      }
      return request;
    };`});
  await browser.navigate(base);
  await until(() => browser.evaluate('typeof resumeSavedLoad === "function"'), 'the suspended initial load');
  await browser.evaluate(`${pageModule('host.mjs')}.then(({running}) => {
    const app = running[0], startup = app.startup, stop = app.runtime.stop.bind(app.runtime);
    globalThis.startupWaited = false; globalThis.stopCount = 0;
    Object.defineProperty(app, 'startup', {get() { globalThis.startupWaited = true; return startup; }});
    app.runtime.stop = (...args) => { globalThis.stopCount++; return stop(...args); };
    app.runtime.send(9, 1);
  })`);
  await edit(source, '"recovered"', '"after slow startup"');
  await until(() => browser.evaluate('startupWaited'), 'the relink waiting for startup');
  assert.equal(await browser.evaluate('stopCount'), 0, 'a relink cannot stop half of a cold retry');
  await browser.evaluate('resumeSavedLoad()');
  await until(async () => await text('greeting') === 'after slow startup' && await text('count') === '1', 'the retry followed by relink');
  await browser.send('Page.removeScriptToEvaluateOnNewDocument', {identifier: gate.result.identifier});

  // The greeting becomes the text of a file a library links. Editing the
  // file compiles nothing and leaves every module's file as it was, but the
  // page relinks from the module that links it, which reads it again,
  // rather than loading again.
  const banner = join(app, 'src/sample/banner.txt');
  await mkdir(join(app, 'src/sample'), {recursive: true});
  await writeFile(banner, 'linked');
  await writeFile(join(app, 'src/sample/banner.sld'), `(define-library (sample banner) (export banner)
    (import (snail core base) (snail shell resource))
    (begin (: banner Resource) (define banner (link-bytes "banner.txt"))))`);
  await edit(join(app, 'project.datum'), '(public "public")', '(public "public")\n    (library-roots ("src"))');
  await edit(source, '(snail shell app))', '(snail shell app)\n (snail shell resource)\n (sample banner))',
    '(define greeting "after slow startup")',
    '(define greeting (list->string (map (lambda (byte) (i32->char (u8->i32 byte))) (vector->list (read-resource banner)))))');
  await until(async () => await text('greeting') === 'linked', 'the linked greeting');
  await browser.evaluate('globalThis.stayed = true');
  await writeFile(banner, 'linked again');
  await until(async () => await text('greeting') === 'linked again', 'the linked file read again');
  assert.equal(await browser.evaluate('globalThis.stayed'), true, 'the page relinked rather than loading again');
  assert.equal(await text('count'), '1', 'and kept its state');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('reload: the page kept its state across modules');
} finally {
  browser.close();
  await service.stop();
  await rm(directory, {recursive: true, force: true});
}
