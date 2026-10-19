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
  const [pipeline, translucent, revealing] = await Promise.all([[false,true],[true,false],[true,true]]
    .map(([alpha,depth]) => device.createRenderPipelineAsync(descriptor(module,format,alpha,depth))));
  return {pipeline, translucent, revealing};
}
function descriptor(module, format, translucent, depthWriteEnabled) {
  return {layout: 'auto', vertex: {module, entryPoint: 'vertex_main', buffers: [{arrayStride: 40, attributes: [
    {shaderLocation: 0, offset: 0, format: 'float32x3'}, {shaderLocation: 1, offset: 12, format: 'float32x3'},
    {shaderLocation: 2, offset: 24, format: 'float32x4'}]},
    {arrayStride:48,stepMode:'instance',attributes:[
      {shaderLocation:3,offset:0,format:'float32x4'}, {shaderLocation:4,offset:16,format:'float32x4'},
      {shaderLocation:5,offset:32,format:'float32x4'}]},
    {arrayStride:36,stepMode:'instance',attributes:[
      {shaderLocation:6,offset:0,format:'float32x3'}, {shaderLocation:7,offset:12,format:'float32x3'},
      {shaderLocation:8,offset:24,format:'float32x3'}]},
    {arrayStride:48,stepMode:'instance',attributes:[
      {shaderLocation:9,offset:0,format:'float32x4'}, {shaderLocation:10,offset:16,format:'float32x4'},
      {shaderLocation:11,offset:32,format:'float32x4'}]}]},
    fragment: {module, entryPoint: 'fragment_main', targets: [{format, ...(translucent ? {blend: {color: {srcFactor:'src-alpha',dstFactor:'one-minus-src-alpha'}, alpha: {srcFactor:'one',dstFactor:'one-minus-src-alpha'}}} : {})}]},
    primitive: {topology: 'triangle-list', cullMode: 'none'},
    depthStencil: {format: 'depth24plus', depthWriteEnabled, depthCompare: 'less'}};
}
function growBuffer(device, buffer, size, usage) {
  if (buffer && buffer.size >= size) return buffer;
  const next = device.createBuffer({size: Math.max(4096, size * 2), usage: usage | GPUBufferUsage.COPY_DST});
  buffer?.destroy(); return next;
}
function depthTexture(device, width, height) {
  return device.createTexture({size: [width, height], format: 'depth24plus',
    usage: GPUTextureUsage.RENDER_ATTACHMENT});
}
function destroyGeometry(value) {
  value?.transforms?.destroy(); value?.normals?.destroy(); value?.previousTransforms?.destroy(); value?.uniform?.destroy();
}
function geometryKey(view, batch) { return view === undefined ? batch : `${view}:${batch}`; }
function destroyInset(view) {
  view.texture.destroy(); view.depth.destroy(); view.uniform.destroy();
}
function destroyMesh(value) { value.vertices.destroy(); value.indices.destroy(); }
function uploadData(device, buffer, values, usage) {
  const data = Float32Array.from(values), next = growBuffer(device,buffer,data.byteLength,usage);
  if (data.length) device.queue.writeBuffer(next,0,data);
  return next;
}
function motionFraction(batch, time) {
  return batch.source.duration ? Math.max(0, Math.min((time - batch.started) / batch.source.duration, 1)) : 1;
}
function sameReveal(left, right) {
  return ['x','y','radius','edge','duration'].every(key => left[key] === right[key]);
}
function revealUniform(clock) {
  // Quintic easing moves from a wholly invisible edge to the enclosing radius.
  // The exact endpoint disables the mask, avoiding floating-point residue.
  const {source,fraction:t} = clock, progress = t*t*t*(10+t*(-15+6*t));
  return [source.x,source.y,-source.edge/2+(source.radius+source.edge)*progress,
    t === 1 ? -1 : source.edge/2];
}

