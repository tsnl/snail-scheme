// A raster renderer for immutable Scheme scene batches. Scheme declares each
// batch's dependencies; the bridge reuses equal batches and this owner uploads
// only batch objects it has not already placed in a GPU buffer.

async function compile(device, source, format) {
  device.pushErrorScope('validation');
  const module = device.createShaderModule({code: source});
  const validation = device.popErrorScope();
  const [info, error] = await Promise.all([module.getCompilationInfo(), validation]);
  if (error) throw new Error(error.message);
  const failures = info.messages.filter(message => message.type === 'error');
  if (failures.length) throw new Error(failures.map(message => message.message).join('\n'));
  return device.createRenderPipelineAsync(descriptor(module, format));
}
function descriptor(module, format) {
  return {layout: 'auto', vertex: {module, entryPoint: 'vertex_main', buffers: [{arrayStride: 40, attributes: [
    {shaderLocation: 0, offset: 0, format: 'float32x3'}, {shaderLocation: 1, offset: 12, format: 'float32x3'},
    {shaderLocation: 2, offset: 24, format: 'float32x4'}]}]},
    fragment: {module, entryPoint: 'fragment_main', targets: [{format}]},
    primitive: {topology: 'triangle-list', cullMode: 'none'},
    depthStencil: {format: 'depth24plus', depthWriteEnabled: true, depthCompare: 'less'}};
}
function growBuffer(device, buffer, size, usage) {
  if (buffer && buffer.size >= size) return buffer;
  const next = device.createBuffer({size: Math.max(4096, size * 2), usage: usage | GPUBufferUsage.COPY_DST});
  buffer?.destroy(); return next;
}
function depthTarget(device, width, height) {
  const texture = device.createTexture({size: [width, height], format: 'depth24plus',
    usage: GPUTextureUsage.RENDER_ATTACHMENT});
  return {width, height, texture, view: texture.createView()};
}
function destroyGeometry(value) { value?.vertices?.destroy(); value?.indices?.destroy(); }

export async function createSceneRenderer(canvas, onError = () => {}) {
  if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser.');
  const adapter = await navigator.gpu.requestAdapter({powerPreference: 'high-performance'});
  if (!adapter) throw new Error('No WebGPU adapter is available.');
  const device = await adapter.requestDevice(), context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque', usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC});
  const uniform = device.createBuffer({size: 96, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  let current, previous, depth, closed = false, lost = false, closing, uploads = 0;
  const geometry = new Map(), pending = new Set();
  device.addEventListener('uncapturederror', event => { if (!closed) onError(event.error); });
  device.lost.then(info => { lost = true; if (!closed) onError(new Error(`WebGPU device lost: ${info.message}`)); });
  function track(operation) {
    pending.add(operation);
    operation.finally(() => pending.delete(operation)).catch(() => {}); return operation;
  }
  function prepare(source) {
    if (closed || lost) return Promise.reject(new Error('3D renderer is closed'));
    return track(compile(device, source, format).then(pipeline => {
      if (closed || lost) throw new Error('3D renderer closed during shader preparation');
      return {pipeline, bindings: device.createBindGroup({layout: pipeline.getBindGroupLayout(0),
        entries: [{binding: 0, resource: {buffer: uniform}}]})};
    }));
  }
  function upload(batch) {
    let stored = geometry.get(batch.key);
    if (stored?.source === batch) return stored;
    const vertexData = Float32Array.from(batch.vertices), indexData = Uint32Array.from(batch.indices);
    stored ??= {}; stored.vertices = growBuffer(device, stored.vertices, vertexData.byteLength, GPUBufferUsage.VERTEX);
    stored.indices = growBuffer(device, stored.indices, indexData.byteLength, GPUBufferUsage.INDEX);
    if (vertexData.length) device.queue.writeBuffer(stored.vertices, 0, vertexData);
    if (indexData.length) device.queue.writeBuffer(stored.indices, 0, indexData);
    stored.source = batch; stored.count = indexData.length; geometry.set(batch.key, stored); uploads++; return stored;
  }
  function resize() {
    if (depth?.width === canvas.width && depth?.height === canvas.height) return;
    const next = depthTarget(device, canvas.width, canvas.height);
    depth?.texture.destroy(); depth = next;
  }
  function draw(scene) {
    if (closed || lost || !current || !scene) return;
    resize(); device.queue.writeBuffer(uniform, 0, Float32Array.from(scene.uniforms));
    const batches = scene.batches.map(upload), target = context.getCurrentTexture();
    const commands = device.createCommandEncoder(), [r, g, b] = scene.background;
    const pass = commands.beginRenderPass({colorAttachments: [{view: target.createView(),
      clearValue: {r, g, b, a: 1}, loadOp: 'clear', storeOp: 'store'}],
      depthStencilAttachment: {view: depth.view, depthClearValue: 1, depthLoadOp: 'clear', depthStoreOp: 'discard'}});
    pass.setPipeline(current.pipeline); pass.setBindGroup(0, current.bindings);
    for (const batch of batches) if (batch.count) {
      pass.setVertexBuffer(0, batch.vertices); pass.setIndexBuffer(batch.indices, 'uint32'); pass.drawIndexed(batch.count);
    }
    pass.end(); device.queue.submit([commands.finish()]); return target;
  }
  async function readPixels(scene) {
    const target = draw(scene);
    if (!target) throw new Error('3D renderer cannot read a closed frame');
    const bytesPerRow = Math.ceil(canvas.width * 4 / 256) * 256;
    const copy = device.createBuffer({size: bytesPerRow * canvas.height, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ});
    try {
      const commands = device.createCommandEncoder();
      commands.copyTextureToBuffer({texture: target}, {buffer: copy, bytesPerRow}, [canvas.width, canvas.height]);
      device.queue.submit([commands.finish()]); await copy.mapAsync(GPUMapMode.READ);
      return {bytes: new Uint8Array(copy.getMappedRange()).slice(), bytesPerRow, format};
    } finally { copy.destroy(); }
  }
  async function dispose() {
    await Promise.allSettled([...pending]);
    if (!lost) await device.queue.onSubmittedWorkDone().catch(() => {});
    context.unconfigure(); depth?.texture.destroy(); for (const value of geometry.values()) destroyGeometry(value);
    uniform.destroy(); geometry.clear(); current = previous = depth = undefined; device.destroy();
  }
  return {adapter: adapter.info, device, prepare, draw,
    replace(candidate) { if (closed) return; previous = current; current = candidate; },
    rollback() { if (previous) { current = previous; previous = undefined; } },
    readPixels: scene => track(readPixels(scene)),
    close() { if (!closing) { closed = true; closing = dispose(); } return closing; },
    get resources() { return {closed, lost, uploads, batches: geometry.size,
      vertexBytes: [...geometry.values()].reduce((total, value) => total + (value.vertices?.size ?? 0), 0),
      indexBytes: [...geometry.values()].reduce((total, value) => total + (value.indices?.size ?? 0), 0),
      textures: depth ? 1 : 0, pending: pending.size}; }};
}
