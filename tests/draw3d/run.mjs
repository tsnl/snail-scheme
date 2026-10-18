import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {createSceneBridge} from '../../src/draw3d/bridge.mjs';
import {BrowserApplication} from '../../src/browser/application.mjs';

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
function immutableGeometry(frame) {
  for (const scene of [frame, ...frame.insets ?? []]) for (const batch of scene.batches)
    for (const values of [batch.vertices, batch.indices, batch.previous].filter(Boolean)) {
      assert.ok(Array.isArray(values) && values.every(Number.isFinite));
      assert.ok(Object.isFrozen(values));
      assert.throws(() => values.push(0), TypeError);
      if (values.length) assert.throws(() => { values[0] = 0; }, TypeError);
    }
}
const output = process.argv[2];
const load = name => loadWasm(readFileSync(join(output, `${name}.wasm`)));
const math = instantiate(load('math'));
assert.equal(invokeEntry(math, []), 1); closeInstance(math);
console.log('ok - affine normals, both camera projections, ground rays, copied indexed geometry and shader checks');
const presentation = instantiate(load('presentation'));
assert.equal(invokeEntry(presentation,[-1]),1);
for(const interval of [1800,3600])assert.equal(invokeEntry(presentation,[interval]),interval);
for(const interval of [0,-2,2147483647])assert.throws(()=>invokeEntry(presentation,[interval]),WebAssembly.RuntimeError);
closeInstance(presentation);
console.log('ok - one difficulty projection derives labels and progress from normal and doubled model intervals, including cap and bounds');
const owners = new Map([[1, new Int32Array(1)], [2, new Int32Array(1)]]);
let tx = {readOnly: true, snapshots: owners};
const bridge = createSceneBridge(provider, () => tx);
const scene = instantiate(load('frame'), new Map([['snail.scene', bridge.provider]]));
tx.instance = scene;
assert.equal(invokeEntry(scene, []), 1);
const frame = bridge.finish(tx);
immutableGeometry(frame);
const vertices = frame.batches.reduce((total, batch) => total + batch.vertices.length / 10, 0);
const triangles = frame.batches.reduce((total, batch) => total + batch.indices.length / 3, 0);
assert.equal(frame.uniforms.length, 32); assert.ok(vertices > 1000); assert.ok(triangles > 1000 / 3);
for (const batch of frame.batches) assert.ok(batch.indices.every(index => index < batch.vertices.length / 10));
tx = {readOnly: true, snapshots: owners, instance: scene}; assert.equal(invokeEntry(scene, []), 1);
const reused = bridge.finish(tx); assert.ok(reused.batches.every((batch, index) => batch === frame.batches[index]));
tx = {readOnly: true, snapshots: new Map(owners).set(1, new Int32Array(1)), instance: scene};
assert.equal(invokeEntry(scene, []), 1); const changed = bridge.finish(tx);
assert.ok(changed.batches.slice(0, 3).every((batch, index) => batch === frame.batches[index]));
assert.equal(changed.batches.find(batch=>batch.key===13),frame.batches.find(batch=>batch.key===13));
assert.notEqual(changed.batches.find(batch=>batch.key===3),frame.batches.find(batch=>batch.key===3)); closeInstance(scene);
writeFileSync(join(output, 'frame.json'), JSON.stringify(frame));
const shader = instantiate(load('shader')), length = invokeEntry(shader, [-1]), characters = [];
assert.ok(length > 0);
for (let i = 0; i < length; i++) characters.push(invokeEntry(shader, [i]));
writeFileSync(join(output, 'shader.wgsl'), String.fromCodePoint(...characters)); closeInstance(shader);
console.log('ok - immutable scene batches reuse exact scalar and owner dependencies',
  {vertices, triangles, batches: frame.batches.length});

const moving = instantiate(load('motion'), new Map([['snail.scene', bridge.provider]]));
tx = {readOnly: true, snapshots: owners, instance: moving};
assert.equal(invokeEntry(moving, []), 1);
const motion = bridge.finish(tx), [stationary, animated, still] = motion.batches;
immutableGeometry(motion);
assert.deepEqual(motion.insets.map(view => [view.key,view.rect]),[[7,[10,20,96,72]],[8,[110,20,96,72]]]);
assert.notDeepEqual(motion.insets[0].uniforms,motion.uniforms);
assert.deepEqual(motion.insets[0].batches[0].vertices.slice(0,3),[3,3.5,6]);
assert.notEqual(motion.insets[1].batches[0],stationary);
assert.equal(stationary.previous, undefined); assert.equal(animated.duration, 100); assert.equal(still.duration, 200);
assert.deepEqual(animated.reveal,{id:91,x:0,y:0,radius:20,edge:Math.fround(.7),elapsed:250,duration:3000});
assert.deepEqual(animated.reveal,motion.insets[0].batches[0].reveal);
assert.equal(animated.previous.length, animated.vertices.length / 10 * 3);
assert.deepEqual(animated.vertices.slice(0, 3), [3, 3.5, 6]);
assert.deepEqual(animated.previous.slice(0, 3), [0, 0.5, 3]);
assert.deepEqual(animated.vertices.slice(40, 43), [4.5, 4.5, 6.5]);
assert.deepEqual(animated.previous.slice(12, 15), [-0.5, 1.5, 3.5]);
for (let vertex = 0; vertex < still.vertices.length / 10; vertex++)
  assert.deepEqual(still.previous.slice(vertex * 3, vertex * 3 + 3), still.vertices.slice(vertex * 10, vertex * 10 + 3));
