// A WebGPU device for tests without a browser, which draws nothing and
// remembers what each frame did: the labels of the bind groups set, and
// the bytes last written to each labeled buffer. Pass `open` to
// `createGpu` of host/browser/gpu.mjs; `frames` holds each submitted frame,
// and `failing` makes the next submit throw.
export function fakeGpu() {
  const fake = {frames: [], failing: false};
  let frame = {groups: [], writes: new Map()};
  const object = descriptor => ({label: descriptor?.label ?? '', destroy() {}, getBindGroupLayout: () => ({}),
                                 createView: () => ({})});
  const pass = () => ({
    setBindGroup(index, group) { frame.groups.push(group.label); },
    setPipeline() {}, setVertexBuffer() {}, setIndexBuffer() {}, setScissorRect() {},
    dispatchWorkgroups() {}, draw() {}, drawIndexed() {}, drawIndexedIndirect() {}, end() {},
  });
  const device = {
    limits: {maxStorageBufferBindingSize: 128 * 1024 * 1024},
    createBuffer: object, createTexture: object, createSampler: object, createShaderModule: object,
    createComputePipeline: object, createRenderPipeline: object, createBindGroup: object,
    createCommandEncoder: () => ({beginRenderPass: pass, beginComputePass: pass, copyBufferToBuffer() {}, copyTextureToBuffer() {},
                                  copyTextureToTexture() {}, finish: () => ({})}),
    queue: {
      writeBuffer(buffer, offset, data) { frame.writes.set(buffer.label, new Uint8Array(data)); },
      writeTexture() {},
      submit() {
        if (fake.failing) throw new Error('a deliberate presentation trap');
        fake.frames.push(frame);
        frame = {groups: [], writes: new Map()};
      },
    },
  };
  fake.open = async canvas => ({device, format: 'bgra8unorm', optional: [],
    context: {getCurrentTexture: () => ({width: canvas.width, height: canvas.height, ...object()})}});
  return fake;
}

// A canvas of the given size, as createGpu reads it.
export function fakeCanvas(width, height) {
  return {clientWidth: width, clientHeight: height, width, height};
}
