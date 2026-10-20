import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {createSceneBridge} from '../../src/draw3d/bridge.mjs';
import {BrowserApplication} from '../../src/browser/application.mjs';
import {parseInputSettings} from '../../src/browser/input.mjs';
import {expandBatch,expandedVertexCount,identityTransform,identityNormal} from './scene-tools.mjs';

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
  for (const scene of [frame, ...frame.insets ?? []]) for (const batch of scene.batches) {
    const arrays=[batch.transforms,batch.normals,batch.previous,...batch.draws.flatMap(draw=>[draw.mesh.vertices,draw.mesh.indices])].filter(Boolean);
    for (const values of arrays) {
      assert.ok(Array.isArray(values) && values.every(Number.isFinite));assert.ok(Object.isFrozen(values));
      assert.throws(() => values.push(0), TypeError);
      if (values.length) assert.throws(() => { values[0] = 0; }, TypeError);
    }
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
const vertices = frame.batches.reduce((total, batch) => total + expandedVertexCount(batch), 0);
const triangles = frame.batches.reduce((total, batch) => total + expandBatch(batch).indices.length / 3, 0);
assert.equal(frame.uniforms.length, 32); assert.ok(vertices > 1000); assert.ok(triangles > 1000 / 3);
for (const batch of frame.batches) for (const {mesh} of batch.draws) assert.ok(mesh.indices.every(index => index < mesh.vertices.length / 10));
tx = {readOnly: true, snapshots: owners, instance: scene}; assert.equal(invokeEntry(scene, []), 1);
const reused = bridge.finish(tx); assert.ok(reused.batches.every((batch, index) => batch === frame.batches[index]));
tx = {readOnly: true, snapshots: new Map(owners).set(1, new Int32Array(1)), instance: scene};
assert.equal(invokeEntry(scene, []), 1); const changed = bridge.finish(tx);
assert.ok(changed.batches.slice(0, 2).every((batch, index) => batch === frame.batches[index]));
assert.equal(changed.batches.find(batch=>batch.key===20),frame.batches.find(batch=>batch.key===20));
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
const motion = bridge.finish(tx), [stationary, animated, still] = motion.batches.map(expandBatch);
immutableGeometry(motion);
assert.deepEqual(motion.insets.map(view => [view.key,view.rect]),[[7,[10,20,96,72]],[8,[110,20,96,72]]]);
assert.notDeepEqual(motion.insets[0].uniforms,motion.uniforms);
assert.deepEqual(expandBatch(motion.insets[0].batches[0]).vertices.slice(0,3),[3,3.5,6]);
assert.notEqual(motion.insets[1].batches[0],motion.batches[0]);
assert.equal(motion.insets[1].batches[0].draws[0].mesh,motion.batches[0].draws[0].mesh);
assert.equal(stationary.previous, undefined); assert.ok(animated.motionClock); assert.ok(Object.isFrozen(animated.motionClock)); assert.equal(animated.duration, 100); assert.equal(still.duration, 200);
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
console.log('ok - nested motion instances preserve corresponding endpoints; static batches omit previous transforms');
console.log('ok - typed inset scenes retain independent cameras and scope equal batch keys by stable view identity');

const fixed=instantiate(load('instances'),new Map([['snail.scene',bridge.provider]]));
tx={readOnly:true,snapshots:owners,instance:fixed};assert.equal(invokeEntry(fixed,[0]),1);
const instances=bridge.finish(tx),[ordered,unordered,composite]=instances.batches;
immutableGeometry(instances);
assert.deepEqual(ordered.draws.map(draw=>draw.count),[1,1,1]);
assert.equal(ordered.draws[0].mesh,ordered.draws[2].mesh,'equal material values share a prototype');
assert.deepEqual(unordered.draws.map(draw=>draw.count),[2,1]);
assert.equal(unordered.draws[0].mesh,ordered.draws[0].mesh,'prototypes share across batches');
assert.deepEqual(composite.draws.map(draw=>draw.count),[2]);
assert.equal(composite.draws[0].mesh.vertices.length/10,40,'a colored body is one fixed composite');
const body=expandBatch(composite);
assert.deepEqual(body.vertices.slice(0,3),[3,-1.5,2]);
assert.deepEqual(body.previous.slice(0,3),[-1,-1.5,2]);
assert.deepEqual(body.vertices.slice(3,6),[0,0,1]);
tx={readOnly:true,snapshots:new Map(owners).set(1,new Int32Array(1)),instance:fixed};
assert.equal(invokeEntry(fixed,[0]),1);const replaced=bridge.finish(tx);
assert.notEqual(replaced.batches[2].transforms,composite.transforms);
assert.equal(replaced.batches[2].draws[0].mesh,composite.draws[0].mesh,'new occurrence data retains fixed mesh identity');
for(const mode of [1,2,4]){tx={readOnly:true,snapshots:owners,instance:fixed};assert.throws(()=>invokeEntry(fixed,[mode]),WebAssembly.RuntimeError);}
tx={readOnly:true,snapshots:owners,instance:fixed};invokeEntry(fixed,[0]);const beforeRejected=bridge.finish(tx);
for(const [mode,error]of [[5,/singular copied scene/],[6,/singular copied scene/],[7,/subnormal scene normal/]]) {
  tx={readOnly:true,snapshots:owners,instance:fixed};assert.throws(()=>invokeEntry(fixed,[mode]),error);
  tx={readOnly:true,snapshots:owners,instance:fixed};invokeEntry(fixed,[0]);const afterRejected=bridge.finish(tx);
  for(let i=0;i<beforeRejected.batches.length;i++)assert.equal(afterRejected.batches[i],beforeRejected.batches[i]);
}
tx={readOnly:true,snapshots:owners,instance:fixed};assert.equal(invokeEntry(fixed,[3]),1);
const extreme=expandBatch(bridge.finish(tx).batches[0]);
assert.ok(extreme.vertices.every(Number.isFinite));
tx={readOnly:true,snapshots:owners,instance:fixed};assert.equal(invokeEntry(fixed,[8]),1);
const anisotropic=bridge.finish(tx);assert.ok(expandBatch(anisotropic.batches[0]).vertices.every(Number.isFinite));
assert.ok(anisotropic.batches[0].normals[4]>0&&anisotropic.batches[0].normals[4]<1e-35);
writeFileSync(join(output,'anisotropic.json'),JSON.stringify(anisotropic));
const other=instantiate(load('instances'),new Map([['snail.scene',bridge.provider]]));
tx={readOnly:true,snapshots:owners,instance:other};assert.equal(invokeEntry(other,[0]),1);
assert.notEqual(bridge.finish(tx).batches[0].draws[0].mesh,ordered.draws[0].mesh,'module-local identities never alias generations');
closeInstance(fixed);closeInstance(other);
writeFileSync(join(output,'instances.json'),JSON.stringify(instances));
console.log('ok - actual Wasm fixed models share immutable colored prototypes, preserve ordered runs, regroup only declared opaque batches and isolate module identities');
console.log('ok - reflected and anisotropic model instances preserve normals and endpoints; singular copied current/prior bases and subnormal coefficients reject without replacing retained batches');

const settings={width:960,height:640,cellSize:40,pointer:{move:'move',confirm:'confirm'},viewportHandler:'viewport'};
const native=parseInputSettings(settings);
const resizeCalls=[],surface={style:{},getBoundingClientRect:()=>({width:1921,height:1081})};
const application=Object.assign(Object.create(BrowserApplication.prototype),
  {canvas:surface,inputSettings:native,manifest:{settings},local:(...args)=>resizeCalls.push(args),note:()=>{}});
const oldRatio=globalThis.devicePixelRatio;
try {
  for(const ratio of [1,1.25,2,3,4]) {
    globalThis.devicePixelRatio=ratio;application.resizeViewport();application.resizeViewport();
    assert.deepEqual([surface.width,surface.height],[Math.round(1921*ratio),Math.round(1081*ratio)]);
  }
  assert.deepEqual(application.viewport,[1921,1081]);
  assert.deepEqual([application.inputSettings.width,application.inputSettings.height],[1921,1081]);
  assert.equal(resizeCalls.length,1,'DPR-only changes do not dispatch logical viewport commands');
  const earlier={generation:'native',settings},next={generation:'replacement',settings:{...settings,width:640,height:480}};
  const replacement=parseInputSettings(next.settings);
  let discarded=0;application.reloadTicket=2;
  application.runtime={manifest:earlier,replace:async candidate=>{application.runtime.manifest=candidate;},
    initialize:async()=>{},discard:()=>discarded++};
  const priorSettings=application.inputSettings;
  await application.install(next,undefined,replacement,1);assert.equal(discarded,1);assert.equal(application.inputSettings,priorSettings);
  await application.install(next,undefined,replacement,2);assert.deepEqual([surface.width,surface.height],[7684,4324]);
  application.runtime.manifest=earlier;application.reconcileGeneration();
  assert.deepEqual([surface.width,surface.height],[7684,4324]);assert.equal(application.generation,'native');
  surface.getBoundingClientRect=()=>({width:3.9,height:1.9});application.applySettings(native);
  assert.deepEqual([surface.width,surface.height],[12,4]);assert.deepEqual(application.viewport,[3,1]);
  surface.getBoundingClientRect=()=>({width:.4,height:.2});globalThis.devicePixelRatio=1;application.resizeViewport();
  assert.deepEqual([surface.width,surface.height],[1,1]);assert.deepEqual(application.viewport,[1,1]);
} finally { if(oldRatio===undefined)delete globalThis.devicePixelRatio;else globalThis.devicePixelRatio=oldRatio; }
console.log('ok - native backing pixels follow DPR at odd and tiny sizes while logical input survives replacement and rollback');

const boundaryOwner={},boundaryBridge=createSceneBridge(functions=>functions,()=>tx),host=boundaryBridge.provider;
function beginBoundary() { tx={readOnly:true,instance:boundaryOwner,snapshots:owners}; }
function floatBits(value) { return new Int32Array(Float32Array.of(value).buffer)[0]; }
function boundaryInstance() {
  if(!host.prototype(1,0,0))host.vertex(0,0,0,0,0,floatBits(1),0,0);
  host.instance(...identityTransform.map(floatBits));host.normal(...identityNormal.map(floatBits));
}
function boundaryView(dependency=0,uniforms=32,reveal) {
  for(let index=0;index<uniforms;index++)host.uniform(index,0);
  host.background(0);host.batch(1,0);host.dependency(dependency);
  if(reveal)host.reveal(reveal.id,floatBits(reveal.x),floatBits(reveal.y),floatBits(reveal.radius),floatBits(reveal.edge),reveal.elapsed,reveal.duration);
  const reused=host.reuse();if(!reused)boundaryInstance();return reused;
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
assert.equal(fresh.batches[0].transforms,older.batches[0].transforms);assert.equal(older.batches[0].reveal.elapsed,200);
assert.equal(fresh.batches[0].reveal.elapsed,100);immutableGeometry(older);
assert.equal(fresh.batches[0].draws,older.batches[0].draws);
beginBoundary();boundaryView(2,32,reveal);host['begin-inset'](1,0,0,96,72);
boundaryView(2,32,{...reveal,x:2});host['end-inset']();
assert.throws(()=>boundaryBridge.finish(tx),/inconsistent scene reveal/);
beginBoundary();assert.equal(boundaryView(),1);boundaryBridge.finish(tx);
beginBoundary();assert.equal(boundaryView(0,32,{...reveal,edge:0}),1);
assert.equal(boundaryBridge.finish(tx).batches[0].reveal.edge,0);
beginBoundary();assert.throws(()=>boundaryView(0,32,{...reveal,edge:-.1}),/reveal extent/);
beginBoundary();assert.throws(()=>boundaryView(0,32,{...reveal,elapsed:-1}),/invalid scene reveal/);
console.log('ok - reveal wrappers preserve copied geometry and validate shared identities before publishing any view');

// Owner-clock metadata changes independently of geometry dependencies. The
// bridge never exports the authoritative snapshot itself to the renderer.
function clockBoundary(owner=1,key=1,duration=100,dependency=0) {
  for(let index=0;index<32;index++)host.uniform(index,0);
  host.background(0);host.batch(key,0);host.motion(duration);host['motion-clock'](owner);host.dependency(dependency);
  const reused=host.reuse();if(!reused){boundaryInstance();host.before(...identityTransform.map(floatBits));}
  return reused;
}
beginBoundary();clockBoundary();const clockInitial=boundaryBridge.finish(tx).batches[0];
assert.ok(Object.isFrozen(clockInitial.motionClock));assert.notEqual(clockInitial.motionClock,owners.get(1));
beginBoundary();tx.snapshots=new Map(owners).set(2,new Int32Array(1));clockBoundary();
assert.equal(boundaryBridge.finish(tx).batches[0],clockInitial,'client updates preserve a match clock and retained geometry');
beginBoundary();clockBoundary(1,1,100,1);const clockCamera=boundaryBridge.finish(tx).batches[0];
assert.equal(clockCamera.motionClock,clockInitial.motionClock);assert.notEqual(clockCamera.transforms,clockInitial.transforms);
beginBoundary();tx.snapshots=new Map(owners).set(1,new Int32Array(1));clockBoundary(1,1,100,1);
const clockTick=boundaryBridge.finish(tx).batches[0];assert.notEqual(clockTick.motionClock,clockCamera.motionClock);
assert.equal(clockTick.transforms,clockCamera.transforms,'new epochs do not force geometry uploads');
beginBoundary();clockBoundary(2,1,100,1);const clockClient=boundaryBridge.finish(tx).batches[0];
assert.notEqual(clockClient.motionClock,clockInitial.motionClock,'owners have separate epochs');
beginBoundary();tx.instance={};clockBoundary();assert.notEqual(boundaryBridge.finish(tx).batches[0].motionClock,clockInitial.motionClock);
beginBoundary();clockBoundary();host['begin-inset'](7,0,0,20,20);clockBoundary();host['end-inset']();
const clockViews=boundaryBridge.finish(tx);assert.equal(clockViews.batches[0].motionClock,clockViews.insets[0].batches[0].motionClock);
beginBoundary();clockBoundary();host['begin-inset'](7,0,0,20,20);clockBoundary(1,1,200);host['end-inset']();
assert.throws(()=>boundaryBridge.finish(tx),/inconsistent owner motion duration/);
beginBoundary();assert.throws(()=>clockBoundary(3),/owner snapshot/);
beginBoundary();assert.throws(()=>clockBoundary(1,1,0),/motion clock/);
beginBoundary();delete tx.snapshots;assert.throws(()=>clockBoundary(),/owner snapshot/);
console.log('ok - owner motion epochs survive camera rebuilds, advance without geometry changes, isolate modules and reject mixed durations');

function phasedBoundary(pulse) {
  beginBoundary();for(let index=0;index<32;index++)host.uniform(index,0);
  host.background(0);host.batch(9,0);host.opacity(floatBits(.8),pulse);
  const reused=host.reuse();if(!reused)boundaryInstance();
  return boundaryBridge.finish(tx).batches[0];
}
for(const pulse of [0,1,45001,360000]) {
  const batch=phasedBoundary(pulse);assert.equal(batch.pulse,pulse!==0);
  assert.equal(batch.pulsePhase,pulse?(pulse-1)*Math.PI/180000:0);
  assert.equal(phasedBoundary(pulse),batch);
}
for(const pulse of [-1,360001,.5])assert.throws(()=>phasedBoundary(pulse),/invalid batch opacity/);
console.log('ok - bounded pulse phases retain their exact dependency and preserve legacy phase-zero behavior');

// A rejected partial occurrence cannot publish its new prototype or evict the
// accepted frame. Omitting a mesh from the full frame releases its cache entry.
beginBoundary();boundaryView(71);const owned=boundaryBridge.finish(tx);
for(const [normal,error]of [[[1,-1,0,-1,1,0,0,0,1e-5],/singular copied scene/],
  [[1,0,0,0,1e-40,0,0,0,1],/subnormal scene normal/]]) {
  beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(1,0);host.dependency(72);host.reuse();
  host.prototype(1,0,0);host.instance(...identityTransform.map(floatBits));
  assert.throws(()=>host.normal(...normal.map(floatBits)),error);
  beginBoundary();assert.equal(boundaryView(71),1);assert.equal(boundaryBridge.finish(tx).batches[0],owned.batches[0]);
}
beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(1,0);host.dependency(72);host.reuse();
assert.equal(host.prototype(2,0,0),0);host.vertex(0,0,0,0,0,floatBits(1),0,0);host.instance(...identityTransform.map(floatBits));
assert.throws(()=>boundaryBridge.finish(tx),/incomplete scene instance/);
beginBoundary();assert.equal(boundaryView(71),1);assert.equal(boundaryBridge.finish(tx).batches[0],owned.batches[0]);
beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(3,0);host.reuse();boundaryBridge.finish(tx);
beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(1,0);host.reuse();
assert.equal(host.prototype(1,0,0),0);host.vertex(0,0,0,0,0,floatBits(1),0,0);host.instance(...identityTransform.map(floatBits));host.normal(...identityNormal.map(floatBits));
assert.notEqual(boundaryBridge.finish(tx).batches[0].draws[0].mesh,owned.batches[0].draws[0].mesh);
for(const [opacity,pulse,edge]of [[.5,0,0],[.5,1,0],[1,0,.1]]){
  beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(8,0);
  host.opacity(floatBits(opacity),pulse);host.unordered();if(edge)host.reveal(1,0,0,floatBits(1),floatBits(edge),0,100);
  assert.throws(()=>host.reuse(),/must be opaque/);
}
beginBoundary();for(let i=0;i<32;i++)host.uniform(i,0);host.background(0);host.batch(8,0);
assert.throws(()=>host.opacity(floatBits(1),1),/invalid batch opacity/); // A pulse requires translucency.
console.log('ok - failed instance parsing preserves the accepted frame; omitted prototypes are evicted and unsafe regrouping declarations reject');
