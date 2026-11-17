// The `gpu` effect on a real WebGPU device: `snail-scheme build` builds
// tests/gpu, a static server serves it, and headless Chromium's software
// WebGPU runs it. The program reads back what it drew into a texture, red
// over a blue clear, and the two texels of a PNG it decoded, and finds every
// object by its path in a second frame. It composes the PNG into an atlas
// with a color swapped, draws it as quads, and reads both the quads' texels
// and the picture as a PNG data URL. It rasterizes two tiles into a
// G-buffer and lights them, one glowing red and one white under ambient
// light. WebGPU reports no error.
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
  assert.deepEqual(printed.slice(1).filter(line => !line.startsWith('url: ')), [
    'target: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
    'image: 255 0 0 255 0 255 0 255',
    'again: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
    'quads: 0 0 255 255 0 0 255 255 0 255 0 255 0 255 0 255',
    'scene: 230 3 3 255 230 3 3 255 153 153 153 255 153 153 153 255',
    'squares: 1 4 9 16 10000',
    'planes: -0.25 -0.0 7 9 0',
  ]);
  // The data URL decodes to the picture: blue for the swapped red, then
  // green.
  const url = lines.find(line => line.startsWith('log: url: ')).slice('log: url: '.length);
  assert.deepEqual(await browser.evaluate(`(async () => {
    const image = new Image();
    image.src = ${JSON.stringify(url)};
    await image.decode();
    const canvas = new OffscreenCanvas(2, 1), context = canvas.getContext('2d');
    context.drawImage(image, 0, 0);
    return [...context.getImageData(0, 0, 2, 1).data];
  })()`), [0, 0, 255, 255, 0, 255, 0, 255]);
  if (screenshot) await browser.screenshot(screenshot);
  console.log('gpu: drawing, readback, decoding, objects kept across frames, atlas composition, quads, a lit, tone-mapped and smoothed G-buffer, motion and ids, and a compute pass on a real device passed');
} finally {
  browser.close();
  server.close();
}
