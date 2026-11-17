// The `gpu` effect's host, as (snail shell gpu page) calls it: the page's
// WebGPU device and the objects the program made on it, by the ids the
// program's books gave them. The books decide every lifetime; this file
// makes, uses and drops objects as it is told. The descriptor of an object
// being made arrives as staged words and texts in the order
// (snail shell gpu)'s "Descriptors as fields" gives, which `made` below
// reads into the dictionary WebGPU takes. A render pass arrives as calls,
// an attachment at a time.

import {byteSnapshot, byteView} from './load.mjs';

// The features the graphics libraries need, and those they use when the
// adapter has them. Phones lack BC compression and SwiftShader, which the
// tests use, lacks f16 shaders, so both are optional.
const REQUIRED = ['indirect-first-instance', 'float32-filterable', 'rg11b10ufloat-renderable'];
const OPTIONAL = ['texture-compression-bc', 'shader-f16', 'timestamp-query'];

// ---- The device ----

// One device per page, configured on its canvas.
let shared = null;
export function pageDevice(canvas) {
  shared ??= requestDevice(canvas);
  return shared;
}

// Buffers and storage bindings up to 1 GiB, 16384-texel textures and 64
// bytes of color attachments per sample, or as much as the adapter has.
async function requestDevice(canvas) {
  if (!navigator.gpu) throw new Error('this browser does not support WebGPU');
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error('this browser offers no WebGPU adapter');
  const missing = REQUIRED.filter(name => !adapter.features.has(name));
  if (missing.length) throw new Error(`this WebGPU adapter lacks ${missing.join(', ')}`);
  const optional = OPTIONAL.filter(name => adapter.features.has(name)), limits = adapter.limits;
  const device = await adapter.requestDevice({requiredFeatures: [...REQUIRED, ...optional], requiredLimits: {
    maxBufferSize: Math.min(limits.maxBufferSize, 2 ** 30),
    maxStorageBufferBindingSize: Math.min(limits.maxStorageBufferBindingSize, 2 ** 30),
    maxTextureDimension2D: Math.min(limits.maxTextureDimension2D, 16384),
    maxColorAttachmentBytesPerSample: Math.min(limits.maxColorAttachmentBytesPerSample, 64)}});
  device.addEventListener('uncapturederror', event => console.error('WebGPU:', event.error.message));
  const format = navigator.gpu.getPreferredCanvasFormat(), context = canvas.getContext('webgpu');
  context.configure({device, format, alphaMode: 'opaque'});
  return {device, context, format, optional};
}

// ---- Objects ----

