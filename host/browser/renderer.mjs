// A small WebGPU renderer for (snail shell app) frames. Meshes and sprites are both
// instances drawn by one shader in the metallic-roughness model: each has a
// position, scale, yaw, color, glow, metalness, roughness and a region of a
// texture (a 1x1 white one when it has none), and an upright instance also
// turns to face the camera. Each instance carries where it was, and the
// frame's motion moves it toward where it is, so animation between updates
// needs no new instances; a texture strip steps through its frames by the
// clock. Batches keep their instance buffers until the application changes
// their version; their style (opacity, or a revealed disc) is a uniform set
// every frame.

const shaderSource = `
struct Globals { viewProjection: mat4x4f, light: vec4f, params: vec4f, eye: vec4f, forward: vec4f }
struct Style { opacity: f32, centerX: f32, centerZ: f32, radius: f32 }
@group(0) @binding(0) var<uniform> globals: Globals;
@group(1) @binding(0) var<uniform> style: Style;
@group(2) @binding(0) var colorMap: texture_2d<f32>;
@group(2) @binding(1) var nearest: sampler;

const PI = 3.14159265;

struct Varyings {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
  @location(1) normal: vec3f,
  @location(2) world: vec3f,
  @location(3) texel: vec2f,
  @location(4) material: vec2f,
}

// params: ambient light, motion, the clock in milliseconds, and 1 for an
// orthographic camera. An instance's start.w is 1 when it is upright, its
// region is in texels, and its material is metalness, roughness, then a
// strip's frame count and milliseconds per frame.
@vertex fn vertex_main(@location(0) position: vec3f, @location(1) normal: vec3f, @location(2) uv: vec2f,
                       @location(3) offset: vec4f, @location(4) scale: vec4f, @location(5) color: vec4f,
                       @location(6) start: vec4f, @location(7) region: vec4f, @location(8) material: vec4f) -> Varyings {
  let back = normalize(-globals.forward.xz + vec2f(0.0, 1e-6));
  let upright = start.w > 0.5;
  let yaw = offset.w + select(0.0, atan2(back.x, back.y), upright);
  let c = cos(yaw);
  let s = sin(yaw);
  let p = position * scale.xyz;
  let n = normal / scale.xyz;
  let origin = mix(start.xyz, offset.xyz, globals.params.y);
  let world = vec3f(c * p.x + s * p.z, p.y, c * p.z - s * p.x) + origin;
  let step = floor(globals.params.z / max(material.w, 1.0)) % max(material.z, 1.0);
  var out: Varyings;
  out.position = globals.viewProjection * vec4f(world, 1.0);
  out.normal = select(vec3f(c * n.x + s * n.z, n.y, c * n.z - s * n.x), vec3f(back.x, 0.0, back.y), upright);
  out.color = vec4f(color.rgb, scale.w);
  out.world = world;
  out.texel = region.xy + vec2f(step * region.z, 0.0) + uv * region.zw;
  out.material = material.xy;
  return out;
}

// Cook-Torrance with a GGX distribution, Smith-Schlick shadowing and
// Schlick's Fresnel under the sun, and the ambient light on the diffuse
// color and a metal's specular color. A dielectric reflects 4% at normal
// incidence. Faces are two-sided: one seen from behind is lit as its front.
// Glow mixes toward the unlit color.
@fragment fn fragment_main(input: Varyings) -> @location(0) vec4f {
  let texture = textureSample(colorMap, nearest, input.texel / vec2f(textureDimensions(colorMap)));
  if (texture.a < 0.5) { discard; }
  if (style.radius >= 0.0 && distance(input.world.xz, vec2f(style.centerX, style.centerZ)) > style.radius) { discard; }
  let base = input.color.rgb * texture.rgb;
  let metalness = input.material.x;
  let roughness = clamp(input.material.y, 0.04, 1.0);
  let view = select(normalize(globals.eye.xyz - input.world), -normalize(globals.forward.xyz), globals.params.w > 0.5);
  let front = normalize(input.normal);
  let n = select(front, -front, dot(front, view) < 0.0);
  let l = normalize(globals.light.xyz);
  let h = normalize(l + view);
  let nl = max(dot(n, l), 0.0);
  let nv = max(dot(n, view), 1e-4);
  let nh = max(dot(n, h), 0.0);
  let vh = max(dot(view, h), 0.0);
  let f0 = mix(vec3f(0.04), base, metalness);
  let fresnel = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);
  let a2 = roughness * roughness * roughness * roughness;
  let distribution = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
  let k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
  let shadowing = nv / (nv * (1.0 - k) + k) * nl / (nl * (1.0 - k) + k);
  let specular = distribution * shadowing * fresnel / (4.0 * nv * max(nl, 1e-4));
  let diffuse = (1.0 - metalness) * base;
  let lit = (diffuse + PI * specular) * globals.light.w * nl + globals.params.x * (diffuse + metalness * f0);
  return vec4f(mix(lit, base, input.color.a), style.opacity);
}`;

