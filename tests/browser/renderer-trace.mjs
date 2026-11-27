import assert from 'node:assert/strict';
import {createCanvas, loadImage} from '@napi-rs/canvas';

export async function pixels(png) {
  const img = await loadImage(png);
  const canvas = createCanvas(img.width, img.height), ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  return {width: img.width, height: img.height, rgba: ctx.getImageData(0, 0, img.width, img.height).data};
}
// Read the owned output just as the offline renderer does. Browser canvas
// capture may return the preceding surface while changing sample count.
export function observeOutput() {
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

// Freeze the trace and enqueue a readback of the corresponding frame in the same
// JavaScript turn. Later frames cannot change the Blob or overtake the GPU copy.
export async function captureFrame(browser) {
  return browser.evaluate(`(async () => {
    const link = document.querySelector('a[download="renderer.jsonl"]');
    link.addEventListener('click', e => e.preventDefault(), {once: true});
    link.click();
    const [trace, image] = await Promise.all([fetch(link.href).then(r => r.text()), window.sceneOutput()]);
    return {trace, image};
  })()`);
}

export async function assertMatches(browserImage, offlinePng) {
  const image = await pixels(Buffer.from(browserImage.split(',')[1], 'base64'));
  const replay = await pixels(offlinePng);
  assert.equal(replay.width, image.width);
  assert.equal(replay.height, image.height);
  let close = 0;
  for (let i = 0; i < replay.rgba.length; i++)
    if (Math.abs(image.rgba[i] - replay.rgba[i]) <= 4) close++;
  assert.ok(close / replay.rgba.length > 0.99, 'browser/offline channels within four display levels: ' + close / replay.rgba.length);
}
