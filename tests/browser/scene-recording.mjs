// Record a viewer frame and replay it on a fresh native WebGPU device.
// Browser URLs are remapped to the same local asset for offline playback.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const run = promisify(execFile), root = process.argv[2], cli = join(root, 'snail-scheme');
const asset = join(root, 'tests/gpu/src/gpu-test/materials.gltf');
const model = await readFile(asset);
const {stdout} = await run(cli, ['build', '--target', 'browser', 'src/apps/viewer/main.scm'], {cwd: root});
const server = await serve(stdout.trim(), (path, res) => {
  if (path !== 'materials.gltf') return false;
  res.writeHead(200, {'content-type': 'model/gltf+json'}).end(model);
  return true;
});
const dir = await mkdtemp(join(tmpdir(), 'snail-scene-'));
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
const tap = async key => {
  for (const type of ['keyDown', 'keyUp']) await browser.send('Input.dispatchKeyEvent', {type, key});
};
async function pixels(png) {
  const img = await loadImage(png);
  const canvas = createCanvas(img.width, img.height), ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  return {width: img.width, height: img.height, rgba: ctx.getImageData(0, 0, img.width, img.height).data};
}
// Read the owned output just as the offline renderer does. Browser canvas
// capture may return the preceding surface while changing sample count.
function observeOutput() {
  const create = GPUDevice.prototype.createTexture;
  GPUDevice.prototype.createTexture = function(desc) {
    const texture = create.call(this, desc);
    if (texture.label === 'forward/depth') window.cameraSamples = texture.sampleCount;
    if (texture.label === 'forward/output') window.sceneOutput = async () => {
      const {width, height} = texture, pitch = Math.ceil(width * 4 / 256) * 256;
      const buffer = this.createBuffer({size: height * pitch, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ});
      const enc = this.createCommandEncoder();
      enc.copyTextureToBuffer({texture}, {buffer, bytesPerRow: pitch}, {width,height});
      this.queue.submit([enc.finish()]);
      await buffer.mapAsync(GPUMapMode.READ);
      const data = new Uint8Array(buffer.getMappedRange()), rgba = new Uint8ClampedArray(width * height * 4);
      for (let y = 0; y < height; y++) rgba.set(data.subarray(y*pitch, y*pitch + width*4), y*width*4);
      buffer.unmap(); buffer.destroy();
      const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
      canvas.getContext('2d').putImageData(new ImageData(rgba,width,height),0,0);
      return canvas.toDataURL();
    };
    return texture;
  };
}
try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observeOutput.toString() + ')()'});
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 192, height: 120, deviceScaleFactor: 1, mobile: false});
  const url = 'http://127.0.0.1:' + server.address().port;
  await browser.navigate(url + '/?model=' + encodeURIComponent(url + '/materials.gltf'));
  await until(() => browser.evaluate('document.body?.dataset.ready && document.querySelector("#status").textContent !== "Loading…"'), 'viewer model');
  await tap('4'); await tap('t');
  await until(() => browser.evaluate('document.querySelector("#status").textContent.includes("Recording.")'), 'record start');
  const image = await until(async () => {
    const uri = await browser.evaluate('window.cameraSamples === 4 && window.sceneOutput()');
    if (!uri) return false;
    const value = await pixels(Buffer.from(uri.split(',')[1], 'base64'));
    return new Set(value.rgba).size > 20 && value;
  }, 'shaded image');
  await browser.evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))))');
  await tap('t');
  const clip = await until(() => browser.evaluate('document.querySelector("a[download]")?.href'), 'recorded scene');
  const trace = join(dir, 'viewer.snail-scene');
  await writeFile(trace, Buffer.from(clip.split(',')[1], 'base64'));
  const png = join(dir, 'replayed.png');
  await run(cli, ['run', '--target', 'node', 'tools/render.scm', 'replay=' + trace, 'scene=' + asset, 'output=' + png], {cwd: root});
  const replay = await pixels(await readFile(png));
  assert.equal(replay.width, image.width);
  assert.equal(replay.height, image.height);
  let close = 0;
  for (let i = 0; i < replay.rgba.length; i++) if (Math.abs(image.rgba[i] - replay.rgba[i]) <= 4) close++;
  assert.ok(close / replay.rgba.length > 0.99, '99% of viewer and offline channels agree within four display levels: ' + close / replay.rgba.length);
  console.log('Recorded viewer scene reproduced offline at ' + image.width + '×' + image.height + '.');
} finally {
  browser.close();
  server.close();
  await rm(dir, {recursive: true, force: true});
}