// ---- Meshes ----

// Each mesh stands on y = 0 with unit size; faces have their own vertices so
// shading stays flat. Vertices are position, normal and texture
// coordinates, which project the unit cell onto the face's main plane, so
// each face shows the texture's whole region, top up on upright faces.
function face(vertices, indices, corners) {
  const [a, b, c] = corners;
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  const normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  const [nx, ny, nz] = normal.map(Math.abs);
  const project = ([x, y, z]) => ny >= nx && ny >= nz ? [x + 0.5, z + 0.5] : nx >= nz ? [z + 0.5, 1 - y] : [x + 0.5, 1 - y];
  const base = vertices.length / 8;
  for (const corner of corners) vertices.push(...corner, ...normal, ...project(corner));
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

// An upright unit square facing +z, standing on y = 0: a sprite.
function quad() {
  const vertices = [], indices = [];
  face(vertices, indices, [[-0.5, 0, 0], [0.5, 0, 0], [0.5, 1, 0], [-0.5, 1, 0]]);
  return {vertices, indices};
}

// The order matches `mesh-index` in src/snail/shell/app.sld.
const meshes = [prism(4, true), prism(4, false), prism(6, true), sphere(), tile(), tetrahedron(), octahedron(), quad()];

// ---- Matrices ----

function lookAt(eye, target) {
  const sub = (a, b) => a.map((v, i) => v - b[i]);
  const norm = v => { const l = Math.hypot(...v); return v.map(x => x / l); };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  // Looking straight down, the top of the screen is -z, as `screen-axes`
  // in src/snail/shell/app.sld says.
  const f = norm(sub(target, eye)), sky = Math.abs(f[1]) > 0.999 ? [0, 0, -1] : [0, 1, 0];
  const r = norm(cross(f, sky)), u = cross(r, f);
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

// A camera's kind is 0 for perspective and 1 for orthographic, as
// `render-camera` in src/snail/shell/app.sld numbers them. An orthographic camera
// sees everything between a plane behind the eye and one well past the
// target, so zooming never clips the ground.
function projection(camera, aspect) {
  if (camera.kind === 0) return perspective(camera.value, aspect, 0.1, 500);
  const distance = Math.hypot(...camera.eye.map((v, i) => v - camera.target[i]));
  return orthographic(camera.value, aspect, -distance, distance * 4);
}

// ---- Instances ----

// An instance is six vectors: position and yaw, scale and glow, color, where
// it was and whether it is upright, its texture region in texels, and its
// material with the strip's frame count and period.
const INSTANCE_FLOATS = 24;

// The values `instance` and then `surface` send, as host.mjs collects them.
function instanceValues([mesh, x, y, z, sx, sy, sz, yaw, color, glow, fx, fy, fz,
                         metalness, roughness, upright, picture, rx, ry, rw, rh, frames, period]) {
  const region = picture < 0 ? [0, 0, 1, 1] : [rx, ry, rw, rh];
  return [x, y, z, yaw, sx, sy, sz, glow, ((color >> 16) & 255) / 255, ((color >> 8) & 255) / 255, (color & 255) / 255, 1,
          fx, fy, fz, upright, ...region, metalness, roughness, frames, period];
}

// ---- Pipelines ----

// One shader draws every batch through bind groups for the frame's globals,
// a batch's style, and a texture with its sampler. Solid batches write
// depth; translucent ones blend over them and leave depth alone.
function createPipelines(device, format) {
  const module = device.createShaderModule({code: shaderSource});
  const layouts = {
    globals: device.createBindGroupLayout({entries: [{binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: {}}]}),
    style: device.createBindGroupLayout({entries: [{binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: {}}]}),
    texture: device.createBindGroupLayout({entries: [
      {binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: {}},
      {binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: {}}]}),
  };
  const layout = device.createPipelineLayout({bindGroupLayouts: [layouts.globals, layouts.style, layouts.texture]});
  const pipeline = translucent => device.createRenderPipeline({
    layout,
    vertex: {module, entryPoint: 'vertex_main', buffers: [
      {arrayStride: 32, attributes: [{shaderLocation: 0, offset: 0, format: 'float32x3'},
                                     {shaderLocation: 1, offset: 12, format: 'float32x3'},
                                     {shaderLocation: 2, offset: 24, format: 'float32x2'}]},
      {arrayStride: INSTANCE_FLOATS * 4, stepMode: 'instance', attributes: [0, 1, 2, 3, 4, 5].map(i => (
        {shaderLocation: 3 + i, offset: 16 * i, format: 'float32x4'}))}]},
    fragment: {module, entryPoint: 'fragment_main', targets: [{format, blend: translucent ? {
      color: {srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha'},
      alpha: {srcFactor: 'one', dstFactor: 'one-minus-src-alpha'}} : undefined}]},
    primitive: {topology: 'triangle-list', cullMode: 'none'},
    depthStencil: {format: 'depth24plus', depthWriteEnabled: !translucent, depthCompare: 'less'},
  });
  return {layouts, solid: pipeline(false), translucent: pipeline(true)};
}

// Each mesh's vertices and indices, in buffers of their own. The indices
// are padded to a whole number of four-byte words, as writeBuffer needs.
function uploadMeshes(device) {
  return meshes.map(({vertices, indices}) => {
    const vertexBuffer = device.createBuffer({size: vertices.length * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
    device.queue.writeBuffer(vertexBuffer, 0, new Float32Array(vertices));
    const indexData = new Uint16Array(Math.ceil(indices.length / 2) * 2);
    indexData.set(indices);
    const indexBuffer = device.createBuffer({size: indexData.byteLength, usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST});
    device.queue.writeBuffer(indexBuffer, 0, indexData);
    return {vertexBuffer, indexBuffer, count: indices.length};
  });
}

// ---- Frames ----

// The globals uniform: the view-projection, the light's direction and the
// sun, then ambient light, motion, the clock and the camera's kind, then
// the eye and the direction it looks.
function frameGlobals(frame, aspect, clock) {
  const {eye, target} = frame.camera;
  const matrix = multiply(projection(frame.camera, aspect), lookAt(eye, target));
  const length = Math.hypot(...target.map((v, i) => v - eye[i]));
  const forward = target.map((v, i) => (v - eye[i]) / length);
  const {direction, sun, ambient} = frame.light;
  return new Float32Array([...matrix, ...direction, sun, ambient, frame.motion, clock, frame.camera.kind, ...eye, 0, ...forward, 0]);
}

// A 0xRRGGBB color as WebGPU clears to it.
function clearColor(color) {
  return {r: ((color >> 16) & 255) / 255, g: ((color >> 8) & 255) / 255, b: (color & 255) / 255, a: 1};
}

// ---- Renderer ----

export async function createRenderer(canvas, pictures) {
  if (!navigator.gpu) throw new Error('this browser does not support WebGPU');
  const adapter = await navigator.gpu.requestAdapter();
  const device = await adapter.requestDevice();
  device.addEventListener('uncapturederror', event => console.error('WebGPU:', event.error.message));
  const context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque'});
  const pipelines = createPipelines(device, format), geometry = uploadMeshes(device);
  const globals = device.createBuffer({size: 128, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  const globalGroup = device.createBindGroup({layout: pipelines.layouts.globals, entries: [{binding: 0, resource: {buffer: globals}}]});
  const batches = new Map();
  let depth = null;

  // ---- Textures ----

  // Pixel art stays sharp: textures are sampled at the nearest texel.
  const nearest = device.createSampler({magFilter: 'nearest', minFilter: 'nearest'});
  const textureGroup = texture => device.createBindGroup({layout: pipelines.layouts.texture, entries: [
    {binding: 0, resource: texture.createView()}, {binding: 1, resource: nearest}]});
  const white = device.createTexture({size: [1, 1], format: 'rgba8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST});
  device.queue.writeTexture({texture: white}, new Uint8Array([255, 255, 255, 255]), {bytesPerRow: 4}, [1, 1]);
  const whiteGroup = textureGroup(white);
  const textures = new Map();

  // The bind group for a picture, uploaded again whenever the picture store
  // composes a new version; null until the picture is ready.
  function pictureGroup(key) {
    if (key < 0) return whiteGroup;
    const picture = pictures.get(key);
    if (!picture) return null;
    let entry = textures.get(key);
    if (entry?.picture !== picture) {
      entry?.texture.destroy();
      const texture = device.createTexture({size: [picture.canvas.width, picture.canvas.height], format: 'rgba8unorm',
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT});
      device.queue.copyExternalImageToTexture({source: picture.canvas}, {texture}, [picture.canvas.width, picture.canvas.height]);
      entry = {picture, texture, group: textureGroup(texture)};
      textures.set(key, entry);
    }
    return entry.group;
  }

  // ---- Batches ----

  // A batch's style uniform and its instances grouped by mesh and picture.
  // Buffers only grow, so a batch that changes every update reuses them.
  function batchState(key) {
    let state = batches.get(key);
    if (!state) {
      const style = device.createBuffer({size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
      state = {version: null, style, group: device.createBindGroup({layout: pipelines.layouts.style, entries: [{binding: 0, resource: {buffer: style}}]}),
               parts: new Map()};
      batches.set(key, state);
    }
    return state;
  }

  function upload(batch) {
    const state = batchState(batch.key);
    const groups = new Map();
    for (const values of batch.items) {
      const id = `${values[0]} ${values[16]}`;
      if (!groups.has(id)) groups.set(id, {mesh: values[0], picture: values[16], values: []});
      groups.get(id).values.push(...instanceValues(values));
    }
    for (const part of state.parts.values()) part.count = 0;
    for (const [id, {mesh, picture, values}] of groups) {
      const part = state.parts.get(id) ?? {mesh, picture, buffer: null, capacity: 0, count: 0};
      if (values.length > part.capacity) {
        part.buffer?.destroy();
        part.capacity = Math.max(values.length, part.capacity * 2);
        part.buffer = device.createBuffer({size: part.capacity * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST});
      }
      device.queue.writeBuffer(part.buffer, 0, new Float32Array(values));
      part.count = values.length / INSTANCE_FLOATS;
      state.parts.set(id, part);
    }
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

  // Instances whose picture is not composed yet wait, undrawn.
  function drawBatches(pass, list) {
    for (const batch of list) {
      const state = batches.get(batch.key);
      pass.setBindGroup(1, state.group);
      for (const part of state.parts.values()) {
        const group = part.count ? pictureGroup(part.picture) : null;
        if (!group) continue;
        const shape = geometry[part.mesh];
        pass.setBindGroup(2, group);
        pass.setVertexBuffer(0, shape.vertexBuffer);
        pass.setVertexBuffer(1, part.buffer);
        pass.setIndexBuffer(shape.indexBuffer, 'uint16');
        pass.drawIndexed(shape.count, part.count);
      }
    }
  }

  // Solid batches first, then translucent ones over them.
  function encodePass(frame) {
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginRenderPass({
      colorAttachments: [{view: context.getCurrentTexture().createView(), loadOp: 'clear', storeOp: 'store', clearValue: clearColor(frame.background)}],
      depthStencilAttachment: {view: depth.createView(), depthLoadOp: 'clear', depthStoreOp: 'store', depthClearValue: 1},
    });
    pass.setBindGroup(0, globalGroup);
    pass.setPipeline(pipelines.solid);
    drawBatches(pass, frame.batches.filter(batch => batch.style[0] >= 1));
    pass.setPipeline(pipelines.translucent);
    drawBatches(pass, frame.batches.filter(batch => batch.style[0] < 1));
    pass.end();
    return encoder.finish();
  }

  const started = performance.now();

  return {
    hasBatch(key, version) { return batches.get(key)?.version === version; },
    // Another module may number its batches the same way, so after a module
    // is replaced, every batch is asked for again; the buffers are kept.
    forget() { for (const state of batches.values()) state.version = null; },
    draw(frame) {
      for (const batch of frame.batches) {
        if (batch.items) upload(batch);
        device.queue.writeBuffer(batchState(batch.key).style, 0, new Float32Array(batch.style));
      }
      resize();
      device.queue.writeBuffer(globals, 0, frameGlobals(frame, canvas.width / canvas.height, (performance.now() - started) % 3600000));
      device.queue.submit([encodePass(frame)]);
    },
  };
}
