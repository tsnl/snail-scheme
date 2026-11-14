// Live reload in a real page: `snail dev` serves a copy of tests/apps/counter
// on its applications' origin, and headless Chromium adds to the counter
// while the test edits the source. A new greeting arrives with the count kept, the
// state passing as it is; a broken edit is shown over the page; a changed
// state type passes the count through the save; a state and save that
// both change keep the old program running until the developer starts
// over; and a linked file's edit relinks the page from the module that
// links it; its explicit application entry reads the new resource.
//
//   CHROMIUM=... node tests/browser/reload.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);

async function edit(path, ...replacements) {
  let text = await readFile(path, 'utf8');
  for (let i = 0; i < replacements.length; i += 2) {
    const next = text.replace(replacements[i], replacements[i + 1]);
    assert.notEqual(next, text, `missing edit: ${replacements[i]}`);
    text = next;
  }
  await writeFile(path, text);
}

// Adds an I64 field, which every construction sets to 0, to the counter's
// state, so its layout changes.
const addStateField = (source, field) => edit(source,
  /\(height I32\)((?:\s+\(\w+ I64\))*)\)\)/, `(height I32)$1\n       (${field} I64)))`,
  /(\(new Counter\s+\(count (?:0|\(● (?:counter|saved) count\))\)\s+\(width (?:width|0)\)\s+\(height (?:height|0)\))((?:\s+\(\w+ 0\))*)\)/g,
  `$1$2 (${field} 0))`);

