// Run with --stack-size=256: a full revealed camera window must fit a small
// engine stack even though its terrain list is much larger than an opening view.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,restoreClient,restoreColony,fixtureCall,siteAt} from '../applications/colony-state.mjs';

const directory=process.argv[2],manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module));
async function fresh() {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,manifest));
  await runtime.initialize(1);await runtime.initialize(2);return runtime;
}
const terrain=scene=>scene.batches.find(batch=>batch.key===1);
async function inspect(runtime,changes) {
  await restoreClient(runtime,{...client(runtime.snapshot(2)),...changes,homing:false});
  const scene=runtime.view().scene;
  assert.equal(terrain(runtime.view().scene).transforms,terrain(scene).transforms,'a repeated frame retains terrain');
  return scene;
}

const runtime=await fresh();
try {
  const opening=runtime.snapshot(1),active=terrain(runtime.view().scene).transforms.length;
  await fixtureCall(runtime,'resign');
  assert.deepEqual(colony(runtime.snapshot(1)),{...colony(opening),outcome:4});
  const resigned=runtime.snapshot(1);
  assert.ok(terrain(runtime.view().scene).transforms.length>active,'resignation reveals terrain beyond opening sight');
  for(const [width,height] of [[960,640],[390,844],[1280,1280]])
    for(const scale of [500,1000,1500,2000,4000,16000])
      for(const heading of [0,45000,90000,135000,180000,225000,270000,315000])
        await inspect(runtime,{width,height,scale,heading});
  assert.deepEqual(runtime.snapshot(1),resigned,'camera inspection never changes the frozen world');
  console.log('ok - resignation reveals 144 desktop/portrait/square camera views with a bounded stack and retained repeated frames');

  const reloaded=await fresh();
  try {
    await reloaded.restore(1,resigned);assert.deepEqual(reloaded.snapshot(1),resigned);
    for(const [cameraX,cameraY] of [[-3000,-3000],[83000,83000],[40000,40000]])
      await inspect(reloaded,{cameraX,cameraY,scale:500});
    const outside=await inspect(reloaded,{cameraX:-3000,cameraY:-3000,width:1,height:8192,heading:45000});
    assert.equal(terrain(outside).transforms.length,0,'a clipped empty window emits no terrain');
    await fixtureCall(reloaded,'advance');await fixtureCall(reloaded,'resign');
    assert.deepEqual(reloaded.snapshot(1),resigned,'a restored World15 resignation remains frozen');
    await fixtureCall(reloaded,'new-run');assert.equal(colony(reloaded.snapshot(1)).outcome,0);reloaded.view();
  } finally {await reloaded.close();}
  console.log('ok - a resigned World15 save reloads, renders clipped edge windows and restarts cleanly');

  await runtime.restore(1,opening);await fixtureCall(runtime,'extract',[12,20]);
  for(let tick=0;tick<300&&siteAt(colony(runtime.snapshot(1)),12,20).stage!==2;tick++)
    await fixtureCall(runtime,'advance');
  assert.equal(siteAt(colony(runtime.snapshot(1)),12,20).stage,2);
  const grown=colony(runtime.snapshot(1));assert.ok(grown.tick>0);
  for(const outcome of [4,1]) {
    await restoreColony(runtime,grown);
    if(outcome===4)await fixtureCall(runtime,'resign');
    else await restoreColony(runtime,{...grown,outcome:1,hull:0});
    const saved=runtime.snapshot(1);
    await inspect(runtime,{width:390,height:844,scale:2000,heading:0});
    await runtime.restore(1,saved);runtime.view();assert.deepEqual(runtime.snapshot(1),saved);
  }
  console.log('ok - a worker-built colony reveals after resignation or restored defeat without changing its World15 snapshot');
} finally {await runtime.close();}
