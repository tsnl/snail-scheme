// Live reload in a real page: `lofi serve` serves a copy of
// tests/apps/counter, and headless Chromium adds to the counter while the
// test edits the source. A new greeting arrives with the count kept; a
// broken edit is shown over the page; a changed Save type keeps the old
// module running until the developer starts over.
//
//   CHROMIUM=... node tests/browser/reload.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openBrowser, sleep} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);

async function until(test, what) {
  for (let i = 0; i < 300; i++) {
    const value = await test();
    if (value) return value;
    await sleep(100);
  }
  throw new Error(`timed out waiting for ${what}`);
}

async function edit(path, from, to) {
  await writeFile(path, (await readFile(path, 'utf8')).replace(from, to));
}

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
  const base = await until(() => printed.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server');
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

  await edit(source, '((count I64))\n  (deriving', '((count I64)\n   (extra I64))\n  (deriving');
  await edit(source, '(Save (Counter-count counter))', '(Save (Counter-count counter) 0)');
  await until(async () => (await notice()).includes('could not restore'), 'the refused save');
  assert.equal(await text('count'), '2', 'the old module keeps running');
  await browser.evaluate(`[...document.querySelectorAll('[role="status"] button')].find(b => b.textContent.startsWith('Start over')).click()`);
  await until(async () => await text('count') === '0', 'the fresh start');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('reload: the page kept its state across modules');
} finally {
  browser.close();
  server.kill();
  await rm(directory, {recursive: true, force: true});
}
