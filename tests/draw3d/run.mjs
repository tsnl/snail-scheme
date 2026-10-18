import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {createSceneBridge} from '../../src/draw3d/bridge.mjs';

// The fixture uses the same typed scalar forwarding ABI as application hosts.
function provider(functions, signatures) {
  const text = value => { const bytes = [...new TextEncoder().encode(value)]; return [bytes.length, ...bytes]; };
  const section = (id, bytes) => [id, ...uleb(bytes.length), ...bytes];
  const types = signatures.flatMap(([, count, result]) =>
    [0x60, count, ...Array(count).fill(0x7f), ...(result ? [1, 0x7f] : [0])]);
  const imports = signatures.flatMap(([key], index) => [...text('host'), ...text(key), 0, index]);
  const exports = signatures.flatMap(([key], index) => [...text(key), 0, index]);
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from([0,97,115,109,1,0,0,0,
    ...section(1, [signatures.length, ...types]), ...section(2, [signatures.length, ...imports]),
    ...section(7, [signatures.length, ...exports])])), {host: functions});
}
function uleb(value) {
  const result = [];
  do { const byte = value & 127; value >>>= 7; result.push(byte | (value ? 128 : 0)); } while (value);
  return result;
}
const output = process.argv[2];
const load = name => loadWasm(readFileSync(join(output, `${name}.wasm`)));
const math = instantiate(load('math'));
assert.equal(invokeEntry(math, []), 1); closeInstance(math);
console.log('ok - affine normals, both camera projections, ground rays, copied indexed geometry and shader checks');
const owners = new Map([[1, new Int32Array(1)], [2, new Int32Array(1)]]);
let tx = {readOnly: true, snapshots: owners};
const bridge = createSceneBridge(provider, () => tx);
const scene = instantiate(load('frame'), new Map([['snail.scene', bridge.provider]]));
tx.instance = scene;
assert.equal(invokeEntry(scene, []), 1);
const frame = bridge.finish(tx);
const vertices = frame.batches.reduce((total, batch) => total + batch.vertices.length / 10, 0);
const triangles = frame.batches.reduce((total, batch) => total + batch.indices.length / 3, 0);
assert.equal(frame.uniforms.length, 24); assert.ok(vertices > 1000); assert.ok(triangles > 1000 / 3);
for (const batch of frame.batches) assert.ok(batch.indices.every(index => index < batch.vertices.length / 10));
tx = {readOnly: true, snapshots: owners, instance: scene}; assert.equal(invokeEntry(scene, []), 1);
const reused = bridge.finish(tx); assert.ok(reused.batches.every((batch, index) => batch === frame.batches[index]));
tx = {readOnly: true, snapshots: new Map(owners).set(1, new Int32Array(1)), instance: scene};
assert.equal(invokeEntry(scene, []), 1); const changed = bridge.finish(tx);
assert.ok(changed.batches.slice(0, 3).every((batch, index) => batch === frame.batches[index]));
assert.notEqual(changed.batches[3], frame.batches[3]); closeInstance(scene);
writeFileSync(join(output, 'frame.json'), JSON.stringify(frame));
const shader = instantiate(load('shader')), length = invokeEntry(shader, [-1]), characters = [];
assert.ok(length > 0);
for (let i = 0; i < length; i++) characters.push(invokeEntry(shader, [i]));
writeFileSync(join(output, 'shader.wgsl'), String.fromCodePoint(...characters)); closeInstance(shader);
console.log('ok - immutable scene batches reuse exact scalar and owner dependencies',
  {vertices, triangles, batches: frame.batches.length});
