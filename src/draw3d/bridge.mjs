// Parse immutable scene batches at the Wasm boundary. A batch may be reused
// only when its declared scalar dependencies and immutable owner snapshots are
// identical. No game reference or GPU resource crosses this boundary.
const word = new Int32Array(1), real = new Float32Array(word.buffer);
function scalar(bits) {
  word[0] = bits;
  if (!Number.isFinite(real[0]) || Math.abs(real[0]) > 1e30) throw new Error('invalid scene scalar');
  return real[0];
}
// Test the copied binary32 basis using binary64 arithmetic. Binary32 determinant
// arithmetic could itself underflow for supported diagonal scales. This catches
// bases collapsed by copying, not every loss of precision from ill conditioning.
function instanceMatrix(bits, stride) {
  const m = bits.map(scalar), s = stride, t = stride * 2;
  const determinant = m[0] * (m[s+1] * m[t+2] - m[s+2] * m[t+1]) -
    m[1] * (m[s] * m[t+2] - m[s+2] * m[t]) + m[2] * (m[s] * m[t+1] - m[s+1] * m[t]);
  if (determinant === 0) throw new Error('singular copied scene instance matrix');
  // GPUs may flush subnormal coefficients even when the host preserves them.
  if (stride === 3 && m.some(value => value !== 0 && Math.abs(value) < 2 ** -126))
    throw new Error('subnormal scene normal coefficient');
  return m;
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
function freezeInstances(batch) {
  for (const values of [batch.transforms,batch.normals,batch.previous].filter(Boolean)) Object.freeze(values);
  for (const draw of batch.draws) Object.freeze(draw);
  Object.freeze(batch.draws);
}
function completeInstance(batch) {
  const count = batch.transforms.length / 12;
  if (batch.normals.length !== count * 9 || (batch.previous && batch.previous.length !== count * 12))
    throw new Error('incomplete scene instance');
}
function regroupInstances(batch) {
  if (!batch.unordered) return;
  const groups = new Map(), transforms = [], normals = [], previous = batch.previous ? [] : undefined;
  for (const draw of batch.draws) {
    if (!groups.has(draw.mesh)) groups.set(draw.mesh, []);
    groups.get(draw.mesh).push(draw);
  }
  batch.draws = [...groups].map(([mesh, draws]) => {
    const first = transforms.length / 12;
    for (const draw of draws) for (let i = draw.first; i < draw.first + draw.count; i++) {
      transforms.push(...batch.transforms.slice(i * 12, i * 12 + 12));
      normals.push(...batch.normals.slice(i * 9, i * 9 + 9));
      if (previous) previous.push(...batch.previous.slice(i * 12, i * 12 + 12));
    }
    return {mesh, first, count: transforms.length / 12 - first};
  });
  batch.transforms = transforms; batch.normals = normals;
  if (previous) batch.previous = previous;
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
function batchMetadata(batch, reveal, motionClock) {
  const previous = batch.reveal;
  const sameReveal = previous === reveal || (previous && reveal &&
    ['id','x','y','radius','edge','elapsed','duration'].every(key => previous[key] === reveal[key]));
  return sameReveal && batch.motionClock === motionClock ? batch : {...batch, reveal, motionClock};
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

function checkMotionClocks(frames) {
  const durations = new Map();
  for (const scene of frames) for (const batch of scene.batches) if (batch.motionClock) {
    const prior = durations.get(batch.motionClock);
    if (!(batch.duration > 0) || (prior !== undefined && prior !== batch.duration))
      throw new Error('inconsistent owner motion duration');
    durations.set(batch.motionClock,batch.duration);
  }
}

export function createSceneBridge(provider, transaction) {
  const caches = new WeakMap();
  function scope() {
    const tx = transaction();
    if (!tx?.readOnly) throw new Error('scene output requires a presentation query');
    if (!tx.instance) throw new Error('scene output requires an owning module instance');
    let owner = caches.get(tx.instance);
    if (!owner) { owner = {views:new Map(), meshes:new Map(), motionOwners:[new WeakMap(),new WeakMap()]}; caches.set(tx.instance, owner); }
    const {views} = owner;
    if (!tx.scene) {
      const main = sceneView(-1, views.get(-1) ?? new Map());
      tx.scene = {owner, views, main, current: main, insets: [], keys: new Set([-1]), meshes:new Map()};
    }
    return tx.scene;
  }
  // Scene data carries only an opaque token. Weak keys never retain an old
  // authoritative snapshot; module and owner scopes prevent accidental sharing.
  function ownerMotionClock(owner) {
    const snapshot = transaction().snapshots?.get(owner);
    if (![1,2].includes(owner) || !snapshot || typeof snapshot !== 'object')
      throw new Error('motion clock requires an immutable owner snapshot');
    const epochs = scope().owner.motionOwners[owner - 1];
    if (!epochs.has(snapshot)) epochs.set(snapshot,Object.freeze({}));
    return epochs.get(snapshot);
  }
  function frame() { return scope().current; }
  function complete(scene) {
    if (!scene.open) return;
    if (!scene.open.ready) throw new Error('scene batch dependencies were not closed');
    const batch = scene.open.batch;
    if (!scene.open.reused) {
      completeInstance(batch);
      if (scene.open.building) throw new Error('scene prototype has no instance');
      regroupInstances(batch); freezeInstances(batch);
    }
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
  function currentMesh() {
    currentBatch();
    const mesh = frame().open.building;
    if (!mesh) throw new Error('scene vertices require a new prototype');
    return mesh;
  }
  function selectMesh(identity, color, emission) {
    const batch = currentBatch(), scene = scope(), open = frame().open, glow = scalar(emission);
    completeInstance(batch);
    if (open.building || !Number.isInteger(identity) || identity <= 0 || color < -1 || color > 0xffffff ||
        glow < 0 || glow > 1 || (color === -1 && glow !== 0)) throw new Error('invalid scene prototype');
    const key = `${identity}:${color}:${glow}`;
    open.mesh = scene.meshes.get(key) ?? scene.owner.meshes.get(key);
    if (open.mesh) return 1;
    open.mesh = open.building = {key, vertices:[], indices:[]};
    return 0;
  }
  function finishMesh() {
    const open = frame().open;
    if (!open.mesh) throw new Error('scene instance requires a prototype');
    if (open.building) {
      Object.freeze(open.mesh.vertices); Object.freeze(open.mesh.indices); Object.freeze(open.mesh);
      scope().meshes.set(open.mesh.key,open.mesh); open.building = undefined;
    }
    return open.mesh;
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
    unordered() {
      const open = frame().open;
      if (!open || open.ready || open.unordered) throw new Error('invalid scene ordering declaration');
      open.unordered = true;
    },
    motion(duration) {
      const open = frame().open;
      if (!open || open.ready || duration < 0) throw new Error('invalid batch motion duration');
      open.duration = duration; open.dependencies.push(duration);
    },
    'motion-clock'(owner) {
      const open = frame().open;
      if (!open || open.ready || open.motionClock || open.duration <= 0) throw new Error('invalid scene motion clock');
      open.motionClock = ownerMotionClock(owner);
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
      if (open.unordered && (open.opacity !== 1 || open.pulse || (open.reveal?.edge ?? 0) !== 0))
        throw new Error('unordered scene batch must be opaque');
      open.dependencies.push(open.unordered ? 1 : 0);
      open.ready = true;
      if (cached && sameSnapshots(cached.states, open.states) && sameValues(cached.dependencies, open.dependencies)) {
        open.batch = batchMetadata(cached.batch,open.reveal,open.motionClock); open.reused = true; return 1;
      }
      open.batch = {key: open.key, draws: [], transforms: [], normals: [], unordered:!!open.unordered,
        opacity: open.opacity, pulse: open.pulse, pulsePhase: open.pulsePhase ?? 0,
        ...(open.duration ? {duration: open.duration, previous: []} : {}), ...(open.reveal ? {reveal:open.reveal} : {}),
        ...(open.motionClock ? {motionClock:open.motionClock} : {})};
      return 0;
    },
    prototype: selectMesh,
    vertex(x, y, z, nx, ny, nz, color, emission) {
      const mesh = currentMesh(), glow = scalar(emission);
      if (mesh.vertices.length >= 2000000 || glow < 0 || glow > 1) throw new Error('invalid scene vertex');
      mesh.vertices.push(scalar(x), scalar(y), scalar(z), scalar(nx), scalar(ny), scalar(nz), ...rgb(color), glow);
    },
    triangle(a, b, c) {
      const mesh = currentMesh(), count = mesh.vertices.length / 10;
      if ([a, b, c].some(index => !Number.isInteger(index) || index < 0 || index >= count) || mesh.indices.length >= 3000000)
        throw new Error('invalid scene triangle');
      mesh.indices.push(a, b, c);
    },
    instance(...values) {
      const batch = currentBatch(); completeInstance(batch);
      if (values.length !== 12 || batch.transforms.length >= 2400000) throw new Error('invalid scene instance');
      const transform = instanceMatrix(values, 4), mesh = finishMesh(), last = batch.draws.at(-1);
      if (last?.mesh === mesh) last.count++;
      else batch.draws.push({mesh, first:batch.transforms.length / 12, count:1});
      batch.transforms.push(...transform);
    },
    normal(...values) {
      const batch = currentBatch(), count = batch.transforms.length / 12;
      if (values.length !== 9 || batch.normals.length !== (count - 1) * 9)
        throw new Error('invalid scene normal sequence');
      batch.normals.push(...instanceMatrix(values, 3));
    },
    before(...values) {
      const batch = currentBatch(), count = batch.transforms.length / 12;
      if (values.length !== 12 || !batch.previous || batch.previous.length !== (count - 1) * 12 || batch.normals.length !== count * 9)
        throw new Error('invalid previous scene instance sequence');
      batch.previous.push(...instanceMatrix(values, 4));
    },
    background(color) { frame().background = rgb(color); }
  };
  return {
    provider: provider(host, [['uniform', 2, false], ['batch', 2, false], ['opacity', 2, false], ['motion', 1, false],
      ['reveal', 7, false], ['motion-clock', 1, false],
      ['dependency', 1, false], ['reuse', 0, true], ['prototype', 3, true], ['vertex', 8, false],
      ['instance', 12, false], ['normal', 9, false], ['before', 12, false], ['unordered', 0, false],
      ['triangle', 3, false], ['background', 1, false], ['viewport', 4, false], ['request-frame', 0, false],
      ['begin-inset', 5, false], ['end-inset', 0, false]]),
    finish(tx) {
      if (!tx.scene) return undefined;
      const {main, current, insets, owner} = tx.scene;
      if (current !== main) throw new Error('unclosed scene inset');
      const frames = [main, ...insets].map(scene => {
        complete(scene);
        if (scene.uniforms.length !== 32 || !scene.background || !scene.batches.length) throw new Error('incomplete scene');
        return {uniforms: scene.uniforms, batches: scene.batches, background: scene.background,
          requestFrame: !!scene.requestFrame, ...(scene.viewport ? {viewport: scene.viewport} : {})};
      });
      checkReveals(frames); checkMotionClocks(frames);
      // Only the complete accepted frame owns retained CPU batches and meshes.
      // Failed parsing never publishes new prototypes or evicts old references.
      owner.views = new Map([main,...insets].map(scene =>
        [scene.key,new Map(scene.pending.map(value => [value.key,value]))]));
      owner.meshes = new Map(frames.flatMap(scene => scene.batches.flatMap(batch =>
        batch.draws.map(draw => [draw.mesh.key,draw.mesh]))));
      return {...frames[0], requestFrame: frames.some(frame => frame.requestFrame),
        ...(insets.length ? {insets: insets.map((scene, index) => ({key: scene.key, rect: scene.rect, ...frames[index + 1]}))} : {})};
    }
  };
}
