// Compare the two meshes actually shipped. Both grids split northwest to
// southeast. Each clipped road triangle fits inside one coarse triangle,
// so the highest difference occurs at one of its vertices.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {inflateRawSync} from 'node:zlib';

const [root, override] = process.argv.slice(2);
const assets = join(root, 'src/apps/last-mile/assets');
const glb = await readFile(override ?? join(assets, 'horizon.glb'));
const end = 20 + glb.readUInt32LE(12);
const gltf = JSON.parse(glb.toString('utf8', 20, end));
const land = gltf.meshes[0].primitives.find(p =>
  gltf.materials[p.material].pbrMetallicRoughness.baseColorFactor.join() === '0.32,0.36,0.23,1');
const positions = gltf.accessors[land.attributes.POSITION];
const vertices = end + 8 + gltf.bufferViews[positions.bufferView].byteOffset;
const grid = new Map();
const cell = (x, z) => Math.floor(x / 128) + ',' + Math.floor(z / 128);
for (let i = 0; i < positions.count; i += 3) {
  const t = Array.from({length: 3}, (_, j) => Array.from({length: 3}, (_, k) =>
    glb.readFloatLE(vertices + 12 * (i + j) + 4 * k)));
  const key = cell(Math.min(...t.map(v => v[0])), Math.min(...t.map(v => v[2])));
  if (!grid.has(key)) grid.set(key, []);
  grid.get(key).push(t);
}
function landHeight(x, z) {
  for (const [[ax, ay, az], [bx, by, bz], [cx, cy, cz]] of grid.get(cell(x, z)) ?? []) {
    const det = (bx - ax) * (cz - az) - (cx - ax) * (bz - az);
    const u = ((x - ax) * (cz - az) - (cx - ax) * (z - az)) / det;
    const v = ((bx - ax) * (z - az) - (x - ax) * (bz - az)) / det;
    if (u >= -1e-8 && v >= -1e-8 && u + v <= 1 + 1e-8) return ay + u * (by - ay) + v * (cy - ay);
  }
}
let tested = 0, worst = -Infinity, buried = 0;
for (let band = 0; band < 6; band++) {
  const file = await readFile(join(assets, 'sf-' + band + '.bin'));
  const west = file.readInt32LE(4), north = file.readInt32LE(8), cols = file.readUInt32LE(12);
  const side = file.readUInt32LE(20), row = file.readUInt32LE(24);
  const n = (file.readUInt32LE(28) - row) * cols, start = 36 + 4 * n;
  for (let i = 0; i < n; i++) {
    const a = start + file.readUInt32LE(32 + 4 * i), b = start + file.readUInt32LE(36 + 4 * i);
    if (a === b) continue;
    const raw = inflateRawSync(file.subarray(a + 4, b));
    const mesh = raw.subarray(16 + raw.readUInt32LE(0)), groups = mesh.readUInt32LE(0);
    for (let k = 0; k < groups; k++) {
      const h = 4 + 20 * k;
      if (mesh.readUInt32LE(h) !== 0) continue;
      const at = 4 + 20 * groups + mesh.readUInt32LE(h + 12);
      for (let j = 0; j < mesh.readUInt32LE(h + 4); j++) {
        const v = at + 8 * j;
        const x = west + (i % cols) * side + mesh.readUInt16LE(v) / 100;
        const z = north + (row + Math.floor(i / cols)) * side + mesh.readUInt16LE(v + 4) / 100;
        const y = landHeight(x, z);
        if (y === undefined) continue;
        const difference = y - (mesh.readUInt16LE(v + 2) / 100 - 12);
        tested++; worst = Math.max(worst, difference);
        if (difference >= 0) buried++;
      }
    }
  }
}
console.log(`Distant land vs ${tested} road vertices: ${buried} buried, highest land minus road ${worst.toFixed(3)} m`);
assert.ok(tested > 100000 && worst < -0.10);
