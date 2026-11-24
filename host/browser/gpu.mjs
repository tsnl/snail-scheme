// The `Gpu` capability's host, as (snail shell gpu) calls it: the page's
// WebGPU device, or Dawn's on Node (host/native/gpu.mjs), and the objects
// the program made on it, each by the id this file gave it when it made
// it. The program keeps an object as long
// as it likes and lets it go with `destroy`, which takes effect at the next
// submit, after the commands that use it; an encoder, a pass and a command
// buffer go once used, and the canvas's texture and its views at the next
// `current-texture`. The descriptor of an object being made
// arrives as staged words and texts in the order (snail shell gpu)'s
// "Descriptors as fields" gives, which `made` below reads into the
// dictionary WebGPU takes. A render pass arrives as calls, an attachment
// at a time.

import {byteSnapshot, byteView} from './load.mjs';
import {span, spansLater, traced, tracing} from './trace.mjs';

// The features the graphics libraries need, and those they use when the
// adapter has them. Phones lack BC compression and SwiftShader, which the
// tests use, lacks f16 shaders, so both are optional; splat training's
// backward pass sums over subgroups.
const REQUIRED = ['indirect-first-instance', 'float32-filterable', 'rg11b10ufloat-renderable'];
const OPTIONAL = ['texture-compression-bc', 'shader-f16', 'timestamp-query', 'subgroups'];

// ---- The device ----

// One device per page, configured on its canvas.
let shared = null;
export function pageDevice(canvas) {
  shared ??= configured(canvas);
  return shared;
}

async function configured(canvas) {
  if (!navigator.gpu) throw new Error('this browser does not support WebGPU');
  const {device, optional} = await requestDevice(navigator.gpu);
  const format = navigator.gpu.getPreferredCanvasFormat(), context = canvas.getContext('webgpu');
  context.configure({device, format, alphaMode: 'opaque'});
  return {device, context, format, optional, decode: encoded => pageImage(device, encoded)};
}

// An encoded image as the browser decodes it, for `imageTexture`: turned
// as its EXIF orientation says, with straight alpha. The bitmap keeps
// each color multiplied by its alpha, so the texture's color is exact
// where the image is opaque and rounded where it is not: (200, 100, 50)
// under an alpha of 3 comes back (170, 85, 85), and under an alpha of 0,
// black. Bytes the browser decodes no image from answer null.
async function pageImage(device, encoded) {
  const bitmap = await createImageBitmap(new Blob([encoded])).catch(() => null);
  return bitmap && {width: bitmap.width, height: bitmap.height,
    write(texture) { device.queue.copyExternalImageToTexture({source: bitmap}, {texture}, [bitmap.width, bitmap.height]); bitmap.close(); }};
}

// A device of `gpu`, the page's or Node's, with the baseline features and
// the optional ones its adapter has. Buffers and storage bindings up to 1
// GiB, 16384-texel textures, 64 bytes of color attachments per sample and
// 32 KiB of workgroup memory, or as much as the adapter has.
export async function requestDevice(gpu) {
  const adapter = await gpu.requestAdapter() ?? await gpu.requestAdapter({powerPreference: 'high-performance'});
  if (!adapter) throw new Error('this host offers no WebGPU adapter');
  const missing = REQUIRED.filter(name => !adapter.features.has(name));
  if (missing.length) throw new Error(`this WebGPU adapter lacks ${missing.join(', ')}`);
  const optional = OPTIONAL.filter(name => adapter.features.has(name)), limits = adapter.limits;
  const device = await adapter.requestDevice({requiredFeatures: [...REQUIRED, ...optional], requiredLimits: {
    maxBufferSize: Math.min(limits.maxBufferSize, 2 ** 30),
    maxStorageBufferBindingSize: Math.min(limits.maxStorageBufferBindingSize, 2 ** 30),
    maxTextureDimension2D: Math.min(limits.maxTextureDimension2D, 16384),
    maxColorAttachmentBytesPerSample: Math.min(limits.maxColorAttachmentBytesPerSample, 64),
    maxComputeWorkgroupStorageSize: Math.min(limits.maxComputeWorkgroupStorageSize, 32768)}});
  device.addEventListener('uncapturederror', event => console.error('WebGPU:', event.error.message));
  device.lost.then(info => console.error('WebGPU: device lost:', info.reason, info.message));
  return {device, optional};
}

