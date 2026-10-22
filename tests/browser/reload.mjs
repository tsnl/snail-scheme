// Live reload in a real page: `lofi serve` serves a copy of
// tests/apps/counter, and headless Chromium adds to the counter while the
// test edits the source. A new greeting arrives with the count kept, the
// state passing as it is; a broken edit is shown over the page; a changed
// state type passes the count through the save; and a state and save that
// both change keep the old program running until the developer starts
// over.
//
//   CHROMIUM=... node tests/browser/reload.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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

const directory = await mkdtemp(join(tmpdir(), 'lofi-reload-'));
const app = join(directory, 'counter'), source = join(app, 'main.sld');
await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
const server = spawn('node', [join(root, 'scripts/develop.mjs'), root, 'serve', '--port', '0', app], {stdio: ['ignore', 'pipe', 'inherit']});
let printed = '';
server.stdout.on('data', chunk => { printed += chunk; process.stdout.write(chunk); });
const browser = await openBrowser();
const text = key => browser.evaluate(`document.querySelector('[data-key="${key}"] .text')?.textContent`);
const notice = () => browser.evaluate(`document.querySelector('[role="status"]')?.style.display === 'block'
  ? document.querySelector('[role="status"]').textContent : ''`);
try {
  const base = await until(() => printed.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server and its tools', 300);
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
  if (screenshot) await browser.screenshot(screenshot);
  console.log('reload: the page kept its state across modules');
} finally {
  browser.close();
  server.kill();
  await rm(directory, {recursive: true, force: true});
}
