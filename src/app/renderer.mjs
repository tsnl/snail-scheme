// A small WebGPU renderer for (lofi app) frames: a few flat-shaded meshes,
// drawn as instances with a position, scale, yaw and color. Batches keep
// their instance buffers until the application changes their version.

const shaderSource = `
struct Uniforms { viewProjection: mat4x4f, light: vec4f }
@group(0) @binding(0) var<uniform> uniforms: Uniforms;

struct Varyings {
  @builtin(position) position: vec4f,
  @location(0) color: vec3f,
  @location(1) normal: vec3f,
}

@vertex fn vertex_main(@location(0) position: vec3f, @location(1) normal: vec3f,
                       @location(2) offset: vec4f, @location(3) scale: vec4f,
                       @location(4) color: vec4f) -> Varyings {
  let c = cos(offset.w);
  let s = sin(offset.w);
  let p = position * scale.xyz;
  let n = normal / scale.xyz;
  var out: Varyings;
  out.position = uniforms.viewProjection * vec4f(c * p.x + s * p.z + offset.x, p.y + offset.y, c * p.z - s * p.x + offset.z, 1.0);
  out.normal = vec3f(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
  out.color = color.rgb;
  return out;
}

@fragment fn fragment_main(input: Varyings) -> @location(0) vec4f {
  let light = max(dot(normalize(input.normal), normalize(uniforms.light.xyz)), 0.0);
  return vec4f(input.color * (0.4 + 0.6 * light), 1.0);
}`;

// ---- Meshes ----

// Each mesh stands on y = 0 with unit size; faces have their own vertices so
// shading stays flat. Vertices are position then normal.
function face(vertices, indices, corners) {
  const [a, b, c] = corners;
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  const normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  const base = vertices.length / 6;
  for (const corner of corners) vertices.push(...corner, ...normal);
  for (let i = 1; i + 1 < corners.length; i++) indices.push(base, base + i, base + i + 1);
}

function prism(sides, top) {
  const vertices = [], indices = [];
  // A square's corners lie on a larger circle, so a box spans the unit cell.
  const radius = sides === 4 ? Math.SQRT1_2 : 0.5;
  const ring = y => Array.from({length: sides}, (_, i) => {
    const angle = (2 * Math.PI * (i + 0.5)) / sides;
    return [radius * Math.cos(angle), y, radius * Math.sin(angle)];
  });
  const bottom = ring(0), upper = ring(1);
  for (let i = 0; i < sides; i++) {
    const j = (i + 1) % sides;
    if (top) face(vertices, indices, [bottom[i], upper[i], upper[j], bottom[j]]);
    else face(vertices, indices, [bottom[i], [0, 1, 0], bottom[j]]);
  }
  face(vertices, indices, [...bottom]);
  if (top) face(vertices, indices, [...upper].reverse());
  return {vertices, indices};
}

function sphere() {
  const vertices = [], indices = [], rows = 6, columns = 10;
  const point = (row, column) => {
    const phi = (Math.PI * row) / rows, theta = (2 * Math.PI * column) / columns;
    return [0.5 * Math.sin(phi) * Math.cos(theta), 0.5 + 0.5 * Math.cos(phi), 0.5 * Math.sin(phi) * Math.sin(theta)];
  };
  for (let row = 0; row < rows; row++)
    for (let column = 0; column < columns; column++)
      face(vertices, indices, [point(row, column), point(row, column + 1), point(row + 1, column + 1), point(row + 1, column)]
        .filter((corner, index, all) => all.findIndex(other => other.every((v, k) => Math.abs(v - corner[k]) < 1e-9)) === index));
  return {vertices, indices};
}

// The order matches `mesh-index` in lib/lofi/app.sld.
const meshes = [prism(4, true), prism(4, false), prism(6, true), sphere(), prism(4, true)];

// ---- Matrices ----

function lookAt(eye, target) {
  const sub = (a, b) => a.map((v, i) => v - b[i]);
  const norm = v => { const l = Math.hypot(...v); return v.map(x => x / l); };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const f = norm(sub(target, eye)), r = norm(cross(f, [0, 1, 0])), u = cross(r, f);
  return [r[0], u[0], -f[0], 0, r[1], u[1], -f[1], 0, r[2], u[2], -f[2], 0, -dot(r, eye), -dot(u, eye), dot(f, eye), 1];
}

function perspective(fov, aspect, near, far) {
  const f = 1 / Math.tan(fov / 2);
  return [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, far / (near - far), -1, 0, 0, (near * far) / (near - far), 0];
}

function multiply(a, b) {
  const out = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++)
    for (let k = 0; k < 4; k++) out[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return out;
}

// ---- Renderer ----

