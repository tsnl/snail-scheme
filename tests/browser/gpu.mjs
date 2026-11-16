// The `gpu` effect on a real WebGPU device: `snail-scheme build` builds
// tests/gpu, a static server serves it, and headless Chromium's software
// WebGPU runs it. The program reads back what it drew into a texture, red
// over a blue clear, and the two texels of a PNG it decoded, and finds every
// object by its path in a second frame; WebGPU reports no error.
//
//   CHROMIUM=... node tests/browser/gpu.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {extname, join, normalize} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2);
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm'};

function serve(directory) {
  const server = createServer(async (request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, 'http://host').pathname)).replace(/^\/+/, '');
    try {
      const bytes = await readFile(join(directory, path === '' ? 'index.html' : path));
      response.writeHead(200, {'content-type': types[extname(path || 'index.html')] ?? 'application/octet-stream'});
      response.end(bytes);
    } catch {
      response.writeHead(404);
      response.end();
    }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const built = (await promisify(execFile)(join(root, 'snail-scheme'), ['build', '--target', 'browser', 'tests/gpu/main.scm'], {cwd: root})).stdout.trim();
const server = await serve(built);
const browser = await openBrowser();
try {
  await browser.navigate(`http://127.0.0.1:${server.address().port}/`);
  const state = await until(() => browser.evaluate('document.body.dataset.ready || document.body.dataset.error'), 'the program');
  const lines = await browser.evaluate('window.lines');
  assert.equal(state, 'true', lines.join('\n'));
  assert.deepEqual(lines.filter(line => line.startsWith('error:') || line.startsWith('warn:')), [], 'WebGPU reported nothing');
  const printed = lines.filter(line => line.startsWith('log: ')).map(line => line.slice(5));
  assert.match(printed[0], /^format: (bgra8unorm|rgba8unorm)$/);
  assert.deepEqual(printed.slice(1), [
    'fresh: #t #t',
    'target: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
    'image: 255 0 0 255 0 255 0 255',
    'fresh: #f #f',
    'again: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
  ]);
  if (screenshot) await browser.screenshot(screenshot);
  console.log('gpu: drawing, readback, decoding and objects by path on a real device passed');
} finally {
  browser.close();
  server.close();
}
