// A raster renderer for copied Scheme scene data. It owns exactly one device,
// one growable vertex/index pair, one uniform buffer and the size-bound targets.
// Geometry, camera, lighting and material decisions have already been made in Scheme.

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
    primitive: {topology: 'triangle-list', cullMode: 'none'}, multisample: {count: 4},
    depthStencil: {format: 'depth24plus', depthWriteEnabled: true, depthCompare: 'less'}};
}
function growBuffer(device, buffer, size, usage) {
  if (buffer && buffer.size >= size) return buffer;
  const next = device.createBuffer({size: Math.max(4096, size * 2), usage: usage | GPUBufferUsage.COPY_DST});
  buffer?.destroy(); return next;
}
function targets(device, width, height, format) {
  const depth = device.createTexture({size: [width, height], format: 'depth24plus', sampleCount: 4,
    usage: GPUTextureUsage.RENDER_ATTACHMENT});
  const color = device.createTexture({size: [width, height], format, sampleCount: 4,
    usage: GPUTextureUsage.RENDER_ATTACHMENT});
  return {width, height, depth, color, depthView: depth.createView(), colorView: color.createView()};
}
function destroyTargets(value) { value?.depth.destroy(); value?.color.destroy(); }

export async function createSceneRenderer(canvas, onError = () => {}) {
  if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser.');
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error('No WebGPU adapter is available.');
  const device = await adapter.requestDevice(), context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque', usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC});
  const uniform = device.createBuffer({size: 96, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  let current, previous, vertices, indices, attachments, closed = false, lost = false, closing;
  const pending = new Set();
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
  function upload(scene) {
    const vertexData = Float32Array.from(scene.vertices), indexData = Uint32Array.from(scene.indices);
    vertices = growBuffer(device, vertices, vertexData.byteLength, GPUBufferUsage.VERTEX);
    indices = growBuffer(device, indices, indexData.byteLength, GPUBufferUsage.INDEX);
    if (vertexData.length) device.queue.writeBuffer(vertices, 0, vertexData);
    if (indexData.length) device.queue.writeBuffer(indices, 0, indexData);
    device.queue.writeBuffer(uniform, 0, Float32Array.from(scene.uniforms));
  }
  function resize() {
    if (attachments?.width === canvas.width && attachments?.height === canvas.height) return;
    const next = targets(device, canvas.width, canvas.height, format);
    destroyTargets(attachments); attachments = next;
  }
  function draw(scene) {
    if (closed || lost || !current || !scene) return;
    resize(); upload(scene);
    const target = context.getCurrentTexture(), commands = device.createCommandEncoder();
    const [r, g, b] = scene.background;
    const pass = commands.beginRenderPass({colorAttachments: [{view: attachments.colorView,
      resolveTarget: target.createView(), clearValue: {r, g, b, a: 1}, loadOp: 'clear', storeOp: 'discard'}],
      depthStencilAttachment: {view: attachments.depthView, depthClearValue: 1, depthLoadOp: 'clear', depthStoreOp: 'discard'}});
    pass.setPipeline(current.pipeline); pass.setBindGroup(0, current.bindings);
    pass.setVertexBuffer(0, vertices); pass.setIndexBuffer(indices, 'uint32'); pass.drawIndexed(scene.indices.length);
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
    context.unconfigure(); destroyTargets(attachments); vertices?.destroy(); indices?.destroy(); uniform.destroy();
    current = previous = attachments = vertices = indices = undefined; device.destroy();
  }
  return {adapter: adapter.info, device, prepare, draw,
    replace(candidate) { if (closed) return; previous = current; current = candidate; },
    rollback() { if (previous) { current = previous; previous = undefined; } },
    readPixels: scene => track(readPixels(scene)),
    close() { if (!closing) { closed = true; closing = dispose(); } return closing; },
    get resources() { return {closed, lost, vertexBytes: vertices?.size ?? 0, indexBytes: indices?.size ?? 0,
      textures: attachments ? 2 : 0, pending: pending.size}; }};
}