export async function createRenderer(canvas) {
  if (!navigator.gpu) throw new Error('this browser does not support WebGPU');
  const adapter = await navigator.gpu.requestAdapter();
  const device = await adapter.requestDevice();
  const context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque'});
  const module = device.createShaderModule({code: shaderSource});
  const pipeline = device.createRenderPipeline({
    layout: 'auto',
    vertex: {module, entryPoint: 'vertex_main', buffers: [
      {arrayStride: 24, attributes: [{shaderLocation: 0, offset: 0, format: 'float32x3'},
                                     {shaderLocation: 1, offset: 12, format: 'float32x3'}]},
      {arrayStride: 48, stepMode: 'instance', attributes: [{shaderLocation: 2, offset: 0, format: 'float32x4'},
                                                           {shaderLocation: 3, offset: 16, format: 'float32x4'},
                                                           {shaderLocation: 4, offset: 32, format: 'float32x4'}]}]},
    fragment: {module, entryPoint: 'fragment_main', targets: [{format}]},
    primitive: {topology: 'triangle-list', cullMode: 'none'},
    depthStencil: {format: 'depth24plus', depthWriteEnabled: true, depthCompare: 'less'},
  });
  const uniforms = device.createBuffer({size: 80, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  const bindGroup = device.createBindGroup({layout: pipeline.getBindGroupLayout(0), entries: [{binding: 0, resource: {buffer: uniforms}}]});
  const geometry = meshes.map(({vertices, indices}) => {
    const vertexBuffer = device.createBuffer({size: vertices.length * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
    device.queue.writeBuffer(vertexBuffer, 0, new Float32Array(vertices));
    const indexBuffer = device.createBuffer({size: Math.ceil(indices.length * 2 / 4) * 4, usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST});
    const indexData = new Uint16Array(Math.ceil(indices.length / 2) * 2);
    indexData.set(indices);
    device.queue.writeBuffer(indexBuffer, 0, indexData);
    return {vertexBuffer, indexBuffer, count: indices.length};
  });
  const batches = new Map();
  let depth = null;

  // Groups a batch's instances by mesh into GPU buffers.
  function upload(batch) {
    batches.get(batch.key)?.parts.forEach(part => part.buffer.destroy());
    const groups = meshes.map(() => []);
    for (let i = 0; i < batch.items.length; i += 9) {
      const [mesh, x, y, z, sx, sy, sz, yaw, color] = batch.items.slice(i, i + 9);
      groups[mesh].push(x, y, z, yaw, sx, sy, sz, 0, ((color >> 16) & 255) / 255, ((color >> 8) & 255) / 255, (color & 255) / 255, 1);
    }
    const parts = groups.flatMap((values, mesh) => {
      if (!values.length) return [];
      const buffer = device.createBuffer({size: values.length * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
      device.queue.writeBuffer(buffer, 0, new Float32Array(values));
      return [{mesh, buffer, count: values.length / 12}];
    });
    batches.set(batch.key, {version: batch.version, parts});
  }

  function resize() {
    const width = Math.max(1, Math.round(canvas.clientWidth * devicePixelRatio));
    const height = Math.max(1, Math.round(canvas.clientHeight * devicePixelRatio));
    if (canvas.width !== width || canvas.height !== height || !depth) {
      canvas.width = width; canvas.height = height;
      depth?.destroy();
      depth = device.createTexture({size: [width, height], format: 'depth24plus', usage: GPUTextureUsage.RENDER_ATTACHMENT});
    }
  }

  return {
    hasBatch(key, version) { return batches.get(key)?.version === version; },
    draw(frame) {
      for (const batch of frame.batches) if (batch.items) upload(batch);
      resize();
      const matrix = multiply(perspective(0.8, canvas.width / canvas.height, 0.1, 500), lookAt(frame.eye, frame.target));
      device.queue.writeBuffer(uniforms, 0, new Float32Array([...matrix, 0.4, 1, 0.3, 0]));
      const background = frame.background;
      const encoder = device.createCommandEncoder();
      const pass = encoder.beginRenderPass({
        colorAttachments: [{view: context.getCurrentTexture().createView(), loadOp: 'clear', storeOp: 'store',
                            clearValue: {r: ((background >> 16) & 255) / 255, g: ((background >> 8) & 255) / 255, b: (background & 255) / 255, a: 1}}],
        depthStencilAttachment: {view: depth.createView(), depthLoadOp: 'clear', depthStoreOp: 'store', depthClearValue: 1},
      });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, bindGroup);
      for (const {key} of frame.batches) {
        for (const part of batches.get(key)?.parts ?? []) {
          const mesh = geometry[part.mesh];
          pass.setVertexBuffer(0, mesh.vertexBuffer);
          pass.setVertexBuffer(1, part.buffer);
          pass.setIndexBuffer(mesh.indexBuffer, 'uint16');
          pass.drawIndexed(mesh.count, part.count);
        }
      }
      pass.end();
      device.queue.submit([encoder.finish()]);
    },
  };
}
