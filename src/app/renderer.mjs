// A small WebGPU renderer for (lofi app) frames: flat-shaded meshes drawn
// as instances with a position, scale, yaw, color and glow. Each instance
// also carries where it was, and the frame's motion moves it toward where it
// is, so animation between updates needs no new instances. Batches keep
// their instance buffers until the application changes their version; their
// style (opacity, or a revealed disc) is a uniform set every frame.

const shaderSource = `
struct Globals { viewProjection: mat4x4f, light: vec4f, params: vec4f }
struct Style { opacity: f32, centerX: f32, centerZ: f32, radius: f32 }
@group(0) @binding(0) var<uniform> globals: Globals;
@group(1) @binding(0) var<uniform> style: Style;

struct Varyings {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
  @location(1) normal: vec3f,
  @location(2) ground: vec2f,
}

@vertex fn vertex_main(@location(0) position: vec3f, @location(1) normal: vec3f,
                       @location(2) offset: vec4f, @location(3) scale: vec4f,
                       @location(4) color: vec4f, @location(5) start: vec4f) -> Varyings {
  let c = cos(offset.w);
  let s = sin(offset.w);
  let p = position * scale.xyz;
  let n = normal / scale.xyz;
  let origin = mix(start.xyz, offset.xyz, globals.params.y);
  let world = vec3f(c * p.x + s * p.z, p.y, c * p.z - s * p.x) + origin;
  var out: Varyings;
  out.position = globals.viewProjection * vec4f(world, 1.0);
  out.normal = vec3f(c * n.x + s * n.z, n.y, c * n.z - s * n.x);
  out.color = vec4f(color.rgb, scale.w);
  out.ground = world.xz;
  return out;
}

@fragment fn fragment_main(input: Varyings) -> @location(0) vec4f {
  if (style.radius >= 0.0 && distance(input.ground, vec2f(style.centerX, style.centerZ)) > style.radius) { discard; }
  let facing = max(dot(normalize(input.normal), normalize(globals.light.xyz)), 0.0);
  let lit = globals.params.x + globals.light.w * facing;
  return vec4f(input.color.rgb * mix(lit, 1.0, input.color.a), style.opacity);
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

function tile() {
  const vertices = [], indices = [];
  face(vertices, indices, [[-0.5, 0, -0.5], [-0.5, 0, 0.5], [0.5, 0, 0.5], [0.5, 0, -0.5]]);
  return {vertices, indices};
}

// Solids from triangular faces, wound so their normals face outward.
function solid(corners, faces) {
  const vertices = [], indices = [];
  for (const [a, b, c] of faces) face(vertices, indices, [corners[a], corners[b], corners[c]]);
  return {vertices, indices};
}

function tetrahedron() {
  const r = 0.5;
  const corners = [[0, 1, 0], [r, 0, 0], [-r / 2, 0, r * 0.866], [-r / 2, 0, -r * 0.866]];
  return solid(corners, [[0, 2, 1], [0, 3, 2], [0, 1, 3], [1, 2, 3]]);
}

function octahedron() {
  const corners = [[0, 1, 0], [0.5, 0.5, 0], [0, 0.5, 0.5], [-0.5, 0.5, 0], [0, 0.5, -0.5], [0, 0, 0]];
  return solid(corners, [[0, 2, 1], [0, 3, 2], [0, 4, 3], [0, 1, 4], [5, 1, 2], [5, 2, 3], [5, 3, 4], [5, 4, 1]]);
}

// The order matches `mesh-index` in lib/lofi/app.sld.
const meshes = [prism(4, true), prism(4, false), prism(6, true), sphere(), tile(), tetrahedron(), octahedron()];

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

// Depth runs from 0 at `near` to 1 at `far`, as WebGPU expects.
function orthographic(height, aspect, near, far) {
  const y = 2 / height, x = y / aspect, z = 1 / (near - far);
  return [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, near * z, 1];
}

function multiply(a, b) {
  const out = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++)
    for (let k = 0; k < 4; k++) out[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return out;
}

// An orthographic camera sees everything between a plane behind the eye
// and one well past the target, so zooming never clips the ground.
function projection(camera, aspect) {
  if (camera.kind === 0) return perspective(camera.value, aspect, 0.1, 500);
  const distance = Math.hypot(...camera.eye.map((v, i) => v - camera.target[i]));
  return orthographic(camera.value, aspect, -distance, distance * 4);
}

// ---- Renderer ----

const INSTANCE_FLOATS = 16;

export async function createRenderer(canvas) {
  if (!navigator.gpu) throw new Error('this browser does not support WebGPU');
  const adapter = await navigator.gpu.requestAdapter();
  const device = await adapter.requestDevice();
  device.addEventListener('uncapturederror', event => console.error('WebGPU:', event.error.message));
  const context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque'});
  const module = device.createShaderModule({code: shaderSource});
  const globalLayout = device.createBindGroupLayout({entries: [{binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: {}}]});
  const styleLayout = device.createBindGroupLayout({entries: [{binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: {}}]});
  const layout = device.createPipelineLayout({bindGroupLayouts: [globalLayout, styleLayout]});
  const pipeline = translucent => device.createRenderPipeline({
    layout,
    vertex: {module, entryPoint: 'vertex_main', buffers: [
      {arrayStride: 24, attributes: [{shaderLocation: 0, offset: 0, format: 'float32x3'},
                                     {shaderLocation: 1, offset: 12, format: 'float32x3'}]},
      {arrayStride: INSTANCE_FLOATS * 4, stepMode: 'instance', attributes: [0, 1, 2, 3].map(i => (
        {shaderLocation: 2 + i, offset: 16 * i, format: 'float32x4'}))}]},
    fragment: {module, entryPoint: 'fragment_main', targets: [{format, blend: translucent ? {
      color: {srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha'},
      alpha: {srcFactor: 'one', dstFactor: 'one-minus-src-alpha'}} : undefined}]},
    primitive: {topology: 'triangle-list', cullMode: 'none'},
    depthStencil: {format: 'depth24plus', depthWriteEnabled: !translucent, depthCompare: 'less'},
  });
  const pipelines = [pipeline(false), pipeline(true)];
  const globals = device.createBuffer({size: 96, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  const globalGroup = device.createBindGroup({layout: globalLayout, entries: [{binding: 0, resource: {buffer: globals}}]});
  const geometry = meshes.map(({vertices, indices}) => {
    const vertexBuffer = device.createBuffer({size: vertices.length * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
    device.queue.writeBuffer(vertexBuffer, 0, new Float32Array(vertices));
    const indexData = new Uint16Array(Math.ceil(indices.length / 2) * 2);
    indexData.set(indices);
    const indexBuffer = device.createBuffer({size: indexData.byteLength, usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST});
    device.queue.writeBuffer(indexBuffer, 0, indexData);
    return {vertexBuffer, indexBuffer, count: indices.length};
  });
  const batches = new Map();
  let depth = null;

  // A batch's style uniform and its instances grouped by mesh. Buffers only
  // grow, so a batch that changes every update reuses its memory.
  function batchState(key) {
    let state = batches.get(key);
    if (!state) {
      const style = device.createBuffer({size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
      state = {version: null, style, group: device.createBindGroup({layout: styleLayout, entries: [{binding: 0, resource: {buffer: style}}]}),
               parts: meshes.map(() => ({buffer: null, capacity: 0, count: 0}))};
      batches.set(key, state);
    }
    return state;
  }

  function upload(batch) {
    const state = batchState(batch.key);
    const groups = meshes.map(() => []);
    for (const [mesh, x, y, z, sx, sy, sz, yaw, color, glow, fx, fy, fz] of batch.items)
      groups[mesh].push(x, y, z, yaw, sx, sy, sz, glow, ((color >> 16) & 255) / 255, ((color >> 8) & 255) / 255, (color & 255) / 255, 1,
                        fx, fy, fz, 0);
    groups.forEach((values, mesh) => {
      const part = state.parts[mesh];
      if (values.length > part.capacity) {
        part.buffer?.destroy();
        part.capacity = Math.max(values.length, part.capacity * 2);
        part.buffer = device.createBuffer({size: part.capacity * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
      }
      if (values.length) device.queue.writeBuffer(part.buffer, 0, new Float32Array(values));
      part.count = values.length / INSTANCE_FLOATS;
    });
    state.version = batch.version;
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

  function drawBatches(pass, list) {
    for (const batch of list) {
      const state = batches.get(batch.key);
      pass.setBindGroup(1, state.group);
      state.parts.forEach((part, mesh) => {
        if (!part.count) return;
        const shape = geometry[mesh];
        pass.setVertexBuffer(0, shape.vertexBuffer);
        pass.setVertexBuffer(1, part.buffer);
        pass.setIndexBuffer(shape.indexBuffer, 'uint16');
        pass.drawIndexed(shape.count, part.count);
      });
    }
  }

  return {
    hasBatch(key, version) { return batches.get(key)?.version === version; },
    draw(frame) {
      for (const batch of frame.batches) {
        if (batch.items) upload(batch);
        device.queue.writeBuffer(batchState(batch.key).style, 0, new Float32Array(batch.style));
      }
      resize();
      const matrix = multiply(projection(frame.camera, canvas.width / canvas.height), lookAt(frame.camera.eye, frame.camera.target));
      const {direction, sun, ambient} = frame.light;
      device.queue.writeBuffer(globals, 0, new Float32Array([...matrix, ...direction, sun, ambient, frame.motion, 0, 0]));
      const background = frame.background;
      const encoder = device.createCommandEncoder();
      const pass = encoder.beginRenderPass({
        colorAttachments: [{view: context.getCurrentTexture().createView(), loadOp: 'clear', storeOp: 'store',
                            clearValue: {r: ((background >> 16) & 255) / 255, g: ((background >> 8) & 255) / 255, b: (background & 255) / 255, a: 1}}],
        depthStencilAttachment: {view: depth.createView(), depthLoadOp: 'clear', depthStoreOp: 'store', depthClearValue: 1},
      });
      pass.setBindGroup(0, globalGroup);
      pass.setPipeline(pipelines[0]);
      drawBatches(pass, frame.batches.filter(batch => batch.style[0] >= 1));
      pass.setPipeline(pipelines[1]);
      drawBatches(pass, frame.batches.filter(batch => batch.style[0] < 1));
      pass.end();
      device.queue.submit([encoder.finish()]);
    },
  };
}
