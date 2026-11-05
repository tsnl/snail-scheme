// Structural editing in the real textarea, including native undo and the
// scalar/UTF-16 boundary. CHROMIUM=... node tests/browser/ide-edit.mjs ROOT [PNG]
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-edit-'));
const source = join(project, 'main.sld');
await writeFile(join(project, 'project.datum'), '((build-target main (program (entry "main.sld"))))');
await writeFile(source, '(import (snail core base))\n(unit)\n');
const service = await startDevelopment(root, project), browser = await openBrowser();
const field = 'document.querySelector(".pane.active textarea")';
const state = () => browser.evaluate(`(() => { const t = ${field}; return [t.value, t.selectionStart, t.selectionEnd]; })()`);
const select = (from, to = from) => browser.evaluate(`(() => { const t = ${field}; t.focus(); t.setSelectionRange(${from}, ${to}); })()`);
const press = init => browser.evaluate(`${field}.dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
async function load(text, from, to = from) {
  await browser.evaluate(`(() => { const t = ${field}; t.focus(); t.select(); document.execCommand('insertText', false, ${JSON.stringify(text)}); })()`);
  await until(async () => (await state())?.[0] === text, 'new draft');
  await select(from, to);
}
async function expect(text, start, end = start) {
  try { await until(async () => JSON.stringify(await state()) === JSON.stringify([text, start, end]), `edit ${JSON.stringify(text)}`); }
  catch (error) { assert.deepEqual(await state(), [text, start, end], error.message); }
}
try {
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate(`${field}?.value.includes('(unit)')`), 'editor');
  await load('', 0);
  assert.equal(await press({key: '(', shiftKey: true}), false);
  await expect('()', 1);
  await until(() => browser.evaluate('document.querySelectorAll(".matching-paren").length === 2'), 'pair highlight');
  await press({key: ')', shiftKey: true});
  await expect('()', 2);
  await browser.evaluate("document.execCommand('undo')");
  await expect('', 0);

  await load('a😀b', 1, 3);
  await press({key: '['});
  await expect('a[😀]b', 2, 4);
  await press({key: 'ArrowUp', altKey: true});
  await expect('a[😀]b', 1, 5);
  await select(1);
  await press({key: 'M', ctrlKey: true, shiftKey: true});
  await expect('a[😀]b', 4);
  await press({key: 'M', ctrlKey: true, shiftKey: true});
  await expect('a[😀]b', 1);

  await load('a😀[]b', 4);
  await press({key: 'Backspace'});
  await expect('a😀b', 3);
  await press({key: 'Backspace'});
  await expect('ab', 1);
  await browser.evaluate("document.execCommand('undo')");
  await expect('a😀b', 1, 3);
  await load('[]', 0);
  await press({key: 'Delete'});
  await expect('', 0);

  await load('"()" ; ()\n#\\(', 2);
  await press({key: '(', shiftKey: true});
  await expect('"(()" ; ()\n#\\(', 3);
  await until(() => browser.evaluate('document.querySelectorAll(".matching-paren").length === 0'), 'literal has no pairs');
  await load(';x\n', 0, 2);
  await press({key: '('});
  await expect('(\n', 1);
  await load('(a [b) c] (d)', 0);
  await press({key: 'M', ctrlKey: true, shiftKey: true});
  await expect('(a [b) c] (d)', 0);

  // The host must not consume composition, modified editing keys or ordinary typing.
  assert.equal(await press({key: '(', isComposing: true}), true);
  assert.equal(await press({key: 'Backspace', ctrlKey: true}), true);
  assert.equal(await press({key: 'x'}), true);

  const compact = '(import (snail core base))\n(: choose (-> Bool I64))\n(define (choose ready) (let ((a 1) (b 2)) (if ready (+ a b) 0)))\n(choose #t)\n';
  await load(compact, compact.indexOf('(+ a'));
  await browser.evaluate('document.getElementById("format").click()');
  await until(async () => (await state())[0].includes('(if ready\n'), 'structural format');
  const [formatted, caret] = await state();
  assert.equal(formatted.slice(caret, caret + 6), '(+ a b', 'format keeps the caret on its token');
  assert.match(formatted, /\(let \(\(a 1\)\n +\(b 2\)\)\n +\(if ready\n +\(\+ a b\)\n +0\)\)\)/);
  await browser.evaluate('document.getElementById("save").click()');
  await until(async () => await readFile(source, 'utf8') === formatted, 'formatted save');
  await until(() => browser.evaluate('document.getElementById("status").dataset.state === "built"'), 'formatted source compiles');
  await select(formatted.indexOf('(if ready'));
  await until(() => browser.evaluate('document.querySelectorAll(".matching-paren").length === 2'), 'formatted match highlight');
  const colors = await browser.evaluate(`[
    getComputedStyle(document.querySelector('.tok-punctuation')).color,
    getComputedStyle(document.querySelector('.highlight')).color,
    getComputedStyle(document.querySelector('.matching-paren')).color]`);
  assert.notEqual(colors[0], colors[1]);
  assert.equal(colors[1], colors[2]);
  if (screenshot) await browser.screenshot(screenshot);
  console.log('ide-edit: pairs, wrapping, Unicode deletion, undo, matching, literal boundaries, formatting and save');
} finally {
  browser.close();
  await service.stop();
  await rm(project, {recursive: true, force: true});
}