tx = {readOnly: true, snapshots: owners, instance: moving};
assert.equal(invokeEntry(moving, []), 1);
const reusedMotion=bridge.finish(tx);
assert.deepEqual(reusedMotion.batches.map((batch, i) => batch === motion.batches[i]), [true, true, true]);
assert.ok(reusedMotion.insets.every((view,index)=>view.batches[0]===motion.insets[index].batches[0]));
closeInstance(moving);
console.log('ok - nested motion transforms copy corresponding endpoints; static batches omit previous vertices');
console.log('ok - typed inset scenes retain independent cameras and scope equal batch keys by stable view identity');

const resizeCalls=[],surface={getBoundingClientRect:()=>({width:1920,height:1080})};
const application={canvas:surface,inputSettings:{},manifest:{settings:{viewportHandler:'viewport'}},local:(...args)=>resizeCalls.push(args)};
const oldRatio=globalThis.devicePixelRatio;
try {
  globalThis.devicePixelRatio=2; BrowserApplication.prototype.resizeViewport.call(application);
  assert.deepEqual([surface.width,surface.height],[3840,2160]);
  BrowserApplication.prototype.resizeViewport.call(application); assert.equal(resizeCalls.length,1);
  globalThis.devicePixelRatio=3; BrowserApplication.prototype.resizeViewport.call(application);
  assert.deepEqual([surface.width,surface.height],[5760,3240]); assert.equal(resizeCalls.length,2);
} finally { if(oldRatio===undefined)delete globalThis.devicePixelRatio;else globalThis.devicePixelRatio=oldRatio; }
console.log('ok - browser backing sizes retain native DPR above the former pixel budget and detect DPR-only changes');

const boundaryInstance={},boundaryBridge=createSceneBridge(functions=>functions,()=>tx),host=boundaryBridge.provider;
function beginBoundary() { tx={readOnly:true,instance:boundaryInstance,snapshots:owners}; }
function floatBits(value) { return new Int32Array(Float32Array.of(value).buffer)[0]; }
function boundaryView(dependency=0,uniforms=32,reveal) {
  for(let index=0;index<uniforms;index++)host.uniform(index,0);
  host.background(0);host.batch(1,0);host.dependency(dependency);
  if(reveal)host.reveal(reveal.id,floatBits(reveal.x),floatBits(reveal.y),floatBits(reveal.radius),floatBits(reveal.edge),reveal.elapsed,reveal.duration);
  const reused=host.reuse();if(!reused)host.vertex(0,0,0,0,0,0,0,0);return reused;
}
beginBoundary();boundaryView();host['begin-inset'](1,0,0,96,72);boundaryView();host['request-frame']();host['end-inset']();
const accepted=boundaryBridge.finish(tx,{});assert.equal(accepted.requestFrame,true);
immutableGeometry(accepted); // Empty index buffers are immutable too.
beginBoundary();boundaryView(1);host['begin-inset'](1,0,0,96,72);boundaryView(1,31);host['end-inset']();
assert.throws(()=>boundaryBridge.finish(tx),/incomplete scene/);
beginBoundary();assert.equal(boundaryView(),1);host['begin-inset'](1,0,0,96,72);assert.equal(boundaryView(),1);host['end-inset']();
const retained=boundaryBridge.finish(tx);assert.equal(retained.batches[0],accepted.batches[0]);
assert.equal(retained.insets[0].batches[0],accepted.insets[0].batches[0]);
beginBoundary();boundaryView();host['begin-inset'](1,0,0,96,72);
assert.throws(()=>host['begin-inset'](2,0,0,96,72),/nested/);
assert.throws(()=>boundaryBridge.finish(tx),/unclosed/);
beginBoundary();boundaryView();
for(const key of [1,2,3]){host['begin-inset'](key,0,0,96,72);boundaryView();host['end-inset']();}
assert.throws(()=>host['begin-inset'](4,0,0,96,72),/invalid/);
beginBoundary();boundaryView();boundaryBridge.finish(tx);
beginBoundary();boundaryView();host['begin-inset'](1,0,0,96,72);assert.equal(boundaryView(),0);host['end-inset']();boundaryBridge.finish(tx);
console.log('ok - malformed/nested/excess insets reject atomically; omitted views release their retained cache');

const reveal={id:5,x:1,y:2,radius:10,edge:.7,elapsed:100,duration:3000};
beginBoundary();assert.equal(boundaryView(0,32,reveal),1);const fresh=boundaryBridge.finish(tx);
beginBoundary();assert.equal(boundaryView(0,32,{...reveal,elapsed:200}),1);const older=boundaryBridge.finish(tx);
assert.equal(fresh.batches[0].vertices,older.batches[0].vertices);assert.equal(older.batches[0].reveal.elapsed,200);
assert.equal(fresh.batches[0].reveal.elapsed,100);immutableGeometry(older);
assert.equal(fresh.batches[0].indices,older.batches[0].indices);
beginBoundary();boundaryView(2,32,reveal);host['begin-inset'](1,0,0,96,72);
boundaryView(2,32,{...reveal,x:2});host['end-inset']();
assert.throws(()=>boundaryBridge.finish(tx),/inconsistent scene reveal/);
beginBoundary();assert.equal(boundaryView(),1);boundaryBridge.finish(tx);
beginBoundary();assert.equal(boundaryView(0,32,{...reveal,edge:0}),1);
assert.equal(boundaryBridge.finish(tx).batches[0].reveal.edge,0);
beginBoundary();assert.throws(()=>boundaryView(0,32,{...reveal,edge:-.1}),/reveal extent/);
beginBoundary();assert.throws(()=>boundaryView(0,32,{...reveal,elapsed:-1}),/invalid scene reveal/);
console.log('ok - reveal wrappers preserve copied geometry and validate shared identities before publishing any view');