const directory = await realpath(await mkdtemp(join(tmpdir(), 'snail-reload-')));
const app = join(directory, 'counter'), source = join(app, 'src/counter/application.sld');
await cp(join(root, 'tests/apps/counter'), app, {recursive: true, filter: path => basename(path) !== 'build'});
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
  assert.match(await until(async () => (await notice()).match(/application\.sld:\d+:\d+: .*/)?.[0], 'the failure'), /application\.sld/);
  await edit(source, '(define (greeting) (→ String) 5)', '(define (greeting) (→ String) "fixed")');
  await until(async () => await text('greeting') === 'fixed', 'the fix');
  assert.equal(await text('count'), '2');

  await addStateField(source, 'extra');
  await until(async () => (await notice()).startsWith('Reloaded'), 'the state passed through the save');
  assert.equal(await text('count'), '2', 'the save carries the count to a state of another shape');

  await addStateField(source, 'more');
  await edit(source, /\(\(count I64\)\)\s+\(deriving/, '((count I64)\n       (extra I64))\n      (deriving', '(new Save (count (● counter count)))', '(new Save (count (● counter count)) (extra 0))');
  await until(async () => (await notice()).includes('could not take over'), 'the refused state');
  assert.equal(await text('count'), '2', 'the old program keeps running');
  await browser.evaluate(`[...document.querySelectorAll('[role="status"] button')].find(b => b.textContent.startsWith('Start over')).click()`);
  await until(async () => await text('count') === '0', 'the fresh start');
  // A consumed failing event is dropped; unread actions cross to the fix.
  const increment = '(Counter-count-set counter (+ (● counter count) 1))';
  await edit(source, increment, '(panic "update trap")', '"fixed"', '"ready to trap"');
  await until(async () => await text('greeting') === 'ready to trap', 'the trapping update');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click()`);
  await until(async () => (await notice()).includes('application stopped'), 'the stopped entry');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click(), document.querySelector('[data-key="add"]').click()`);
  await edit(source, '(panic "update trap")', increment, '"ready to trap"', '"recovered"');
  await until(async () => await text('greeting') === 'recovered' && await text('count') === '2', 'the checkpoint and unread actions');

  // A cold first-frame failure still registers its owner for a source fix.
  await edit(source, '(define (draw (counter Counter)) (→ Frame)\n', '(define (draw (counter Counter)) (→ Frame)\n  (panic "cold first view trap")\n');
  await until(async () => (await notice()).includes('cold first view trap'), 'the view before a page reload');
  await browser.navigate(base);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the stopped cold application');
  await until(async () => (await notice()).includes('application stopped'), 'the cold trap notice');
  // A rejected repair also traps when restarting the previous code. Its
  // failed rollback must retain the same restored checkpoint for another fix.
  await edit(source, 'cold first view trap', 'cold view still broken');
  await until(async () => (await notice()).includes('cold view still broken'), 'the rejected cold repair');
  await edit(source, '  (panic "cold view still broken")\n', '');
  await until(async () => await text('count') === '2' && (await notice()).startsWith('Reloaded'), 'the fixed cold application');

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
  await browser.evaluate(`${pageModule('application.mjs')}.then(({running}) => {
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

  // The application entry reads a file linked by a library. Editing the
  // file compiles that library again with the new bytes' digest. Relinking
  // invokes the entry again, which reads the changed resource.
  const banner = join(app, 'src/sample/banner.txt');
  const printed = line => browser.evaluate(`globalThis.printed.includes(${JSON.stringify(line)})`);
  await browser.evaluate(`globalThis.printed = []; const log = console.log;
    console.log = (...parts) => { globalThis.printed.push(parts.join(' ')); log(...parts); }`);
  await mkdir(join(app, 'src/sample'), {recursive: true});
  await writeFile(banner, 'linked');
  await writeFile(join(app, 'src/sample/banner.sld'), `(define-library (sample banner) (export print-banner)
    (import (snail core base) (snail core io) (only (snail shell task) tasks) (snail shell resource))
    (begin (define (banner) (→ Resource) (link-file "banner.txt"))
      (define (print-banner) (→ Unit) (! output-port resource tasks)
        (write-line (list->string (map (lambda (byte) (i32->char (u8->i32 byte)))
                                      (vector->list (read-resource (banner)))))))))`);
  // Startup belongs to the explicit Application entry. Relinking calls that
  // entry again; merely importing the library performs no source effects.
  await edit(source, '(snail shell wire))', `(snail shell wire)
   (snail core io)
   (only (snail shell task) tasks)
   (only (snail shell page) page)
   (only (snail shell resource) resource)
   (prefix (snail shell application) application:)
   (sample banner))`,
    '(type CounterApplication (SceneApplication Counter))', `(record CounterApplication ())
    (instance (application:Application (! mut screen events storage tasks page resource output-port) CounterApplication)
      (define (start (entry (application:Entry CounterApplication)))
        (→ Unit) (! mut screen events storage tasks page resource output-port)
        (print-banner)
        (application:start (ann (new application:Entry) (application:Entry (SceneApplication Counter))))))`);
  await until(() => printed('linked'), 'the linked file read by the explicit application entry');
  await browser.evaluate('globalThis.stayed = true');
  await writeFile(banner, 'linked again');
  await until(() => printed('linked again'), 'the linked file read again');
  assert.equal(await browser.evaluate('globalThis.stayed'), true, 'the page relinked rather than loading again');
  assert.equal(await text('count'), '1', 'and kept its state');

  // An incompatible save retries initialization. If that retry's first view
  // traps, a repair takes its checkpoint, not the new initializer's default.
  await edit(source, '(new Counter (count 0)', '(new Counter (count 7)',
    '(define (draw (counter Counter)) (→ Frame)\n', '(define (draw (counter Counter)) (→ Frame)\n  (panic "retry view trap")\n');
  await until(async () => (await notice()).includes('retry view trap'), 'the rejected retry view');
  await browser.evaluate(`${pageModule('storage.mjs')}.then(({storeSave}) => storeSave('counter', new Uint8Array([0])))`);
  await browser.navigate(base);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the stopped retry application');
  await until(async () => (await notice()).includes('application stopped'), 'the retry trap notice');
  await edit(source, '(new Counter (count 7)', '(new Counter (count 9)', '  (panic "retry view trap")\n', '');
  await until(async () => await text('count') === '7' && (await notice()).startsWith('Reloaded'), 'the repaired retry checkpoint');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('reload: the page kept its state across modules');
} catch (error) {
  console.error('reload failure:', {notice: await notice(), status: await service.status()});
  throw error;
} finally {
  browser.close();
  await service.stop();
  await rm(directory, {recursive: true, force: true});
}
