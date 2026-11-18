// The `gpu` effect on Node: host/browser/gpu.mjs's objects and commands
// over Dawn, the WebGPU implementation Chromium uses, through Dawn's own
// Node binding, dawn.node. Dawn runs in this process and is called
// directly, where Chromium's runs in a GPU process that every call is sent
// to. The binding is npm's webgpu package (github.com/dawn-gpu/node-webgpu),
// which the repository's package.json pins and `make fetch` installs, and
// which a Node build's package depends on when its program may ask for a
// device. It loads at the program's first `request-device`, so a program
// that never asks needs none. Dawn keeps the guards a browser has, which
// cost little (doc/book/graphics/plan.md, "WebGPU on Node").
//
// A browser decodes images and Node does not, so `decode-image` is npm's
// sharp package (sharp.pixelplumbing.com), a binding to libvips, pinned
// and installed the same way and loaded at the program's first decode. It
// reads what a browser reads, JPEG, PNG, WebP, GIF and AVIF among them,
// and decodes on libuv's threads, so several images decode at once while
// the program's tasks go on.
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

async function opened() {
  const {create, globals} = await import('webgpu').catch(error => {
    if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error;
    throw new Error('Node has no WebGPU here: install the webgpu package with npm');
  });
  Object.assign(globalThis, globals);
  const instance = create([]);
  const {device, optional} = await requestDevice(instance);
  return {device, context: null, format: 'rgba8unorm', optional, instance, decode: encoded => nodeImage(device, encoded)};
}

// An encoded image as sharp decodes it, for host/browser/gpu.mjs's
// `start-decode`, and as a page's would be: turned as its EXIF
// orientation says, in sRGB, eight bits a channel, with straight alpha.
// Bytes sharp decodes no image from answer null.
let sharp = null;
async function nodeImage(device, encoded) {
  sharp ??= import('sharp').then(module => module.default, error => {
    if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error;
    throw new Error('Node decodes no images here: install the sharp package with npm');
  });
  const decoded = await (await sharp)(encoded).autoOrient().toColourspace('srgb').ensureAlpha().raw({depth: 'uchar'})
    .toBuffer({resolveWithObject: true}).catch(() => null);
  if (!decoded) return null;
  const {data, info: {width, height}} = decoded;
  return {width, height,
    write(texture) { device.queue.writeTexture({texture}, data, {bytesPerRow: 4 * width, rowsPerImage: height}, [width, height]); }};
}
