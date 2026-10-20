// Browser platform binding: real WebGPU, a fixed vertex layout, replaceable
// validated pipelines. All scene and color decisions arrive as Scheme data.

// Pop each scope before awaiting. Concurrent reload candidates must not pop
// one another's device error scopes when compilation finishes out of order.
async function checkedShader(device, source) {
  device.pushErrorScope('validation');
  const module = device.createShaderModule({code: source});
  const validation = device.popErrorScope();
  const [info, error] = await Promise.all([module.getCompilationInfo(), validation]);
  if (error) throw new Error(error.message);
  const failures = info.messages.filter(message => message.type === 'error');
  if (failures.length) throw new Error(failures.map(message => message.message).join('\n'));
  return module;
}
async function checkedPipeline(device, descriptor) {
  device.pushErrorScope('validation');
  const pending = device.createRenderPipelineAsync(descriptor);
  const validation = device.popErrorScope();
  const [pipeline, error] = await Promise.allSettled([pending, validation]);
  if (error.status === 'rejected') throw error.reason;
  if (error.value) throw new Error(error.value.message);
  if (pipeline.status === 'rejected') throw pipeline.reason;
  return pipeline.value;
}

export async function createRenderer(canvas, onError = () => {}) {
  if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser. Use a WebGPU-enabled Chromium build.');
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error('No WebGPU adapter is available.');
  const device = await adapter.requestDevice(), context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque', usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC});
  let pipeline, previousPipeline, buffer, capacity = 0, lost = false, closed = false;
  device.addEventListener('uncapturederror', event => onError(event.error));
  device.lost.then(info => { lost = true; if (!closed) onError(new Error(`WebGPU device lost: ${info.message}`)); });
  const renderer = {
    adapter: adapter.info, device,
    async prepare(source) {
      const module = await checkedShader(device, source);
      return checkedPipeline(device, {layout: 'auto',
          vertex: {module, entryPoint: 'vertex_main', buffers: [{arrayStride: 24, attributes: [
            {shaderLocation: 0, offset: 0, format: 'float32x2'}, {shaderLocation: 1, offset: 8, format: 'float32x4'}]}]},
          fragment: {module, entryPoint: 'fragment_main', targets: [{format, blend: {
            color: {srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha'},
            alpha: {srcFactor: 'one', dstFactor: 'one-minus-src-alpha'}}}]}, primitive: {topology: 'triangle-list'}});
    },
    replace(candidate) { previousPipeline = pipeline; pipeline = candidate; },
    rollback() { if (previousPipeline) { pipeline = previousPipeline; previousPipeline = undefined; } },
    draw(quads, width, height) {
      if (!pipeline || lost) return;
      const values = new Float32Array(quads.length * 36); let offset = 0;
      for (const [x, y, w, h, rgb, opacity] of quads) {
        const rgba = [((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255, opacity / 255];
        for (const [px, py] of [[x,y], [x+w,y], [x,y+h], [x,y+h], [x+w,y], [x+w,y+h]]) {
          values.set([px / width * 2 - 1, 1 - py / height * 2, ...rgba], offset); offset += 6;
        }
      }
      if (values.byteLength > capacity) {
        buffer?.destroy(); capacity = Math.max(4096, values.byteLength * 2);
        buffer = device.createBuffer({size: capacity, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
      }
      if (values.length) device.queue.writeBuffer(buffer, 0, values);
      const target = context.getCurrentTexture();
      const commands = device.createCommandEncoder(), pass = commands.beginRenderPass({colorAttachments: [{
        view: target.createView(), clearValue: {r: .04, g: .06, b: .1, a: 1}, loadOp: 'clear', storeOp: 'store'}]});
      pass.setPipeline(pipeline); if (values.length) { pass.setVertexBuffer(0, buffer); pass.draw(quads.length * 6); }
      pass.end(); device.queue.submit([commands.finish()]); return target;
    },
    async readPixels(quads, width, height) {
      const target = renderer.draw(quads, width, height);
      if (!target) throw new Error('quad renderer has no frame to read');
      const bytesPerRow = Math.ceil(canvas.width * 4 / 256) * 256;
      const copy = device.createBuffer({size: bytesPerRow * canvas.height,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ});
      try {
        const commands = device.createCommandEncoder();
        commands.copyTextureToBuffer({texture: target}, {buffer: copy, bytesPerRow}, [canvas.width, canvas.height]);
        device.queue.submit([commands.finish()]); await copy.mapAsync(GPUMapMode.READ);
        return {bytes: new Uint8Array(copy.getMappedRange()).slice(), bytesPerRow, format};
      } finally { copy.destroy(); } // Destroying a mapped buffer also unmaps it.
    },
    close() { closed = true; buffer?.destroy(); device.destroy(); }
  };
  return renderer;
}