// ---- Objects ----

// The runtime gives the running program's memory, to read Bytes from
// staging, and its tasks, to wait in. `open` answers the device, its
// canvas context, format and optional features, and `decode`, the host's
// image decoder: the page's, a test's, or Node's, which has no canvas:
// there `canvas` is null and the program has no screen. `decode` answers
// an encoded image's width, height and `write`, which puts its texels in
// a texture of that size, or null for bytes it decodes no image from.
export function createGpu(canvas, runtime, open = pageDevice) {
  const objects = new Map();
  let gpu = null, next = 1, reply = [], held = new Uint8Array(), decoded = null, pass = null, queued = [];
  let timestamps = null, timeline = null;
  let canvasIds = [], retired = [];
  const memory = () => runtime.execution.entry.memory;
  const tasks = () => runtime.execution.tasks;
  const object = id => objects.get(id);
  const keep = value => { objects.set(next, value); return next++; };
  // An object used up: answered, and forgotten.
  const take = id => { const value = objects.get(id); objects.delete(id); return value; };
  // A string answered a scalar at a time.
  const answer = text => { reply = [...text]; return reply.length; };
  const copy = (texture, mipLevel, x, y, layer) => ({texture: object(texture), mipLevel, origin: [x, y, layer]});

  const imports = {
    // A page without the baseline answers 1, which the program reports.
    'start-device'(ticket) {
      tasks().start(Number(ticket), async () => {
        try { gpu = await open(canvas); } catch (error) { console.error(error.message); return 1; }
        if (tracing && gpu.optional.includes('timestamp-query')) timeline = createTimeline(gpu.device);
        return 0;
      }, status => status);
    },
    'finish-device': ticket => tasks().finish(Number(ticket)),
    // Waits until the device has done the work submitted so far.
    'start-done'(ticket) {
      const start = performance.now();
      tasks().start(Number(ticket), async () => {
        await gpu.device.queue.onSubmittedWorkDone();
        span('wait', 'gpu done', start);
        return 0;
      }, status => status);
    },
    'finish-done': ticket => tasks().finish(Number(ticket)),
    'device-format': () => answer(gpu.format),
    'device-features': () => answer(gpu.optional.join(' ')),
    'storage-binding-size': () => gpu.device.limits.maxStorageBufferBindingSize,
    'reply-scalar': index => reply[index].codePointAt(0),
    create: (kind, address) => keep(made[kind](gpu.device, fields(byteView(memory(), address)), object)),
    'create-view'(texture, address) {
      const id = keep(viewOf(object(texture), fields(byteView(memory(), address))));
      if (canvasIds.includes(texture)) canvasIds.push(id);
      return id;
    },
    // At the next submit a buffer or texture frees its memory; any other
    // object is forgotten.
    destroy(id) { retired.push(id); },
    'write-buffer'(id, offset, address) { gpu.device.queue.writeBuffer(object(id), offset, byteView(memory(), address)); },
    'write-texture'(id, mip, x, y, layer, bytesPerRow, width, height, address) {
      gpu.device.queue.writeTexture(copy(id, mip, x, y, layer), byteView(memory(), address), {bytesPerRow, rowsPerImage: height}, [width, height, 1]);
    },
    'start-read'(ticket, id, offset, size) {
      const buffer = object(id);
      tasks().start(Number(ticket), async () => {
        const start = performance.now();
        await buffer.mapAsync(GPUMapMode.READ, offset, size);
        const read = new Uint8Array(buffer.getMappedRange(offset, size)).slice();
        buffer.unmap();
        span('wait', 'gpu read', start);
        return read;
      }, read => { held = read; return read.length; });
    },
    'finish-read': ticket => tasks().finish(Number(ticket)),
    'read-byte': index => held[index],
    // The decoded texture is held until the program keeps it; bytes that
    // are no image the host decodes answer a width of 0.
    'start-decode'(ticket, usage, address) {
      const encoded = byteSnapshot(memory(), address);
      tasks().start(Number(ticket), async () => {
        const start = performance.now(), image = await gpu.decode(encoded);
        span('wait', 'decode image', start);
        if (!image) return null;
        const texture = gpu.device.createTexture({size: [image.width, image.height], format: 'rgba8unorm', usage});
        image.write(texture);
        return texture;
      }, texture => { decoded = texture; return texture?.width ?? 0; });
    },
    'finish-decode': ticket => tasks().finish(Number(ticket)),
    'decoded-height': () => decoded.height,
    'keep-decoded'() { const id = keep(decoded); decoded = null; return id; },
    encoder: () => keep(gpu.device.createCommandEncoder()),
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
    // A pass's attachments come first, each its view, load and store.
    'pass-color'(view, clear, r, g, b, a, store) {
      pass ??= {colorAttachments: []};
      pass.colorAttachments.push({view: object(view), loadOp: clear ? 'clear' : 'load', clearValue: {r, g, b, a},
                                  storeOp: store ? 'store' : 'discard'});
    },
    // A location left without an attachment.
    'pass-no-color'() {
      pass ??= {colorAttachments: []};
      pass.colorAttachments.push(null);
    },
    // A depth attachment loads (0), clears (1), or is read-only (2).
    'pass-depth'(view, load, depth, store) {
      pass ??= {colorAttachments: []};
      pass.depthStencilAttachment = load === 2 ? {view: object(view), depthReadOnly: true}
        : {view: object(view), depthLoadOp: load ? 'clear' : 'load', depthClearValue: depth,
           depthStoreOp: store ? 'store' : 'discard'};
    },
    // The next pass's timestamp writes, render or compute.
    'pass-timestamps'(querySet, beginning, end) {
      timestamps = {querySet: object(querySet), beginningOfPassWriteIndex: beginning, endOfPassWriteIndex: end};
    },
    'begin-pass'(encoder) {
      const writes = timeline ? timeline.writes(object(encoder), timestamps) : timestamps;
      const descriptor = {...pass, ...(writes && {timestampWrites: writes})};
      pass = null;
      timestamps = null;
      const begun = object(encoder).beginRenderPass(descriptor);
      timeline?.begun(object(encoder), begun, writes, 'render pass');
      return keep(begun);
    },
    'set-pipeline'(pass, pipeline) {
      timeline?.uses(object(pass), object(pipeline));
      object(pass).setPipeline(object(pipeline));
    },
    'set-bind-group'(pass, index, group) { object(pass).setBindGroup(index, object(group)); },
    'set-vertex-buffer'(pass, slot, buffer, offset) { object(pass).setVertexBuffer(slot, object(buffer), offset); },
    'set-index-buffer'(pass, buffer, format, offset) { object(pass).setIndexBuffer(object(buffer), format ? 'uint32' : 'uint16', offset); },
    'set-scissor'(pass, x, y, width, height) { object(pass).setScissorRect(x, y, width, height); },
    draw(pass, vertices, instances, firstVertex, firstInstance) { object(pass).draw(vertices, instances, firstVertex, firstInstance); },
    'draw-indexed'(pass, indices, instances, firstIndex, baseVertex, firstInstance) {
      object(pass).drawIndexed(indices, instances, firstIndex, baseVertex, firstInstance);
    },
    'draw-indexed-indirect'(pass, buffer, offset) { object(pass).drawIndexedIndirect(object(buffer), offset); },
    'end-pass'(pass) { take(pass).end(); },
    'begin-compute'(encoder) {
      const writes = timeline ? timeline.writes(object(encoder), timestamps) : timestamps;
      timestamps = null;
      const begun = object(encoder).beginComputePass(writes ? {timestampWrites: writes} : undefined);
      timeline?.begun(object(encoder), begun, writes, 'compute pass');
      return keep(begun);
    },
    'set-compute-pipeline'(pass, pipeline) {
      timeline?.uses(object(pass), object(pipeline));
      object(pass).setPipeline(object(pipeline));
    },
    'set-compute-bind-group'(pass, index, group) { object(pass).setBindGroup(index, object(group)); },
    dispatch(pass, x, y, z) { object(pass).dispatchWorkgroups(x, y, z); },
    'dispatch-indirect'(pass, buffer, offset) { object(pass).dispatchWorkgroupsIndirect(object(buffer), offset); },
    'end-compute'(pass) { take(pass).end(); },
    'resolve-queries'(encoder, querySet, first, count, buffer, offset) {
      object(encoder).resolveQuerySet(object(querySet), first, count, object(buffer), offset);
    },
    finish(id) {
      const encoder = take(id);
      return keep(timeline ? timeline.finish(encoder) : encoder.finish());
    },
    'queue-buffer'(id) { queued.push(take(id)); },
    submit() {
      const submitted = performance.now();
      traced('gpu submit', () => gpu.device.queue.submit(queued));
      timeline?.submitted(queued, submitted);
      queued = [];
      for (const id of retired) take(id)?.destroy?.();
      retired = [];
    },
    // The canvas holds as many pixels as it covers on the screen. Last
    // frame's texture and its views go.
    'current-texture'() {
      if (!canvas) throw new Error('this host has no screen: draw into a texture of your own');
      for (const id of canvasIds) objects.delete(id);
      const ratio = globalThis.devicePixelRatio ?? 1;
      const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
      const id = keep(gpu.context.getCurrentTexture());
      canvasIds = [id];
      return id;
    },
    'current-width': () => canvas.width,
    'current-height': () => canvas.height,
  };

  // A program that starts again, cold or after a reload, knows no ids, so
  // the objects its last run made go.
  function reset() {
    for (const value of objects.values()) value.destroy?.();
    objects.clear();
    canvasIds = [];
    retired = [];
    decoded?.destroy();
    decoded = null;
  }
  return {imports, reset};
}

