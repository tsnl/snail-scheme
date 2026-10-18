// Parse immutable scene batches at the Wasm boundary. A batch may be reused
// only when its declared scalar dependencies and immutable owner snapshots are
// identical. No game reference or GPU resource crosses this boundary.
const word = new Int32Array(1), real = new Float32Array(word.buffer);
function scalar(bits) {
  word[0] = bits;
  if (!Number.isFinite(real[0]) || Math.abs(real[0]) > 1e30) throw new Error('invalid scene scalar');
  return real[0];
}
function rgb(value) {
  if (value < 0 || value > 0xffffff) throw new Error('invalid scene color');
  return [(value >> 16) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255];
}
function sameValues(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
function ownerSnapshots(tx, mask) {
  if (mask < 0 || mask > 3) throw new Error('invalid scene state dependency mask');
  if (mask && !tx.snapshots) throw new Error('scene state dependencies require an application query');
  return [mask & 1 ? tx.snapshots.get(1) : undefined, mask & 2 ? tx.snapshots.get(2) : undefined];
}
function sameSnapshots(left, right) { return left[0] === right[0] && left[1] === right[1]; }
function freezeGeometry(batch) {
  // The builder owns these ordinary arrays and admits only scalar numbers.
  // Freezing each leaf proves it immutable without a later recursive copy/walk.
  // Leave the wrapper and reveal metadata for the presentation's deep freeze.
  Object.freeze(batch.vertices); Object.freeze(batch.indices);
  if (batch.previous) Object.freeze(batch.previous);
}
function viewportRect(x, y, width, height) {
  if (x < 0 || y < 0 || width < 1 || height < 1 || x + width > 16384 || y + height > 16384)
    throw new Error('invalid scene viewport');
  return [x, y, width, height];
}
function sceneView(key, cache) {
  return {key, cache, uniforms: [], batches: [], background: undefined,
    keys: new Set(), pending: [], open: undefined};
}
function revealGeometry(batch, reveal) {
  const previous = batch.reveal;
  if (previous === reveal || (previous && reveal &&
      ['id','x','y','radius','edge','elapsed','duration'].every(key => previous[key] === reveal[key]))) return batch;
  return {...batch, reveal};
}
function checkReveals(frames) {
  const reveals = new Map();
  for (const scene of frames) for (const {reveal} of scene.batches) if (reveal) {
    const previous = reveals.get(reveal.id);
    if (previous && ['x','y','radius','edge','duration'].some(key => previous[key] !== reveal[key]))
      throw new Error('inconsistent scene reveal identity');
    reveals.set(reveal.id,reveal);
  }
}

export function createSceneBridge(provider, transaction) {
  const caches = new WeakMap();
  function scope() {
    const tx = transaction();
    if (!tx?.readOnly) throw new Error('scene output requires a presentation query');
    if (!tx.instance) throw new Error('scene output requires an owning module instance');
    let views = caches.get(tx.instance);
    if (!views) { views = new Map(); caches.set(tx.instance, views); }
    if (!tx.scene) {
      const main = sceneView(-1, views.get(-1) ?? new Map());
      tx.scene = {views, main, current: main, insets: [], keys: new Set([-1])};
    }
    return tx.scene;
  }
  function frame() { return scope().current; }
  function complete(scene) {
    if (!scene.open) return;
    if (!scene.open.ready) throw new Error('scene batch dependencies were not closed');
    const batch = scene.open.batch;
    if (batch.duration > 0 && batch.previous.length !== batch.vertices.length / 10 * 3)
      throw new Error('incomplete previous scene vertices');
    if (!scene.open.reused) freezeGeometry(batch);
    scene.batches.push(scene.open.batch);
    if (scene.open.key >= 0) scene.pending.push({key: scene.open.key, states: scene.open.states,
      dependencies: scene.open.dependencies, batch: scene.open.batch});
    scene.open = undefined;
  }
  function currentBatch() {
    const open = frame().open;
    if (!open?.ready || open.reused) throw new Error('scene geometry requires an uncached open batch');
    return open.batch;
  }
  const host = {
    'request-frame'() { frame().requestFrame = true; },
    viewport(x, y, width, height) {
      frame().viewport = viewportRect(x, y, width, height);
    },
    'begin-inset'(key, x, y, width, height) {
      const value = scope();
      if (value.current !== value.main || value.main.uniforms.length !== 32 || key < 0 ||
          value.keys.has(key) || value.insets.length >= 3) throw new Error('invalid or nested scene inset');
      complete(value.main); value.keys.add(key);
      const inset = sceneView(key, value.views.get(key) ?? new Map());
      inset.rect = viewportRect(x, y, width, height);
      value.insets.push(inset); value.current = inset;
    },
    'end-inset'() {
      const value = scope();
      if (value.current === value.main) throw new Error('scene inset was not opened');
      complete(value.current); value.current = value.main;
    },
    uniform(index, bits) {
      const scene = frame();
      if (index !== scene.uniforms.length || index >= 32) throw new Error('invalid scene uniform sequence');
      scene.uniforms.push(scalar(bits));
    },
    batch(key, mask) {
      const scene = frame(); complete(scene);
      if (scene.keys.has(key) || key < -1) throw new Error('duplicate or invalid scene batch key');
      scene.keys.add(key);
      scene.open = {key, states: ownerSnapshots(transaction(), mask), dependencies: [], opacity: 1,
        pulse: false, duration: 0, ready: false, reused: false};
    },
    opacity(bits, pulse) {
      const open = frame().open, opacity = scalar(bits);
      if (!open || open.ready || opacity <= 0 || opacity > 1 || !Number.isInteger(pulse) || pulse < 0 || pulse > 360000)
        throw new Error('invalid batch opacity');
      open.opacity = opacity; open.pulse = !!pulse; open.pulsePhase = pulse ? (pulse - 1) * Math.PI / 180000 : 0;
      open.dependencies.push(bits, pulse);
    },
    motion(duration) {
      const open = frame().open;
      if (!open || open.ready || duration < 0) throw new Error('invalid batch motion duration');
      open.duration = duration; open.dependencies.push(duration);
    },
    reveal(id, x, y, radius, edge, elapsed, duration) {
      const open = frame().open;
      if (!open || open.ready || open.reveal || id < 0 || elapsed < 0 || duration <= 0)
        throw new Error('invalid scene reveal');
      const value = {id,x:scalar(x),y:scalar(y),radius:scalar(radius),edge:scalar(edge),elapsed,duration};
      if (value.radius < 0 || value.edge < 0) throw new Error('invalid scene reveal extent');
      open.reveal = value;
    },
    dependency(value) {
      const open = frame().open;
      if (!open || open.ready || open.dependencies.length >= 65536) throw new Error('invalid scene batch dependency');
      open.dependencies.push(value);
    },
    reuse() {
      const scene = frame(), open = scene.open;
      if (!open || open.ready) throw new Error('invalid scene batch reuse query');
      const cached = open.key < 0 ? undefined : scene.cache.get(open.key);
      open.ready = true;
      if (cached && sameSnapshots(cached.states, open.states) && sameValues(cached.dependencies, open.dependencies)) {
        open.batch = revealGeometry(cached.batch,open.reveal); open.reused = true; return 1;
      }
      open.batch = {key: open.key, vertices: [], indices: [], opacity: open.opacity, pulse: open.pulse, pulsePhase: open.pulsePhase ?? 0,
        ...(open.duration ? {duration: open.duration, previous: []} : {}), ...(open.reveal ? {reveal:open.reveal} : {})};
      return 0;
    },
    vertex(x, y, z, nx, ny, nz, color, emission) {
      const batch = currentBatch(), glow = scalar(emission);
      if (batch.vertices.length >= 2000000 || glow < 0 || glow > 1) throw new Error('invalid scene vertex');
      if (batch.previous && batch.previous.length !== batch.vertices.length / 10 * 3)
        throw new Error('missing previous scene vertex');
      batch.vertices.push(scalar(x), scalar(y), scalar(z), scalar(nx), scalar(ny), scalar(nz), ...rgb(color), glow);
    },
    'previous-vertex'(x, y, z) {
      const batch = currentBatch();
      if (!batch.previous || batch.previous.length !== (batch.vertices.length / 10 - 1) * 3)
        throw new Error('invalid previous scene vertex sequence');
      batch.previous.push(scalar(x), scalar(y), scalar(z));
    },
    triangle(a, b, c) {
      const batch = currentBatch(), count = batch.vertices.length / 10;
      if ([a, b, c].some(index => index < 0 || index >= count) || batch.indices.length >= 3000000)
        throw new Error('invalid scene triangle');
      batch.indices.push(a, b, c);
    },
    background(color) { frame().background = rgb(color); }
  };
  return {
    provider: provider(host, [['uniform', 2, false], ['batch', 2, false], ['opacity', 2, false], ['motion', 1, false],
      ['reveal', 7, false],
      ['dependency', 1, false], ['reuse', 0, true], ['vertex', 8, false], ['previous-vertex', 3, false],
      ['triangle', 3, false], ['background', 1, false], ['viewport', 4, false], ['request-frame', 0, false],
      ['begin-inset', 5, false], ['end-inset', 0, false]]),
    finish(tx) {
      if (!tx.scene) return undefined;
      const {main, current, insets, views, keys} = tx.scene;
      if (current !== main) throw new Error('unclosed scene inset');
      const frames = [main, ...insets].map(scene => {
        complete(scene);
        if (scene.uniforms.length !== 32 || !scene.background || !scene.batches.length) throw new Error('incomplete scene');
        return {uniforms: scene.uniforms, batches: scene.batches, background: scene.background,
          requestFrame: !!scene.requestFrame, ...(scene.viewport ? {viewport: scene.viewport} : {})};
      });
      checkReveals(frames);
      // Publish every view's retained batches only after the entire frame parses.
      for (const scene of [main, ...insets]) {
        for (const value of scene.pending) scene.cache.set(value.key, value);
        views.set(scene.key, scene.cache);
      }
      for (const key of views.keys()) if (!keys.has(key)) views.delete(key);
      return {...frames[0], requestFrame: frames.some(frame => frame.requestFrame),
        ...(insets.length ? {insets: insets.map((scene, index) => ({key: scene.key, rect: scene.rect, ...frames[index + 1]}))} : {})};
    }
  };
}
