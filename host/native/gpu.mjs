// The `Gpu` capability on Node: host/browser/gpu.mjs's objects and commands
// over Dawn, the WebGPU implementation Chromium uses, through Dawn's own
// Node binding, dawn.node. Dawn runs in this process and is called
// directly, where Chromium's runs in a GPU process that every call is sent
// to. The binding is npm's webgpu package (github.com/dawn-gpu/node-webgpu),
// which the repository's package.json pins and `npm ci` installs, and
// which a Node build's package depends on when its program may ask for a
// device. It loads at the program's first `request-device`, so a program
// that never asks needs none. Dawn keeps the guards a browser has, which
// cost little (doc/book/graphics/plan.md, "WebGPU on Node").
//
// A browser decodes images and Node does not, so `decode-image` is npm's
// @napi-rs/canvas package (github.com/Brooooooklyn/canvas), a 2D canvas
// over Skia, pinned and installed the same way and loaded at the
// program's first decode. It reads what a browser reads, JPEG, PNG, WebP,
// GIF and AVIF among them, and decodes off the program's thread, so
// several images decode at once while the program's tasks go on; only
// reading a decoded image's texels holds that thread.
import {createGpu, requestDevice} from '../browser/gpu.mjs';

// `program` gives the running program, whose memory holds staged Bytes;
// `tasks` are its tasks. Node has no canvas, so the program has no
// screen.
export function nodeGpu(program, tasks) {
  const execution = {tasks, get entry() { return program().exports; }};
  return createGpu(null, {execution}, nodeDevice);
}

// One device per run. The program's own targets are rgba8unorm, which
// reads back as a PNG's bytes. The device keeps Dawn's instance, the
// object `create` answers: dawn.node polls it while any work is pending,
// and an instance the collector frees crashes the process at the next
// poll, so it must stay reachable as long as the device works.
let shared = null;
function nodeDevice() {
  shared ??= opened();
  return shared;
}

// Dawn rounds timestamps to 65,536 nanoseconds by default, so that a page
// cannot time what other sites do; a program on Node is no page, and its
// profiles need the device's own resolution.
async function opened() {
  const {create, globals} = await import('webgpu');
  Object.assign(globalThis, globals);
  const instance = create(['disable-dawn-features=timestamp_quantization']);
  const {device, optional} = await requestDevice(instance);
  return {device, context: null, format: 'rgba8unorm', optional, instance, decode: encoded => nodeImage(device, encoded)};
}

// An encoded image as the canvas decodes it, for host/browser/gpu.mjs's
// `start-decode`, and as a page's is, texel for texel: turned as its EXIF
// orientation says, eight bits a channel, with straight alpha. The image
// is drawn on a canvas to be read, and a canvas keeps each color
// multiplied by its alpha as a page's bitmap does, so the two round a
// color that is not opaque alike. Bytes the canvas decodes no image from
// answer null. Node keeps the package once it is loaded, so each decode
// imports it.
async function nodeImage(device, encoded) {
  const {loadImage, createCanvas} = await import('@napi-rs/canvas');
  const image = await loadImage(encoded).catch(() => null);
  if (!image) return null;
  const {width, height} = image;
  const context = createCanvas(width, height).getContext('2d');
  context.drawImage(image, 0, 0);
  const {data} = context.getImageData(0, 0, width, height);
  return {width, height,
    write(texture) { device.queue.writeTexture({texture}, data, {bytesPerRow: 4 * width}, [width, height]); }};
}
