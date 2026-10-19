// Execute the product's fixed-model declarations through the real Wasm bridge.
import assert from 'node:assert/strict';
import {colony,restoreColony,at,pixelAt} from './colony-state.mjs';

const meshes=scene=>new Map(scene.batches.flatMap(batch=>batch.draws.map(draw=>[draw.mesh.key,draw.mesh])));
export async function checkInstancing(test,fresh) {
  await test('tiles, towers and workers share fixed colored models across ticks and camera motion',async()=>{
    const r=await fresh(),world=colony(r.snapshot(1));world.started=true;
    world.surveys.unshift({...world.surveys[0]});
    for(const x of [10,11,12]) {
      const point=at(world,x,22),aim=pixelAt(world,x,22);
      world.buildings.push({id:world.nextId++,kind:3,...point,level:1,hp:90,stock:0,stage:2,
        cooldown:0,aimX:aim.x,aimY:aim.y,armed:0,source:0,moveX:-1,moveY:-1});
      world.surveys.push({...point,radius:7});world.spent+=25;world.ore-=25;
    }
    await restoreColony(r,world);const first=r.view().scene,actors=first.batches.find(batch=>batch.key===3);
    assert.ok(actors.draws.some(draw=>draw.count===3&&draw.mesh.vertices.length>72*10),'three complete towers share one model');
    assert.ok(actors.draws.some(draw=>draw.count===3&&draw.mesh.vertices.length===72*10),'three colored worker bodies share one model');
    assert.ok(first.batches.some(batch=>batch.unordered&&batch.draws.some(draw=>draw.count>20&&draw.mesh.vertices.length===40)),
      'terrain colors batch repeated fixed tile meshes');
    assert.ok(first.batches.every(batch=>!('vertices' in batch)),'product batches carry occurrences, never expanded vertices');
    const prototypes=meshes(first);world.tick++;
    await restoreColony(r,world);const next=r.view().scene;
    assert.notEqual(next.batches.find(batch=>batch.key===3).transforms,actors.transforms);
    for(const [key,mesh] of meshes(next))assert.equal(mesh,prototypes.get(key),'new tick reuses every fixed prototype');
    await r.dispatch(2,r.command('client','drift',[1,0]));const camera=r.view().scene;
    for(const batch of camera.batches) {
      const previous=next.batches.find(value=>value.key===batch.key);
      assert.equal(batch.transforms,previous.transforms);assert.equal(batch.draws,previous.draws);
    }
    assert.equal(camera.insets,undefined);await r.close();
  });
}