// ---- The device's timeline ----

// While a run is traced (trace.mjs), the host times every pass on a
// device that can, so that a trace shows the device's work beside the
// program's. A pass the program times writes the program's queries, and
// any other two of the host's own. As an encoder finishes, the queries its
// passes wrote are resolved and copied into one buffer, which is read once
// the device has done that work; then each pass is a span on the `gpu`
// track, named for the pipelines it set. WebGPU times passes, not draws or
// dispatches, so a pass is the finest span, and timing them costs the
// device a little.
//
// The device's times count from an origin of its own. A pass starts no
// earlier than its submit, so the host places the device's clock as early
// as it can be with no submit so far after its first pass: exactly once
// the device was idle at some submit, and otherwise early by however long
// work had waited. Durations are the device's own.
function createTimeline(device) {
  const encoders = new WeakMap(), passes = new WeakMap(), reads = new WeakMap();
  const timed = encoder => encoders.get(encoder) ?? encoders.set(encoder, {passes: [], own: [], used: 64}).get(encoder);
  let origin = null, offset = -Infinity;
  function draw(times, submitted) {
    origin ??= times[0].begin;
    const ms = time => Number(time - origin) / 1e6;
    offset = Math.max(offset, submitted - Math.min(...times.map(time => ms(time.begin))));
    for (const {name, begin, end} of times) span('gpu', name, ms(begin) + offset, ms(end) + offset);
  }
  return {
    // The program's timestamp writes for a pass of `encoder`, or the
    // host's own, from a set of 64 its passes share.
    writes(encoder, writes) {
      const record = timed(encoder);
      if (writes) return writes;
      if (record.used === 64) { record.own.push(device.createQuerySet({label: 'trace', type: 'timestamp', count: 64})); record.used = 0; }
      record.used += 2;
      return {querySet: record.own.at(-1), beginningOfPassWriteIndex: record.used - 2, endOfPassWriteIndex: record.used - 1};
    },
    begun(encoder, pass, writes, kind) {
      const record = {writes, kind, pipelines: []};
      timed(encoder).passes.push(record);
      passes.set(pass, record);
    },
    uses(pass, pipeline) {
      const {pipelines} = passes.get(pass);
      if (!pipelines.includes(pipeline.label)) pipelines.push(pipeline.label);
    },
    finish(encoder) {
      const record = encoders.get(encoder), read = record && resolvedTimes(device, encoder, record);
      const buffer = encoder.finish();
      if (read) reads.set(buffer, read);
      return buffer;
    },
    submitted(buffers, submitted) {
      for (const buffer of buffers)
        if (reads.has(buffer)) spansLater(reads.get(buffer)().then(times => times.length && draw(times, submitted)));
    },
  };
}

