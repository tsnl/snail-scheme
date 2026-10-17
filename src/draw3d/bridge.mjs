// Parse one complete, copied scene at the Wasm boundary. The resulting arrays
// contain no game state, live Wasm references, or GPU resources.
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
export function createSceneBridge(provider, transaction) {
  function frame() {
    const tx = transaction();
    if (!tx?.readOnly) throw new Error('scene output requires a presentation query');
    return tx.scene ??= {uniforms: [], vertices: [], indices: [], background: undefined};
  }
  const host = {
    uniform(index, bits) {
      const scene = frame();
      if (index !== scene.uniforms.length || index >= 24) throw new Error('invalid scene uniform sequence');
      scene.uniforms.push(scalar(bits));
    },
    vertex(x, y, z, nx, ny, nz, color, emission) {
      const scene = frame(), glow = scalar(emission);
      if (scene.vertices.length >= 2000000 || glow < 0 || glow > 1) throw new Error('invalid scene vertex');
      scene.vertices.push(scalar(x), scalar(y), scalar(z), scalar(nx), scalar(ny), scalar(nz), ...rgb(color), glow);
    },
    triangle(a, b, c) {
      const scene = frame(), count = scene.vertices.length / 10;
      if ([a, b, c].some(index => index < 0 || index >= count) || scene.indices.length >= 3000000)
        throw new Error('invalid scene triangle');
      scene.indices.push(a, b, c);
    },
    background(color) { frame().background = rgb(color); }
  };
  return {
    provider: provider(host, [['uniform', 2, false], ['vertex', 8, false], ['triangle', 3, false], ['background', 1, false]]),
    finish(tx) {
      if (!tx.scene) return undefined;
      if (tx.scene.uniforms.length !== 24 || !tx.scene.background) throw new Error('incomplete scene');
      return tx.scene;
    }
  };
}
