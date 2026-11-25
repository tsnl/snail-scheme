// Execute identical Wasm bytes with the project's scalar host on Node and on the page.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import * as host from '../../host/browser/load.mjs';
import {openBrowser, until} from '../../tests/browser/chromium.mjs';
import {serve} from '../../tests/browser/static.mjs';

async function drive(bytes, {createWasi, instantiate}) {
  const module = await WebAssembly.compile(bytes);
  for (const entry of WebAssembly.Module.imports(module)) {
    if (entry.module !== 'wasi_snapshot_preview1') throw new Error('Unlinked import ' + entry.name);
  }
  const wasi = createWasi({print: (_, line) => console.error(line)});
  const instance = await instantiate(module, wasi.getImportObject());
  wasi.initialize(instance);
  const travel = instance.exports.travel;
  return {parked: travel(0), powered: travel(1750), reset: travel(0)};
}

const root = fileURLToPath(new URL('../..', import.meta.url));
const artifact = 'build/rapier/drive.release.wasm';
const node = await drive(await readFile(new URL('../../' + artifact, import.meta.url)), host);
const page = `<title>Rapier test track</title><output></output><script type="module">
  import * as host from '/host/browser/load.mjs';
  try {
    const bytes = await (await fetch('/${artifact}')).arrayBuffer();
    document.querySelector('output').textContent = JSON.stringify(await (${drive})(bytes, host));
  } catch (error) { document.querySelector('output').textContent = JSON.stringify({error: String(error)}); }
</script>`;
const server = await serve(root, (path, response) => {
  if (path !== '') return false;
  response.writeHead(200, {'content-type': 'text/html'});
  response.end(page);
  return true;
});
try {
  const browser = await openBrowser();
  try {
    await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
    const output = await until(() => browser.evaluate("document.querySelector('output')?.textContent"),
      'Rapier vehicle on the page');
    const chromium = JSON.parse(output);
    for (const [name, result] of Object.entries({node, chromium})) {
      assert.ok(!result.error, result.error);
      assert.ok(Math.abs(result.parked) < 0.001 && Math.abs(result.reset) < 0.001);
      assert.ok(result.powered > 5 && result.powered < 90);
      console.log(name, result);
    }
  } finally { browser.close(); }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
