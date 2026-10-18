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

export function createSceneBridge(provider, transaction) {
  const caches = new WeakMap();
  function frame() {
    const tx = transaction();
    if (!tx?.readOnly) throw new Error('scene output requires a presentation query');
    if (!tx.instance) throw new Error('scene output requires an owning module instance');
    let cache = caches.get(tx.instance);
    if (!cache) { cache = new Map(); caches.set(tx.instance, cache); }
    return tx.scene ??= {uniforms: [], batches: [], background: undefined,
      cache, keys: new Set(), pending: [], open: undefined};
  }
  function complete(scene) {
    if (!scene.open) return;
    if (!scene.open.ready) throw new Error('scene batch dependencies were not closed');
    scene.batches.push(scene.open.batch);
    if (scene.open.key >= 0 && !scene.open.reused) scene.pending.push({key: scene.open.key, states: scene.open.states,
      dependencies: scene.open.dependencies, batch: scene.open.batch});
    scene.open = undefined;
  }
  function currentBatch() {
    const open = frame().open;
    if (!open?.ready || open.reused) throw new Error('scene geometry requires an uncached open batch');
    return open.batch;
  }
  const host = {
    uniform(index, bits) {
      const scene = frame();
      if (index !== scene.uniforms.length || index >= 24) throw new Error('invalid scene uniform sequence');
      scene.uniforms.push(scalar(bits));
    },
    batch(key, mask) {
      const scene = frame(); complete(scene);
      if (scene.keys.has(key) || key < -1) throw new Error('duplicate or invalid scene batch key');
      scene.keys.add(key);
      scene.open = {key, states: ownerSnapshots(transaction(), mask), dependencies: [], ready: false, reused: false};
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
        open.batch = cached.batch; open.reused = true; return 1;
      }
      open.batch = {key: open.key, vertices: [], indices: []};
      return 0;
    },
    vertex(x, y, z, nx, ny, nz, color, emission) {
      const batch = currentBatch(), glow = scalar(emission);
      if (batch.vertices.length >= 2000000 || glow < 0 || glow > 1) throw new Error('invalid scene vertex');
      batch.vertices.push(scalar(x), scalar(y), scalar(z), scalar(nx), scalar(ny), scalar(nz), ...rgb(color), glow);
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
    provider: provider(host, [['uniform', 2, false], ['batch', 2, false], ['dependency', 1, false], ['reuse', 0, true],
      ['vertex', 8, false], ['triangle', 3, false], ['background', 1, false]]),
    finish(tx) {
      if (!tx.scene) return undefined;
      complete(tx.scene);
      if (tx.scene.uniforms.length !== 24 || !tx.scene.background || !tx.scene.batches.length)
        throw new Error('incomplete scene');
      for (const value of tx.scene.pending) tx.scene.cache.set(value.key, value);
      return {uniforms: tx.scene.uniforms, batches: tx.scene.batches, background: tx.scene.background};
    }
  };
}