// The queries an encoder's passes wrote, resolved after its commands into
// one buffer, a range of each query set in turn; and the function that
// reads it once the device is done, answering each written pass's name and
// times, and destroying what the reading needed.
function resolvedTimes(device, encoder, {passes, own}) {
  const ranges = queryRanges(passes), first = new Map();
  let size = 0;
  for (const [set, [low, high]] of ranges) { first.set(set, size / 8 - low); size += 8 * (high - low + 1); }
  const readback = device.createBuffer({label: 'trace/times', size, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST});
  const used = [...own, readback];
  for (const [set, [low, high]] of ranges) {
    const count = high - low + 1;
    const resolved = device.createBuffer({label: 'trace/resolved', size: 8 * count, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC});
    encoder.resolveQuerySet(set, low, count, resolved, 0);
    encoder.copyBufferToBuffer(resolved, 0, readback, 8 * (first.get(set) + low), 8 * count);
    used.push(resolved);
  }
  const slot = (set, query) => first.get(set) + query;
  return async () => {
    await readback.mapAsync(GPUMapMode.READ);
    const times = new BigUint64Array(readback.getMappedRange().slice(0));
    for (const object of used) object.destroy();
    return passes.map(({writes, kind, pipelines}) => ({name: passName(kind, pipelines),
      begin: times[slot(writes.querySet, writes.beginningOfPassWriteIndex)], end: times[slot(writes.querySet, writes.endOfPassWriteIndex)]}))
      .filter(({begin, end}) => begin > 0n && end >= begin);
  };
}

