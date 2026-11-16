// The `gpu` effect's host, as (snail shell gpu page) calls it: the page's
// WebGPU device and the objects the program made on it, by the ids the
// program's books gave them. The books decide every lifetime; this file
// makes, uses and drops objects as it is told. A descriptor arrives as
// JSON in WebGPU's own names, in which `{"object": ID}` names an object,
// `{"view-of": TEXTURE, ...}` a view of a texture, and
// `{"layout-of": PIPELINE, "group": N}` a pipeline's bind group layout.

import {byteSnapshot} from './load.mjs';

// The features the graphics libraries need, and those they use when the
// adapter has them. Phones lack BC compression and SwiftShader, which the
// tests use, lacks f16 shaders, so both are optional.
const REQUIRED = ['indirect-first-instance', 'float32-filterable', 'rg11b10ufloat-renderable'];
const OPTIONAL = ['texture-compression-bc', 'shader-f16', 'timestamp-query'];

// ---- The device ----

// One device per page, configured on its canvas, which the scene renderer
// shares while it remains.
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
// staging, and its tasks, to wait in.
export function createGpu(canvas, runtime) {
  const decoder = new TextDecoder(), objects = new Map();
  let gpu = null, reply = [], held = new Uint8Array(), decoded = null;
  const bytes = address => byteSnapshot(runtime.execution.entry.memory, address);
  const tasks = () => runtime.execution.tasks;
  const object = id => objects.get(id);
  const revive = (key, value) => {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return value;
    if ('object' in value) return object(value.object);
    if ('view-of' in value) { const {'view-of': texture, ...view} = value; return texture.createView(view); }
    if ('layout-of' in value) return value['layout-of'].getBindGroupLayout(value.group);
    return value;
  };
  const descriptor = address => JSON.parse(decoder.decode(bytes(address)), revive);
  // A string answered a scalar at a time.
  const answer = text => { reply = [...text]; return reply.length; };
  // The constructors in the order of `kind-index` in (snail shell gpu page).
  const made = ['createBuffer', 'createTexture', 'createSampler', 'createShaderModule', 'createRenderPipeline', 'createBindGroup'];
  const copy = (texture, mipLevel, x, y, layer) => ({texture: object(texture), mipLevel, origin: [x, y, layer]});

  const imports = {
    // A page without the baseline answers 1, which the program reports.
    'start-device'(ticket) {
      tasks().start(Number(ticket), async () => {
        try { gpu = await pageDevice(canvas); return 0; } catch (error) { console.error(error.message); return 1; }
      }, status => status);
    },
    'finish-device': ticket => tasks().finish(Number(ticket)),
    'device-format': () => answer(gpu.format),
    'device-features': () => answer(gpu.optional.join(' ')),
    'reply-scalar': index => reply[index].codePointAt(0),
    create(kind, id, address) { objects.set(id, gpu.device[made[kind]](descriptor(address))); },
    destroy(id) { object(id)?.destroy?.(); objects.delete(id); },
    release(id) { objects.delete(id); },
    'write-buffer'(id, offset, address) { gpu.device.queue.writeBuffer(object(id), offset, bytes(address)); },
    'write-texture'(id, mip, x, y, layer, bytesPerRow, width, height, address) {
      gpu.device.queue.writeTexture(copy(id, mip, x, y, layer), bytes(address), {bytesPerRow, rowsPerImage: height}, [width, height, 1]);
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
      const encoded = bytes(address);
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
    'begin-pass'(encoder, id, address) { objects.set(id, object(encoder).beginRenderPass(descriptor(address))); },
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
    submit(address) { gpu.device.queue.submit(JSON.parse(decoder.decode(bytes(address))).map(object)); },
    // The canvas holds as many pixels as it covers on the screen.
    'current-texture'(id) {
      const width = Math.max(1, Math.round(canvas.clientWidth * devicePixelRatio));
      const height = Math.max(1, Math.round(canvas.clientHeight * devicePixelRatio));
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
    for (const value of objects.values()) if (value instanceof GPUBuffer || value instanceof GPUTexture) value.destroy();
    objects.clear();
    decoded?.destroy();
    decoded = null;
  }
  return {imports, reset};
}
