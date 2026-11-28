// The `Gpu` capability on a real WebGPU device: `snail-scheme build` builds
// tests/gpu, a static server serves it, and headless Chromium's software
// WebGPU runs it. The program reads back what it drew into a texture, red
// over a blue clear, and the two texels of a PNG it decoded, and finds every
// object by its path in a second frame. It composes the PNG into an atlas
// with a color swapped, draws it as quads, and reads both the quads' texels
// and the picture as a PNG data URL. It rasterizes two tiles lit by the
// sun, one glowing red and one white under ambient light. It squares numbers in a compute pass, scans and sorts on the GPU,
// splats gaussians under a transforms table it then changes, as quads
// and tile by tile, times a
// render pass, and runs lowered tensor programs, checked against their CPU
// evaluation and profiled, among them fused SSIM's gradient and
// densification. WebGPU reports no error.
// tests/gpu.mjs runs the checks that need no screen on Node, with the
// splat renderer's training checks, and tests/gpu/expected.mjs holds what
// both print.
//
//   CHROMIUM=... node tests/browser/gpu.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import {serve} from './static.mjs';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';
import {assertLines, deviceLines, fetchedLine, pageLines, splatLines, tensorLines} from '../gpu/expected.mjs';

const [root, screenshot] = process.argv.slice(2);
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
  assertLines(printed.slice(1).filter(line => !line.startsWith('url: ')),
    [...pageLines, ...deviceLines, ...tensorLines, ...splatLines, fetchedLine]);
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
  console.log('gpu: drawing, readback, decoding, objects kept across frames, atlas composition, quads, lit, tone-mapped and smoothed batches, a compute pass, a scan, a sort, splats as quads and tile by tile, a timed pass, tensor programs and their profile, fused SSIM, densification, a wait and a file read as bytes on a real device passed');
} finally {
  browser.close();
  server.close();
}
