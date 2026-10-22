// The browser IDE in a real page: scripts/build-ide.scm packages
// tests/apps/counter, a static server serves the site, and headless
// Chromium adds to the counter, then types into the editor. The toolchain
// builds in the page's worker; a new greeting arrives with the count kept,
// and a broken edit is shown over the page.
//
//   CHROMIUM=... node tests/browser/ide.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
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

const site = await mkdtemp(join(tmpdir(), 'lofi-ide-'));
await promisify(execFile)(process.env.CHIBI ?? 'chibi-scheme', ['-h', '2G', '-I', join(root, 'host/chibi'), '-I', join(root, 'src'),
  join(root, 'scripts/build-ide.scm'), root, join(root, 'tests/apps/counter'), site]);
const server = await serve(site);
const browser = await openBrowser();
const text = key => browser.evaluate(`document.querySelector('[data-key="${key}"] .text')?.textContent`);
const notice = () => browser.evaluate(`document.querySelector('[role="status"]')?.style.display === 'block'
  ? document.querySelector('[role="status"]').textContent : ''`);
const type = (from, to) => browser.evaluate(`(() => { const t = document.getElementById('source');
  t.value = t.value.replace(${JSON.stringify(from)}, ${JSON.stringify(to)}); t.dispatchEvent(new Event('input')); })()`);
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  await until(() => browser.evaluate('document.body.dataset.ready'), 'the first build');
  await browser.evaluate(`document.querySelector('[data-key="add"]').click(), document.querySelector('[data-key="add"]').click()`);
  await until(async () => await text('count') === '2', 'two presses');

  await type('"hello"', '"hello from the editor"');
  await until(async () => await text('greeting') === 'hello from the editor', 'the new greeting');
  assert.equal(await text('count'), '2', 'the count survives the relink');

  await type('"hello from the editor"', '5');
  assert.match(await until(async () => (await notice()).match(/main\.sld:\d+:\d+: .*/)?.[0], 'the failure'), /main\.sld/);
  assert.equal(await text('count'), '2', 'the old program keeps running');
  if (screenshot) await browser.screenshot(screenshot);
  console.log('ide: the page built and relinked its program as the source changed');
} finally {
  browser.close();
  server.close();
  await rm(site, {recursive: true, force: true});
}