export async function createSceneRenderer(canvas, onError = () => {}) {
  if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser.');
  const adapter = await navigator.gpu.requestAdapter({powerPreference: 'high-performance'});
  if (!adapter) throw new Error('No WebGPU adapter is available.');
  const device = await adapter.requestDevice(), context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({device, format, alphaMode: 'opaque',
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC | GPUTextureUsage.COPY_DST});
  const uniform = device.createBuffer({size: 128, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST});
  let current, previous, depth, closed = false, lost = false, closing, uploads = 0, frames = 0;
  const geometry = new Map(), meshes = new Map(), insets = new Map(), pending = new Set();
  let latest, reveals = new Map(), meshUploads = 0, drawCalls = 0, instancedDraws = 0;
  device.addEventListener('uncapturederror', event => { if (!closed) onError(event.error); });
  device.lost.then(info => { lost = true; if (!closed) onError(new Error(`WebGPU device lost: ${info.message}`)); });
  function track(operation) {
    pending.add(operation);
    operation.finally(() => pending.delete(operation)).catch(() => {}); return operation;
  }
  function prepare(source) {
    if (closed || lost) return Promise.reject(new Error('3D renderer is closed'));
    return track(compile(device, source, format).then(({pipeline, translucent, revealing}) => {
      if (closed || lost) throw new Error('3D renderer closed during shader preparation');
      return {pipeline, translucent, revealing, bindings: device.createBindGroup({layout: pipeline.getBindGroupLayout(0),
        entries: [{binding: 0, resource: {buffer: uniform}}]})};
    }));
  }
  function batchUniform(batch, source) {
    if ((source.duration || (source.opacity ?? 1) < 1 || source.reveal) && !batch.uniform)
      batch.uniform = device.createBuffer({size:128,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
  }
  function uploadMesh(source) {
    const cached = meshes.get(source); if (cached) return cached;
    let vertices, indices;
    try {
      vertices = uploadData(device,undefined,source.vertices,GPUBufferUsage.VERTEX);
      const data = Uint32Array.from(source.indices);
      indices = growBuffer(device,undefined,data.byteLength,GPUBufferUsage.INDEX);
      if (data.length) device.queue.writeBuffer(indices,0,data);
      const mesh = {vertices,indices,count:data.length}; meshes.set(source,mesh); meshUploads++; return mesh;
    } catch (error) { vertices?.destroy(); indices?.destroy(); throw error; }
  }
  function upload(batch, time, view) {
    const key = geometryKey(view, batch.key); let stored = geometry.get(key);
    if (stored?.source === batch) return stored;
    stored ??= {};
    // Reveal metadata never uploads instances or restarts their motion clock.
    if (stored.source?.transforms === batch.transforms && stored.source?.normals === batch.normals &&
        stored.source?.draws === batch.draws && stored.source?.previous === batch.previous && stored.source?.duration === batch.duration) {
      batchUniform(stored,batch); stored.source = batch; return stored;
    }
    for (const draw of batch.draws) uploadMesh(draw.mesh);
    batchUniform(stored,batch);
    stored.transforms = uploadData(device,stored.transforms,batch.transforms,GPUBufferUsage.VERTEX);
    stored.normals = uploadData(device,stored.normals,batch.normals,GPUBufferUsage.VERTEX);
    if (batch.previous) stored.previousTransforms = uploadData(device,stored.previousTransforms,batch.previous,GPUBufferUsage.VERTEX);
    else { stored.previousTransforms?.destroy(); stored.previousTransforms = undefined; }
    stored.started = time; stored.fraction = batch.duration ? 0 : 1;
    stored.source = batch; stored.count = batch.draws.reduce((count,draw) => count + draw.mesh.indices.length * draw.count,0);
    geometry.set(key, stored); uploads++; return stored;
  }
  function resize() {
    if (depth?.width === canvas.width && depth?.height === canvas.height) return;
    const next = depthTexture(device, canvas.width, canvas.height);
    depth?.destroy(); depth = next;
  }
  function insetView(key, width, height) {
    let view = insets.get(key);
    if (!view) {
      view = {key, uniform: device.createBuffer({size:128,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST})};
      insets.set(key, view);
    }
    if (view.width !== width || view.height !== height) {
      view.texture?.destroy(); view.depth?.destroy(); view.width = width; view.height = height;
      view.texture = device.createTexture({size:[width,height],format,
        usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.COPY_SRC});
      view.depth = depthTexture(device,width,height);
    }
    if (view.pipeline !== current.pipeline) {
      view.pipeline = current.pipeline;
      view.bindings = device.createBindGroup({layout:current.pipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:view.uniform}}]});
    }
    return view;
  }
  // Each changing batch owns its uniform: queue writes happen before the one
  // render submission, so sharing a changing uniform would overwrite siblings.
  function batchBindings(batch, pipeline, scene, time, bindings) {
    if (!batch.uniform) return bindings;
    if (batch.pipeline !== pipeline) {
      batch.pipeline = pipeline;
      batch.bindings = device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:batch.uniform}}]});
    }
    const values = Float32Array.from(scene.uniforms);
    values[23] = (batch.source.opacity ?? 1) * (batch.source.pulse ? 0.72 + 0.28 * Math.sin((time % 1570.796327) * 0.004 - (batch.source.pulsePhase ?? 0)) : 1);
    values[24] = batch.fraction = motionFraction(batch, time);
    if (batch.source.reveal) values.set(revealUniform(reveals.get(batch.source.reveal.id)),28);
    device.queue.writeBuffer(batch.uniform, 0, values); return batch.bindings;
  }
  function drawBatch(pass, batch, scene, time, bindings) {
    const alpha = (batch.source.opacity ?? 1) < 1;
    const pipeline = alpha ? current.translucent : batch.source.reveal ? current.revealing : current.pipeline;
    pass.setPipeline(pipeline); pass.setBindGroup(0,batchBindings(batch,pipeline,scene,time,bindings));
    pass.setVertexBuffer(1,batch.transforms); pass.setVertexBuffer(2,batch.normals);
    pass.setVertexBuffer(3,batch.previousTransforms ?? batch.transforms);
    for (const draw of batch.source.draws) {
      const mesh = meshes.get(draw.mesh);
      pass.setVertexBuffer(0,mesh.vertices); pass.setIndexBuffer(mesh.indices,'uint32');
      pass.drawIndexed(mesh.count,draw.count,0,0,draw.first); drawCalls++;
      if (draw.count > 1) instancedDraws++;
    }
  }
  function drawView(commands, view, scene, logicalWidth, logicalHeight, time, present) {
    device.queue.writeBuffer(view.uniform, 0, Float32Array.from(scene.uniforms));
    const [r,g,b] = scene.background;
    // Each pass stores its single-sample color for presentation, inset copies or readback.
    const pass = commands.beginRenderPass({colorAttachments: [{view: view.texture.createView(),
      clearValue: {r, g, b, a: 1}, loadOp: 'clear', storeOp: 'store'}],
      depthStencilAttachment: {view: view.depth.createView(), depthClearValue: 1, depthLoadOp: 'clear', depthStoreOp: 'discard'}});
    pass.setPipeline(current.pipeline); pass.setBindGroup(0, view.bindings);
    if (scene.viewport) {
      const [x, y, width, height] = scene.viewport, sx = view.width / logicalWidth, sy = view.height / logicalHeight;
      const left = Math.max(0, Math.floor(x * sx)), top = Math.max(0, Math.floor(y * sy));
      const right = Math.min(view.width, Math.ceil((x + width) * sx)), bottom = Math.min(view.height, Math.ceil((y + height) * sy));
      pass.setViewport(left, top, Math.max(1, right - left), Math.max(1, bottom - top), 0, 1);
      pass.setScissorRect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    }
    // Batch order is explicit; previews are submitted after all opaque geometry.
    for (const source of scene.batches) {
      const batch = upload(source,time,view.key); present.add(batch);
      if (batch.count) drawBatch(pass,batch,scene,time,view.bindings);
    }
    pass.end();
  }
  function copyInset(commands, target, scene, logicalWidth, logicalHeight, time, present) {
    const [x,y,width,height] = scene.rect, sx = canvas.width/logicalWidth, sy = canvas.height/logicalHeight;
    const left = Math.floor(x*sx), top = Math.floor(y*sy);
    if (left >= canvas.width || top >= canvas.height) return false;
    const view = insetView(scene.key,Math.max(1,Math.round(width*sx)),Math.max(1,Math.round(height*sy)));
    drawView(commands,view,scene,width,height,time,present);
    commands.copyTextureToTexture({texture:view.texture},{texture:target,origin:[left,top]},
      [Math.min(view.width,canvas.width-left),Math.min(view.height,canvas.height-top)]);
    return true;
  }
  function checkTargetSizes(scene, logicalWidth, logicalHeight) {
    const sizes = [[canvas.width,canvas.height], ...(scene.insets ?? []).map(view =>
      [Math.max(1,Math.round(view.rect[2]*canvas.width/logicalWidth)),
        Math.max(1,Math.round(view.rect[3]*canvas.height/logicalHeight))])];
    if (sizes.some(size => size.some(value => !Number.isInteger(value) || value < 1 || value > device.limits.maxTextureDimension2D)))
      throw new Error('scene target exceeds the device texture dimensions');
  }
  // Presence in the complete frame owns a clock, even when its geometry is
  // empty or its inset is clipped. Cameras, uploads and pipelines do not own it.
  function frameReveals(scene, time) {
    const next = new Map();
    for (const view of [scene,...scene.insets ?? []]) for (const {reveal} of view.batches) if (reveal) {
      const clock = next.get(reveal.id) ?? reveals.get(reveal.id);
      if (clock && !sameReveal(clock.source,reveal)) throw new Error('inconsistent scene reveal identity');
      next.set(reveal.id,clock ?? {source:reveal,started:time-Math.min(reveal.elapsed,reveal.duration)});
    }
    for (const clock of next.values()) clock.fraction = Math.max(0,Math.min((time-clock.started)/clock.source.duration,1));
    return next;
  }
  function render(scene, logicalWidth, logicalHeight, time = performance.now()) {
    if (closed || lost || !current || !scene) return;
    if ((scene.insets?.length ?? 0) > 3) throw new Error('at most three scene insets are supported');
    checkTargetSizes(scene,logicalWidth,logicalHeight);
    reveals = frameReveals(scene,time);
    resize(); const target = context.getCurrentTexture(), commands = device.createCommandEncoder();
    const present = new Set(), visible = new Set(); drawCalls = instancedDraws = 0;
    drawView(commands,{texture:target,depth,uniform,bindings:current.bindings,width:canvas.width,height:canvas.height},
      scene,logicalWidth,logicalHeight,time,present);
    for (const inset of scene.insets ?? [])
      if (copyInset(commands,target,inset,logicalWidth,logicalHeight,time,present)) visible.add(inset.key);
    device.queue.submit([commands.finish()]); frames++;
    // Submitted work retains its resources. The cache owns only this frame's
    // keys; a later rollback can upload its immutable CPU batches again.
    for (const [key, value] of geometry) if (!present.has(value)) { destroyGeometry(value); geometry.delete(key); }
    for (const [key, view] of insets) if (!visible.has(key)) { destroyInset(view); insets.delete(key); }
    const liveMeshes = new Set([...present].flatMap(batch => batch.source.draws.map(draw => draw.mesh)));
    for (const [source,mesh] of meshes) if (!liveMeshes.has(source)) { destroyMesh(mesh); meshes.delete(source); }
    return target;
  }
  function draw(scene, logicalWidth = canvas.clientWidth || canvas.width, logicalHeight = canvas.clientHeight || canvas.height) {
    const target = render(scene,logicalWidth,logicalHeight);
    if (target) latest = {scene,logicalWidth,logicalHeight}; return target;
  }
  function animate(time) {
    // Test the last drawn fraction, ensuring a delayed frame still draws the
    // endpoint once before animation sleeps. No Scheme query runs on this path.
    const scene = latest?.scene;
    if (scene && [scene,...scene.insets ?? []].some(view => view.batches.some(batch => {
      const stored = geometry.get(geometryKey(view === scene ? undefined : view.key,batch.key));
      return stored?.count && (batch.pulse || stored.fraction < 1 || reveals.get(batch.reveal?.id)?.fraction < 1);
    })))
      render(latest.scene,latest.logicalWidth,latest.logicalHeight,time);
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
    context.unconfigure(); depth?.destroy(); for (const value of geometry.values()) destroyGeometry(value);
    for (const view of insets.values()) destroyInset(view);
    for (const mesh of meshes.values()) destroyMesh(mesh);
    uniform.destroy(); geometry.clear(); meshes.clear(); insets.clear(); reveals.clear(); latest = current = previous = depth = undefined; device.destroy();
  }
  return {adapter: adapter.info, device, prepare, draw, animate,
    replace(candidate) { if (closed) return; previous = current; current = candidate; },
    rollback() { if (previous) { current = previous; previous = undefined; } },
    readPixels: scene => track(readPixels(scene)),
    close() { if (!closing) { closed = true; closing = dispose(); } return closing; },
    get resources() { return {closed, lost, uploads, frames, batches: geometry.size,
      meshes:meshes.size, meshUploads, drawCalls, instancedDraws,
      instances:[...geometry.values()].reduce((total,value) => total + value.source.transforms.length / 12,0),
      vertexBytes:[...meshes.values()].reduce((total,value) => total + value.vertices.size,0),
      instanceBytes:[...geometry.values()].reduce((total,value) => total + value.transforms.size + value.normals.size + (value.previousTransforms?.size ?? 0),0),
      motionBytes:[...geometry.values()].reduce((total,value) => total + (value.previousTransforms?.size ?? 0),0),
      indexBytes:[...meshes.values()].reduce((total,value) => total + value.indices.size,0),
      insets: insets.size, insetPixels: [...insets.values()].reduce((total,view) => total+view.width*view.height,0),
      reveals: reveals.size,
      textures: (depth ? 1 : 0)+2*insets.size, pending: pending.size}; }};
}
