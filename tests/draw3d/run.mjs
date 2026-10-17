import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {createSceneBridge} from '../../src/draw3d/bridge.mjs';

// The fixture uses the same typed scalar forwarding ABI as application hosts.
function provider(functions, signatures) {
  const text = value => { const bytes = [...new TextEncoder().encode(value)]; return [bytes.length, ...bytes]; };
  const section = (id, bytes) => [id, ...uleb(bytes.length), ...bytes];
  const types = signatures.flatMap(([, count]) => [0x60, count, ...Array(count).fill(0x7f), 0]);
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
const tx = {readOnly: true}, bridge = createSceneBridge(provider, () => tx);
const scene = instantiate(load('frame'), new Map([['snail.scene', bridge.provider]]));
assert.equal(invokeEntry(scene, []), 1); closeInstance(scene);
const frame = bridge.finish(tx);
assert.equal(frame.uniforms.length, 24); assert.ok(frame.vertices.length > 1000); assert.ok(frame.indices.length > 1000);
assert.ok(frame.indices.every(index => index < frame.vertices.length / 10));
writeFileSync(join(output, 'frame.json'), JSON.stringify(frame));
const shader = instantiate(load('shader')), length = invokeEntry(shader, [-1]), characters = [];
assert.ok(length > 0);
for (let i = 0; i < length; i++) characters.push(invokeEntry(shader, [i]));
writeFileSync(join(output, 'shader.wgsl'), String.fromCodePoint(...characters)); closeInstance(shader);
console.log('ok - Scheme colony scene copied through typed Wasm bridge', {vertices: frame.vertices.length / 10, triangles: frame.indices.length / 3});