// A pass is named for the first three pipelines it set, and how many
// more: `splat/fit, scan/scan_tiles, scan/add_sums +2`.
function passName(kind, pipelines) {
  if (!pipelines.length) return kind;
  const more = pipelines.length - 3;
  return pipelines.slice(0, 3).join(', ') + (more > 0 ? ` +${more}` : '');
}

// Each query set the passes wrote, and the first and last query written.
function queryRanges(passes) {
  const ranges = new Map();
  for (const {writes: {querySet, beginningOfPassWriteIndex: begin, endOfPassWriteIndex: end}} of passes) {
    const [low, high] = ranges.get(querySet) ?? [begin, end];
    ranges.set(querySet, [Math.min(low, begin, end), Math.max(high, begin, end)]);
  }
  return ranges;
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

// Each kind's descriptor, in the order of the kinds `made` in
// (snail shell gpu) numbers: its label, then its fields as the
// matching `...-fields` in (snail shell gpu) writes them. A bind group's
// pipeline is of either kind.
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
      if (!f.flag()) return null;
      const format = f.text();
      return f.flag() ? {format, blend: {color: component(), alpha: component()}} : {format};
    })} : undefined;
    const primitive = {topology: f.text(), cullMode: f.text()};
    const depthStencil = f.flag() ? {format: f.text(), depthWriteEnabled: f.flag(), depthCompare: f.text()} : undefined;
    return device.createRenderPipeline({label, layout: 'auto', vertex, fragment, primitive, depthStencil});
  },
  (device, f, object) => {
    const label = f.text(), layout = object(f.word()).getBindGroupLayout(f.word());
    const entries = f.list(() => {
      const binding = f.word(), kind = f.word();
      if (kind === 0) { const buffer = object(f.word()), offset = f.word(), size = f.word();
                        return {binding, resource: {buffer, offset, size: size || undefined}}; }
      return {binding, resource: object(f.word())};
    });
    return device.createBindGroup({label, layout, entries});
  },
  (device, f, object) => {
    const label = f.text(), module = object(f.word());
    return device.createComputePipeline({label, layout: 'auto', compute: {module, entryPoint: f.text()}});
  },
  (device, f) => device.createQuerySet({label: f.text(), type: 'timestamp', count: f.word()}),
];

// A view's dimension, first level and count, and first layer and count,
// 0 meaning the rest.
function viewOf(texture, f) {
  return texture.createView({dimension: f.text(), baseMipLevel: f.word(), mipLevelCount: f.word(),
                             baseArrayLayer: f.word(), arrayLayerCount: f.word() || undefined});
}
