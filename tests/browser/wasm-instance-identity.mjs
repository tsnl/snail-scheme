// The same explicit-linking identity program as Node runs, in
// Chromium with the browser's real scalar imports and WebAssembly instances.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'node', join(root, 'tests/programs/wasm-instance-identity.sld')]);
const output = stdout.trim();
const expected = await readFile(join(root, 'tests/programs/wasm-instance-identity.out'), 'utf8');
const page = `<!doctype html><title>Instance identity</title><pre></pre>
<script type="module">
import {createWasi, linkModule, runMain, wasmImports} from './load.mjs';
import {createTasks, taskExports} from './tasks.mjs';
const output = document.querySelector('pre');
try {
  const wasi = createWasi({print: (fd, line) => { output.textContent += line + '\\n'; }});
  const read = async file => new Uint8Array(await (await fetch(file)).arrayBuffer());
  let program;
  const host = {'snail.runtime.wasm': wasmImports(() => program)};
  const tasks = createTasks(() => program && taskExports(program));
  program = await linkModule(read, './wasm-instance-identity.wasm', wasi, host, () => tasks);
  runMain(program.exports, tasks);
  try { await tasks.drive(); } finally { tasks.close(); }
} catch (error) { document.body.dataset.error = String(error); }
document.body.dataset.finished = 'true';
</script>`;
// The page, the loader, and the build's module, read as the page asks
// for them.
const server = createServer(async (request, response) => {
  const path = decodeURIComponent(new URL(request.url, 'http://page').pathname);
  const file = path === '/' ? ['text/html', Buffer.from(page)]
    : ['/load.mjs', '/tasks.mjs', '/trace.mjs'].includes(path)
      ? ['text/javascript', await readFile(join(root, 'host/browser', path))]
    : await readFile(join(output, path)).then(bytes => ['application/wasm', bytes], () => null);
  response.writeHead(file ? 200 : 404, file ? {'content-type': file[0]} : {});
  response.end(file?.[1]);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await openBrowser();
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  await until(() => browser.evaluate('document.body.dataset.finished'), 'instance identity');
  assert.equal(await browser.evaluate('document.body.dataset.error'), undefined);
  assert.equal(await browser.evaluate('document.querySelector("pre").textContent'), expected);
  if (screenshot) await browser.screenshot(screenshot);
  console.log('explicit links preserve provider identity and initialize instances once');
} finally {
  browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
