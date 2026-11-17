// The `gpu` effect on a real WebGPU device: `snail-scheme build` builds
// tests/gpu, a static server serves it, and headless Chromium's software
// WebGPU runs it. The program reads back what it drew into a texture, red
// over a blue clear, and the two texels of a PNG it decoded, and finds every
// object by its path in a second frame. It composes the PNG into an atlas
// with a color swapped, draws it as quads, and reads both the quads' texels
// and the picture as a PNG data URL. It rasterizes two tiles into a
// G-buffer and lights them, one glowing red and one white under ambient
// light. It squares numbers in a compute pass, scans and sorts on the GPU,
// splats gaussians under a transforms table it then changes, and runs
// compiled tensor programs, checked against their CPU evaluation, among
// them the differentiable splat renderer's gradients. WebGPU
// reports no error.
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
    // The same light through Hable's curve and sRGB encoding: the grey
    // tile's 0.6 is 159, as the curve computed by hand gives.
    'filmic: 186 0 0 255 186 0 0 255 159 159 159 255 159 159 159 255',
    'squares: 1 4 9 16 10000',
    'planes: -0.25 -0.0 7 9 0',
    // An exclusive scan of i mod 3 over three levels of tiles, checked at
    // every index; a stable sort of 5,000 keys; and splats: red at the
    // left, green over red at the center, blue at the right, faint green
    // above, until turning the red one's transform stands it up.
    'scan: 0 0 1 3 510 511 513 262143 299998 all',
    'sort: paired sorted stable permutation',
    'splats: 96 2 0 255 40 209 0 255 7 0 225 255 0 2 0 255',
    'turned: 0 2 0 255 40 209 0 255 0 0 225 255 96 2 0 255',
    // A compiled tensor program computes each of its sinks as the CPU
    // evaluates them, and Adam fits a line in 1,000 runs of another.
    'tensor: 11 sinks agree',
    'fitted: from above 1 to below 1e-4, b 1.0',
    // The differentiable splat renderer: a pixel blended as the paper
    // does, every param's gradient of L1 and D-SSIM against central
    // differences, and Adam fitting a cloud to a rendered one.
    'splat forward: blends as the paper does',
    'splat gradients: means agree, scales agree, rotations agree, opacities agree, dc agree, degree1 agree, degree2 agree, degree3 agree',
    'splat fit: the loss falls by more than four times',
    // The page's own first bytes, and the server's 404 for a file it lacks.
    'fetched: <!doctype 404 fetching missing.bin',
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
  console.log('gpu: drawing, readback, decoding, objects kept across frames, atlas composition, quads, a lit, tone-mapped and smoothed G-buffer, motion and ids, a compute pass, a scan, a sort, splats, tensor programs, the differentiable splat renderer, a wait and a file read as bytes on a real device passed');
} finally {
  browser.close();
  server.close();
}