// The runtime gives the running program's memory, to read Bytes from
// staging, and its tasks, to wait in. `open` answers the device, its
// canvas context, format and optional features: the page's, or a test's.
export function createGpu(canvas, runtime, open = pageDevice) {
  const objects = new Map();
  let gpu = null, reply = [], held = new Uint8Array(), decoded = null, pass = null, queued = [];
  const memory = () => runtime.execution.entry.memory;
  const tasks = () => runtime.execution.tasks;
  const object = id => objects.get(id);
  // A string answered a scalar at a time.
  const answer = text => { reply = [...text]; return reply.length; };
  const copy = (texture, mipLevel, x, y, layer) => ({texture: object(texture), mipLevel, origin: [x, y, layer]});
  const view = (texture, array, baseMipLevel, mipLevelCount, baseArrayLayer, layers) =>
    object(texture).createView({dimension: array ? '2d-array' : '2d', baseMipLevel, mipLevelCount, baseArrayLayer,
                                arrayLayerCount: layers || undefined});

  const imports = {
    // A page without the baseline answers 1, which the program reports.
    'start-device'(ticket) {
      tasks().start(Number(ticket), async () => {
        try { gpu = await open(canvas); return 0; } catch (error) { console.error(error.message); return 1; }
      }, status => status);
    },
    'finish-device': ticket => tasks().finish(Number(ticket)),
    'device-format': () => answer(gpu.format),
    'device-features': () => answer(gpu.optional.join(' ')),
    'reply-scalar': index => reply[index].codePointAt(0),
    create(kind, id, address) { objects.set(id, made[kind](gpu.device, fields(byteView(memory(), address)), object, view)); },
    destroy(id) { object(id)?.destroy?.(); objects.delete(id); },
    release(id) { objects.delete(id); },
    'write-buffer'(id, offset, address) { gpu.device.queue.writeBuffer(object(id), offset, byteView(memory(), address)); },
    'write-texture'(id, mip, x, y, layer, bytesPerRow, width, height, address) {
      gpu.device.queue.writeTexture(copy(id, mip, x, y, layer), byteView(memory(), address), {bytesPerRow, rowsPerImage: height}, [width, height, 1]);
    },
    'start-read'(ticket, id, offset, size) {
      const buffer = object(id);
      tasks().start(Number(ticket), async () => {
        await buffer.mapAsync(GPUMapMode.READ, offset, size);
        const read = new Uint8Array(buffer.getMappedRange(offset, size)).slice();
        buffer.unmap();
        return read;
      }, read => { held = read; return read.length; });
    },
    'finish-read': ticket => tasks().finish(Number(ticket)),
    'read-byte': index => held[index],
    // The decoded texture is held until the books give it an id.
    'start-decode'(ticket, usage, address) {
      const encoded = byteSnapshot(memory(), address);
      tasks().start(Number(ticket), async () => {
        const bitmap = await createImageBitmap(new Blob([encoded]));
        const texture = gpu.device.createTexture({size: [bitmap.width, bitmap.height], format: 'rgba8unorm', usage});
        gpu.device.queue.copyExternalImageToTexture({source: bitmap}, {texture}, [bitmap.width, bitmap.height]);
        bitmap.close();
        return texture;
      }, texture => { decoded = texture; return texture.width; });
    },
    'finish-decode': ticket => tasks().finish(Number(ticket)),
    'decoded-height': () => decoded.height,
    'keep-decoded'(id) { objects.set(id, decoded); decoded = null; },
    'drop-decoded'() { decoded.destroy(); decoded = null; },
    encoder(id) { objects.set(id, gpu.device.createCommandEncoder()); },
    'copy-buffer'(encoder, source, sourceOffset, destination, destinationOffset, size) {
      object(encoder).copyBufferToBuffer(object(source), sourceOffset, object(destination), destinationOffset, size);
    },
    'copy-texture-to-buffer'(encoder, texture, mip, x, y, layer, buffer, offset, bytesPerRow, width, height) {
      object(encoder).copyTextureToBuffer(copy(texture, mip, x, y, layer),
        {buffer: object(buffer), offset, bytesPerRow, rowsPerImage: height}, [width, height, 1]);
    },
    'copy-texture'(encoder, source, sourceMip, sx, sy, sourceLayer, destination, mip, x, y, layer, width, height) {
      object(encoder).copyTextureToTexture(copy(source, sourceMip, sx, sy, sourceLayer), copy(destination, mip, x, y, layer), [width, height, 1]);
    },
    // A pass's attachments come first, each its view and then its load and
    // store; a layer count of 0 means the rest.
    'pass-view'(texture, array, baseMip, mips, baseLayer, layers) {
      pass ??= {colorAttachments: []};
      pass.view = view(texture, array, baseMip, mips, baseLayer, layers);
    },
    'pass-color'(clear, r, g, b, a, store) {
      pass.colorAttachments.push({view: pass.view, loadOp: clear ? 'clear' : 'load', clearValue: {r, g, b, a},
                                  storeOp: store ? 'store' : 'discard'});
    },
    'pass-depth'(clear, depth, store) {
      pass.depthStencilAttachment = {view: pass.view, depthLoadOp: clear ? 'clear' : 'load', depthClearValue: depth,
                                     depthStoreOp: store ? 'store' : 'discard'};
    },
    'begin-pass'(encoder, id) {
      const {view: _, ...descriptor} = pass;
      pass = null;
      objects.set(id, object(encoder).beginRenderPass(descriptor));
    },
    'set-pipeline'(pass, pipeline) { object(pass).setPipeline(object(pipeline)); },
    'set-bind-group'(pass, index, group) { object(pass).setBindGroup(index, object(group)); },
    'set-vertex-buffer'(pass, slot, buffer, offset) { object(pass).setVertexBuffer(slot, object(buffer), offset); },
    'set-index-buffer'(pass, buffer, format, offset) { object(pass).setIndexBuffer(object(buffer), format ? 'uint32' : 'uint16', offset); },
    'set-scissor'(pass, x, y, width, height) { object(pass).setScissorRect(x, y, width, height); },
    draw(pass, vertices, instances, firstVertex, firstInstance) { object(pass).draw(vertices, instances, firstVertex, firstInstance); },
    'draw-indexed'(pass, indices, instances, firstIndex, baseVertex, firstInstance) {
      object(pass).drawIndexed(indices, instances, firstIndex, baseVertex, firstInstance);
    },
    'draw-indexed-indirect'(pass, buffer, offset) { object(pass).drawIndexedIndirect(object(buffer), offset); },
    'end-pass'(pass) { object(pass).end(); },
    finish(encoder, id) { objects.set(id, object(encoder).finish()); },
    'queue-buffer'(id) { queued.push(object(id)); },
    submit() { gpu.device.queue.submit(queued); queued = []; },
    // The canvas holds as many pixels as it covers on the screen.
    'current-texture'(id) {
      const ratio = globalThis.devicePixelRatio ?? 1;
      const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
      const texture = gpu.context.getCurrentTexture();
      objects.set(id, texture);
      return texture.width;
    },
    'current-height': () => canvas.height,
  };

  // A program that starts again, cold or after a reload, knows no ids, so
  // the objects its last run made go.
  function reset() {
    for (const value of objects.values()) value.destroy?.();
    objects.clear();
    decoded?.destroy();
    decoded = null;
  }
  return {imports, reset};
}

