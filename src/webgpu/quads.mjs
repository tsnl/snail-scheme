// Browser platform binding: real WebGPU, a fixed vertex layout, replaceable
// validated pipelines. All scene and color decisions arrive as Scheme data.
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
      device.pushErrorScope('validation');
      try {
        const module = device.createShaderModule({code: source});
        const info = await module.getCompilationInfo();
        const failures = info.messages.filter(message => message.type === 'error');
        if (failures.length) throw new Error(failures.map(e => e.message).join('\n'));
        return await device.createRenderPipelineAsync({layout: 'auto',
          vertex: {module, entryPoint: 'vertex_main', buffers: [{arrayStride: 24, attributes: [
            {shaderLocation: 0, offset: 0, format: 'float32x2'}, {shaderLocation: 1, offset: 8, format: 'float32x4'}]}]},
          fragment: {module, entryPoint: 'fragment_main', targets: [{format, blend: {
            color: {srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha'},
            alpha: {srcFactor: 'one', dstFactor: 'one-minus-src-alpha'}}}]}, primitive: {topology: 'triangle-list'}});
      } finally { const error = await device.popErrorScope(); if (error) throw new Error(error.message); }
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
      const bytesPerRow = Math.ceil(canvas.width * 4 / 256) * 256;
      const copy = device.createBuffer({size: bytesPerRow * canvas.height,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ});
      const commands = device.createCommandEncoder();
      commands.copyTextureToBuffer({texture: target}, {buffer: copy, bytesPerRow}, [canvas.width, canvas.height]);
      device.queue.submit([commands.finish()]); await copy.mapAsync(GPUMapMode.READ);
      const bytes = new Uint8Array(copy.getMappedRange()).slice(); copy.unmap(); copy.destroy();
      return {bytes, bytesPerRow, format};
    },
    close() { closed = true; buffer?.destroy(); device.destroy(); }
  };
  return renderer;
}
