// The same namespace-publication program as Node and Wasmtime, running in
// Chromium with the browser's real scalar imports and WebAssembly instances.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const directory = await mkdtemp(join(tmpdir(), 'snail-wasm-replacement-'));
const binary = join(directory, 'test.wasm');
await promisify(execFile)(join(root, 'scripts/snail-tool'),
  ['compile', '-o', binary, join(root, 'tests/programs/wasm-replacement.sld')]);
const expected = await readFile(join(root, 'tests/programs/wasm-replacement.out'), 'utf8');
const page = `<!doctype html><title>Namespace publication</title><pre></pre>
<script type="module">
import {createWasi, instantiate, wasmImports} from './load.mjs';
const output = document.querySelector('pre');
try {
  const wasi = createWasi({print: (fd, line) => { output.textContent += line + '\\n'; }});
  const program = {runtime: null, host: {}, linked: new Map()};
  program.host['snail.runtime.wasm'] = wasmImports(() => program);
  const module = await WebAssembly.compile(await (await fetch('./test.wasm')).arrayBuffer());
  const instance = await instantiate(module, {...wasi.getImportObject(), ...program.host});
  program.runtime = instance;
  wasi.initialize(instance);
} catch (error) { document.body.dataset.error = String(error); }
document.body.dataset.finished = 'true';
</script>`;
const files = new Map([
  ['/', ['text/html', Buffer.from(page)]],
  ['/load.mjs', ['text/javascript', await readFile(join(root, 'host/browser/load.mjs'))]],
  ['/test.wasm', ['application/wasm', await readFile(binary)]],
]);
const server = createServer((request, response) => {
  const file = files.get(request.url);
  response.writeHead(file ? 200 : 404, file ? {'content-type': file[0]} : {});
  response.end(file?.[1]);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await openBrowser();
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  await until(() => browser.evaluate('document.body.dataset.finished'), 'namespace publication');
  assert.equal(await browser.evaluate('document.body.dataset.error'), undefined);
  assert.equal(await browser.evaluate('document.querySelector("pre").textContent'), expected);
  if (screenshot) await browser.screenshot(screenshot);
  console.log('namespace replacement preserves identity, rejects partial publication and runs no initialization');
} finally {
  browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await rm(directory, {recursive: true, force: true});
}