// ---- Descriptors ----

// A reader over a descriptor's staged fields: words little-endian, and
// texts as a byte length, UTF-8 and padding to a word.
const utf8 = new TextDecoder();
function fields(bytes) {
  const data = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let at = 0;
  const word = () => { const value = data.getInt32(at, true); at += 4; return value; };
  const text = () => {
    const length = word(), value = utf8.decode(bytes.subarray(at, at + length));
    at += (length + 3) & ~3;
    return value;
  };
  return {word, text, flag: () => word() !== 0, list: read => Array.from({length: word()}, read)};
}

// Each kind's descriptor, in the order of `kind-index` in
// (snail shell gpu page): its label, then its fields as the matching
// `...-request` in (snail shell gpu) writes them.
const made = [
  (device, f) => device.createBuffer({label: f.text(), size: f.word(), usage: f.word()}),
  (device, f) => device.createTexture({label: f.text(), size: [f.word(), f.word(), f.word()], mipLevelCount: f.word(),
                                       format: f.text(), usage: f.word()}),
  (device, f) => {
    const label = f.text(), magFilter = f.text(), minFilter = f.text(), mipmapFilter = f.text(), address = f.text();
    return device.createSampler({label, magFilter, minFilter, mipmapFilter, addressModeU: address, addressModeV: address});
  },
  (device, f) => device.createShaderModule({label: f.text(), code: f.text()}),
  (device, f, object) => {
    const label = f.text(), module = object(f.word());
    const vertex = {module, entryPoint: f.text(), buffers: f.list(() => ({
      arrayStride: f.word(), stepMode: f.text(),
      attributes: f.list(() => ({format: f.text(), offset: f.word(), shaderLocation: f.word()}))}))};
    const component = () => ({operation: f.text(), srcFactor: f.text(), dstFactor: f.text()});
    const fragment = f.flag() ? {module, entryPoint: f.text(), targets: f.list(() => {
      const format = f.text();
      return f.flag() ? {format, blend: {color: component(), alpha: component()}} : {format};
    })} : undefined;
    const primitive = {topology: f.text(), cullMode: f.text()};
    const depthStencil = f.flag() ? {format: f.text(), depthWriteEnabled: f.flag(), depthCompare: f.text()} : undefined;
    return device.createRenderPipeline({label, layout: 'auto', vertex, fragment, primitive, depthStencil});
  },
  (device, f, object, view) => {
    const label = f.text(), layout = object(f.word()).getBindGroupLayout(f.word());
    const entries = f.list(() => {
      const binding = f.word(), kind = f.word();
      if (kind === 0) { const buffer = object(f.word()), offset = f.word(), size = f.word();
                        return {binding, resource: {buffer, offset, size: size || undefined}}; }
      if (kind === 1) { const texture = f.word(), dimension = f.text();
                        return {binding, resource: view(texture, dimension === '2d-array', f.word(), f.word(), f.word(), f.word())}; }
      return {binding, resource: object(f.word())};
    });
    return device.createBindGroup({label, layout, entries});
  },
];
