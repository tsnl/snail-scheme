// A typed document application uses the same development lifecycle as a
// scene: periodic save, direct state handover, and rollback after a bad view.
// CHROMIUM=... node tests/browser/ui-reload.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {cp, mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const directory = await realpath(await mkdtemp(join(tmpdir(), 'snail-ui-reload-')));
const app = join(directory, 'notes'), source = join(app, 'src/notes/application.sld');
await cp(join(root, 'tests/apps/notes'), app, {recursive: true, filter: path => basename(path) !== 'build'});
const service = await startDevelopment(root, app), browser = await openBrowser();
const notes = () => browser.evaluate(`[...document.querySelectorAll('#notes li')].map(item => item.firstChild.data).join(',')`);
const notice = () => browser.evaluate(`document.querySelector('[role="status"]')?.textContent ?? ''`);
const button = () => browser.evaluate(`document.getElementById('add')?.textContent`);
async function edit(...replacements) {
  let text = await readFile(source, 'utf8');
  for (let i = 0; i < replacements.length; i += 2) {
    const next = text.replace(replacements[i], replacements[i + 1]);
    assert.notEqual(next, text, `missing edit: ${replacements[i]}`);
    text = next;
  }
  await writeFile(source, text);
}
async function add(text) {
  await browser.evaluate(`(() => { const field = document.getElementById('draft');
    field.value = ${JSON.stringify(text)}; field.dispatchEvent(new Event('input', {bubbles: true}));
    document.getElementById('add').click(); })()`);
}

try {
  const base = (await service.settled(0)).published.targets.find(target => target.name === 'site').url;
  await browser.navigate(base);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the document application');
  await add('milk');
  await until(async () => await notes() === 'milk', 'the first note');

  // No display-frame or hidden event is needed to save a document.
  await until(() => browser.evaluate(`new Promise(resolve => {
    const request = indexedDB.open('snail-applications', 1);
    request.onsuccess = () => { const db = request.result;
      const get = db.transaction('saves').objectStore('saves').get('notes');
      get.onsuccess = () => { db.close(); resolve(get.result !== undefined); };
      get.onerror = () => { db.close(); resolve(false); }; };
    request.onerror = () => resolve(false); })`), 'the periodic document save');
  await browser.navigate(base);
  await until(async () => await notes() === 'milk', 'the periodically saved note restored');

  // Capture an event from the old view; a queued listener id must never
  // become a different listener after replacement.
  await browser.evaluate(`import(new URL('application.mjs', document.baseURI).href).then(({running}) => {
    globalThis.runtime = running[0].runtime;
    const send = runtime.send.bind(runtime);
    runtime.send = (...event) => { if (event[0] === 14 && !globalThis.oldEvent) globalThis.oldEvent = event; send(...event); };
    document.getElementById('draft').value = 'kept draft';
    document.getElementById('draft').dispatchEvent(new Event('input', {bubbles: true}));
    globalThis.stayed = true;
  })`);
  await edit('(Text "Add")', '(Text "Add note")');
  await until(async () => await button() === 'Add note', 'the replacement view');
  assert.equal(await notes(), 'milk');
  assert.equal(await browser.evaluate(`document.getElementById('draft').value`), 'kept draft');
  assert.equal(await browser.evaluate('stayed'), true, 'replacement keeps the page');
  await add('eggs');
  await until(async () => await notes() === 'milk,eggs', 'a note under the replacement');
  await browser.evaluate('runtime.send(...oldEvent), new Promise(resolve => setTimeout(resolve, 50))');
  assert.equal(await browser.evaluate(`document.getElementById('draft').value`), '', 'the replaced view cannot deliver an old event');

  await edit('(define (view model)\n', '(define (view model)\n      (panic "rejected document view")\n');
  await until(async () => (await notice()).includes('rejected document view'), 'the refused replacement');
  assert.equal(await notes(), 'milk,eggs', 'rollback restores the latest committed model');
  await add('tea');
  await until(async () => await notes() === 'milk,eggs,tea', 'the old application after rollback');
  await edit('      (panic "rejected document view")\n', '');
  await until(async () => (await notice()).startsWith('Reloaded'), 'the repaired document application');
  assert.equal(await notes(), 'milk,eggs,tea');

  // A stopped root extracts its save without presenting or replaying its
  // startup messages. Only starting the repaired application increments it.
  const trap = '      (when (string=? (::draft model) "trap") (panic "document update trap"))\n';
  await edit('(define (interface-messages model) (list (Load)))',
    '(define (interface-messages model) (list (Added (+ (::added model) 1))))',
    '(define (view model)\n', '(define (view model)\n' + trap,
    '(Text "Add note")', '(Text "Trap test")');
  await until(async () => await button() === 'Trap test', 'the recovery test application');
  const count = () => browser.evaluate(`Number(document.getElementById('added').textContent.split(' ')[0])`);
  const before = await count();
  await browser.evaluate(`document.getElementById('draft').value = 'trap',
    document.getElementById('draft').dispatchEvent(new Event('input', {bubbles: true}))`);
  await until(async () => (await notice()).includes('application stopped'), 'the stopped document');
  await edit(trap, '', '(Text "Trap test")', '(Text "Recovered")');
  await until(async () => await button() === 'Recovered', 'the recovered document');
  assert.equal(await count(), before + 1, 'checkpoint extraction never replays startup messages');
  assert.equal(await notes(), 'milk,eggs,tea');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('document reload: periodic saves, state handover, stale listeners and rollback passed');
} catch (error) {
  console.error('document reload failure:', await notice(), await service.status());
  throw error;
} finally {
  browser.close();
  await service.stop();
  await rm(directory, {recursive: true, force: true});
}
