// Paired actual-Wasm CPU diagnostic. Keep timing runs separate from counted
// scalar calls and diagnostic expansion; neither measures physical GPU speed.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {expandBatch} from './scene-tools.mjs';

const [before,after,fixtureDirectory,output]=process.argv.slice(2);
if(!output)throw new Error('usage: instance-profile.mjs BEFORE-SOLO AFTER-SOLO FIXTURE-DIRECTORY OUTPUT.json');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const fixtureFile=join(fixtureDirectory,'grown-fixtures.json');
const fixtures={fresh:JSON.parse(readFileSync(join(fixtureDirectory,'fixtures.json'))).fresh,
  ...JSON.parse(readFileSync(fixtureFile))};
const command=(r,owner,binding,args=[])=>r.dispatch(owner,r.command(owner===1?'match':'client',binding,args));
async function load(path) {
  const {ReducerRuntime}=await import(pathToFileURL(join(resolve(path),'lib/application/runtime.mjs')));
  const manifest=JSON.parse(readFileSync(join(path,'manifest.json'))),bytes=readFileSync(join(path,manifest.module));
  const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);
  await command(r,2,'viewport',[390,844]);await command(r,2,'center');return{r,manifest,bytes,path,local:r.snapshot(2)};
}
const variants=[await load(before),await load(after)];
const retained=variants[0].r.view(),committed=variants[0].r.instance,saved=variants[0].r.snapshot(1);
assert.throws(()=>variants[0].r.prepare(variants[1].bytes,variants[1].manifest),/missing provider function: snail\.scene\//);
assert.equal(variants[0].r.instance,committed);assert.deepEqual(variants[0].r.snapshot(1),saved);
assert.deepEqual(variants[0].r.view(),retained);
async function reset(item,words) {await item.r.restore(1,words);await item.r.restore(2,item.local);return item.r.view();}
const operations={view:r=>r.view(),tickAndView:async r=>{await command(r,1,'advance');return r.view();},
  cameraAndView:async(r,index)=>{await command(r,2,'drift',[index%2?1:-1,0]);return r.view();}};
function triangleSignature(batch) {
  const counts=new Map();
  for(let i=0;i<batch.indices.length;i+=3) {
    const key=batch.indices.slice(i,i+3).flatMap(index=>batch.vertices.slice(index*10,index*10+10))
      .map(value=>Math.round(value*1000)).join(',');
    counts.set(key,(counts.get(key)??0)+1);
  }
  return [...counts].sort(([a],[b])=>a.localeCompare(b));
}
let maxEndpointError=0,equivalence=0;
function compareGeometry(left,right) {
  assert.equal(right.insets,undefined);assert.deepEqual(left.uniforms,right.uniforms);
  assert.deepEqual(left.batches.map(b=>b.key),right.batches.map(b=>b.key));
  for(let index=0;index<left.batches.length;index++) {
    const a=left.batches[index],b=expandBatch(right.batches[index]);
    for(const key of ['opacity','pulse','pulsePhase','duration','reveal'])assert.deepEqual(a[key],b[key]);
    if(b.unordered)assert.deepEqual(triangleSignature(a),triangleSignature(b));
    else {
      assert.deepEqual(a.indices,b.indices);assert.equal(a.vertices.length,b.vertices.length);
      for(const key of ['vertices','previous'])for(let i=0;i<(a[key]?.length??0);i++) {
        const difference=Math.abs(a[key][i]-b[key][i]);maxEndpointError=Math.max(maxEndpointError,difference);
        assert.ok(difference<0.00005,`batch ${a.key} ${key}[${i}] differs by ${difference}`);
      }
    }
  }
}
for(const [fixture,words] of Object.entries(fixtures)) {
  for(const item of variants)await reset(item,words);
  for(let index=0;index<6;index++)for(const operation of ['tickAndView','cameraAndView']) {
    const frames=[];for(const item of variants)frames.push(await operations[operation](item.r,index));
    const [{scene:left,...oldUI},{scene:right,...newUI}]=frames;
    assert.deepEqual(oldUI,newUI,`${fixture}/${operation}/${index} UI`);compareGeometry(left,right);
    for(const owner of [1,2])assert.deepEqual(variants[0].r.snapshot(owner),variants[1].r.snapshot(owner));
    equivalence++;
  }
}
console.log(JSON.stringify({equivalence,maxEndpointError}));
function summary(values) {
  values.sort((a,b)=>a-b);return{n:values.length,median:values[Math.floor(values.length/2)],p95:values[Math.floor(values.length*.95)]};
}
const rounds=[];
for(let round=0;round<(process.argv.includes('--verify-only')?0:4);round++)for(const variant of round%2?[1,0]:[0,1]) {
  const item=variants[variant],measurements=[];
  for(const [fixture,words] of Object.entries(fixtures))for(const [operation,work] of Object.entries(operations)) {
    await reset(item,words);for(let i=0;i<5;i++)await work(item.r,i);
    const times=[];for(let i=0;i<25;i++){const start=performance.now();await work(item.r,i);times.push(performance.now()-start);}
    measurements.push({fixture,operation,...summary(times)});
  }
  const result={round,variant,measurements};rounds.push(result);console.log(JSON.stringify(result));
}
// Count transferred data by immutable identity after warm-up. This includes
// reused model bytes once and occurrence bytes only for changed batches.
function transfer(scene,previous) {
  const priorBatches=new Map(previous.batches.map(batch=>[batch.key,batch]));
  const priorMeshes=new Set(previous.batches.flatMap(batch=>batch.draws?.map(draw=>draw.mesh)??[]));
  const seen=new Set();let vertices=0,indices=0,instances=0,motion=0,draws=0;
  for(const batch of scene.batches) {
    const prior=priorBatches.get(batch.key);
    if(!batch.draws) {
      if(batch.vertices!==prior?.vertices){vertices+=batch.vertices.length;indices+=batch.indices.length;motion+=batch.previous?.length??0;}
      if(batch.indices.length)draws++;continue;
    }
    for(const {mesh} of batch.draws)if(!seen.has(mesh)) {
      seen.add(mesh);if(!priorMeshes.has(mesh)){vertices+=mesh.vertices.length;indices+=mesh.indices.length;}
    }
    if(batch.transforms!==prior?.transforms){instances+=batch.transforms.length+batch.normals.length;motion+=batch.previous?.length??0;}
    draws+=batch.draws.length;
  }
  return{vertexBytes:vertices*4,indexBytes:indices*4,instanceBytes:instances*4,motionBytes:motion*4,draws};
}
const work=[];
for(let variant=0;variant<2;variant++)for(const [fixture,words] of Object.entries(fixtures)) {
  const item=variants[variant];let previous=(await reset(item,words)).scene;
  for(const operation of ['view','cameraAndView','tickAndView']) {
    const next=(await operations[operation](item.r,0)).scene;
    work.push({variant,fixture,operation,...transfer(next,previous)});previous=next;
  }
}
const result={kind:'shared-host actual-Wasm CPU diagnostic; uninstrumented alternating timings; separate identity-based transfer counts',
  node:process.version,fixtureSha256:hash(readFileSync(fixtureFile)),oldProviderRejectsWithoutReplacement:true,equivalence,maxEndpointError,
  packages:variants.map(({path,manifest,bytes})=>({path,generation:manifest.generation,wasmBytes:bytes.length,wasmSha256:hash(bytes),
    runtimeSha256:hash(readFileSync(join(path,'lib/application/runtime.mjs'))),
    bridgeSha256:hash(readFileSync(join(path,'lib/draw3d/bridge.mjs')))})),rounds,work};
writeFileSync(output,JSON.stringify(result,null,2));for(const item of variants)await item.r.close();
