// The compiled Scheme reducer owns every transition. Kruskal is an independent
// small-graph oracle for its geometric minimum, not a second game simulator.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,routeCell,setWorker} from './colony-state.mjs';

export async function checkTransport(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function step(r,count=1) {
    for(let i=0;i<count;i++) {
      await fixtureCall(r,'advance'); const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    }
  }
  function fund(world) {world.produced+=10000;world.delivered+=10000;world.ore+=10000;}
  function depot(world,x,y,level=1) {
    const cell=at(world,x,y),point=pixelAt(world,x,y),cost=25*level;
    const site={id:world.nextId++,kind:3,...cell,level,hp:90,stock:0,stage:2,cooldown:0,
      aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
    world.buildings.push(site);world.started=true;world.spent+=cost;world.ore-=cost;
    world.surveys.push({...cell,radius:level===1?7:10});return site;
  }
  const topology=world=>world.rails.map(({source,parent})=>[source,parent]);
  function oracle(world) {
    const nodes=[{id:0,...at(world,8,22)},...world.buildings.filter(site=>site.kind===3)];
    const edges=nodes.flatMap((a,i)=>nodes.slice(i+1).map(b=>({a:a.id,b:b.id,cost:(a.x-b.x)**2+(a.y-b.y)**2})))
      .sort((a,b)=>a.cost-b.cost||Math.min(a.a,a.b)-Math.min(b.a,b.b)||Math.max(a.a,a.b)-Math.max(b.a,b.b));
    const parents=new Map(nodes.map(node=>[node.id,node.id]));
    const root=id=>parents.get(id)===id?id:root(parents.get(id));let cost=0;
    for(const edge of edges)if(root(edge.a)!==root(edge.b)){parents.set(root(edge.a),root(edge.b));cost+=edge.cost;}
    return cost;
  }
  function treeCost(world) {
    const nodes=new Map([{id:0,...at(world,8,22)},...world.buildings].map(site=>[site.id,site]));
    return world.rails.reduce((total,rail)=>{const a=nodes.get(rail.source),b=nodes.get(rail.parent);return total+(a.x-b.x)**2+(a.y-b.y)**2;},0);
  }
  await test('each tick builds a deterministic minimum spanning tree independent of node age or prior rail order',async()=>{
    const r=await fresh(),world=state(r);fund(world);
    for(const [x,y] of [[16,22],[12,22],[12,25],[15,25]])depot(world,x,y);
    await restoreColony(r,world);await step(r);const first=state(r);
    assert.equal(first.rails.length,4);assert.equal(treeCost(first),oracle(first));
    assert.ok(first.rails.some(rail=>rail.parent>rail.source),'a newer depot may be the older depot’s parent');
    await r.restore(1,r.snapshot(1));
    const shuffled=state(r);shuffled.rails.reverse();await restoreColony(r,shuffled);await step(r);
    assert.deepEqual(topology(state(r)),topology(first));await step(r,3);assert.deepEqual(topology(state(r)),topology(first));
    assert.deepEqual(state(r).tracks,[]);await r.close();
  });
  await test('new depot rerouting refunds source freight once and preserves a worker between grid centers',async()=>{
    const r=await fresh(),world=state(r);fund(world);const old=depot(world,16,22);
    await restoreColony(r,world);await step(r);const changed=state(r);
    changed.produced+=48;Object.assign(changed.rails[0],{cargo:32,progress:16});
    setWorker(changed,0,{x:15,y:22,job:2,cargo:16,path:[14,13,12,11,10,9,8].map(x=>x+22*48)});
    changed.bots[0].x-=8;const workerX=changed.bots[0].x,newer=depot(changed,12,22);
    await restoreColony(r,changed);await step(r);const rerouted=state(r),edge=rerouted.rails.find(rail=>rail.source===old.id);
    assert.equal(edge.parent,newer.id);assert.equal(edge.cargo,32);assert.equal(edge.progress,0);
    assert.equal(rerouted.lostOre,0);assert.ok(rerouted.bots[0].x<workerX);assert.equal(rerouted.bots[0].cargo,16);
    await step(r,80);assert.equal(state(r).delivered,world.delivered+48);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('save decoding rejects a two-depot cycle and missing parent despite valid endpoint paths',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);depot(world,16,22);
    await restoreColony(r,world);await step(r);const valid=r.snapshot(1),cycle=state(r);
    cycle.rails[0].parent=cycle.rails[1].source;cycle.rails[0].path=cycle.rails[1].path.toReversed();
    await assert.rejects(()=>restoreColony(r,cycle),WebAssembly.RuntimeError);assert.deepEqual(r.snapshot(1),valid);
    const missing=state(r);missing.rails.shift();
    await assert.rejects(()=>restoreColony(r,missing),WebAssembly.RuntimeError);assert.deepEqual(r.snapshot(1),valid);
    await r.close();
  });
  await test('unchanged directed routes preserve loaded and returning shuttle progress across recomputation',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);depot(world,16,22);
    await restoreColony(r,world);await step(r);const loaded=state(r);loaded.produced+=16;
    Object.assign(loaded.rails[0],{returning:1,progress:80});Object.assign(loaded.rails[1],{cargo:16,progress:16});
    await restoreColony(r,loaded);await step(r);const next=state(r);
    assert.equal(next.rails[0].returning,1);assert.equal(next.rails[0].progress,48);
    assert.equal(next.rails[1].cargo,16);assert.equal(next.rails[1].progress,48);
    assert.deepEqual(next.rails.map(rail=>rail.path),loaded.rails.map(rail=>rail.path));await r.close();
  });
  await test('cart budgets cross corners but defer delivery to the following job transition',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,24);
    await restoreColony(r,world);await step(r);const riding=state(r),route=riding.rails[0].path;
    const corner=route.findIndex((cell,i)=>i>0&&i+1<route.length&&Math.abs(cell-route[i-1])!==Math.abs(route[i+1]-cell));
    assert.ok(corner>0);const start=route[corner-1];riding.produced+=16;
    Object.assign(riding.bots[0],{x:(start%128)*40+20,y:Math.floor(start/128)*40+20,job:2,target:0,cargo:16,path:route.slice(corner)});
    await restoreColony(r,riding);await step(r);const next=state(r),point=route[corner+1];
    assert.deepEqual([next.bots[0].x,next.bots[0].y],[(point%128)*40+20,Math.floor(point/128)*40+20]);
    assert.equal(next.bots[0].cargo,16);assert.equal(next.delivered,riding.delivered);
    await step(r,20);assert.equal(state(r).delivered,riding.delivered+16);await r.close();
  });
  await test('freight speed doubles at each shared tower level and keeps its 32-ore load',async()=>{
    for(const level of [1,2,3]) {
      const r=await fresh(),world=state(r);fund(world);depot(world,16,22,level);
      await restoreColony(r,world);await step(r);const loaded=state(r);loaded.produced+=32;loaded.rails[0].cargo=32;
      await restoreColony(r,loaded);await step(r);assert.equal(state(r).rails[0].progress,32*2**(level-1));
      assert.equal(state(r).rails[0].cargo,32);await r.restore(1,r.snapshot(1));await r.close();
    }
  });
  await test('maximum-speed carts follow every segment of a U-shaped route before processing arrival',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22,3);
    await restoreColony(r,world);await step(r);const riding=state(r);
    const path=[[12,22],[12,23],[12,24],[11,24],[10,24],[9,24],[8,24],[8,23],[8,22]]
      .map(([x,y])=>routeCell(riding,x,y));
    riding.rails[0].path=path;riding.produced+=16;
    const start=path[0];Object.assign(riding.bots[0],{x:(start%128)*40+20,y:Math.floor(start/128)*40+20,
      job:2,target:0,cargo:16,path:path.slice(1)});
    await restoreColony(r,riding);await step(r);const arrived=state(r),hub=pixelAt(arrived,8,22);
    assert.deepEqual([arrived.bots[0].x,arrived.bots[0].y],[hub.x,hub.y]);
    assert.deepEqual(arrived.bots[0].path,[]);assert.equal(arrived.bots[0].cargo,16);
    assert.equal(arrived.delivered,riding.delivered);await step(r);assert.equal(state(r).delivered,riding.delivered+16);
    await r.close();
  });
  await test('restoring an alternate legal route retains its own cargo and progress despite a warm path cache',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);
    await restoreColony(r,world);await step(r);const restored=state(r);
    const path=[[12,22],[12,23],[11,23],[10,23],[9,23],[8,23],[8,22]].map(([x,y])=>routeCell(restored,x,y));
    restored.produced+=16;Object.assign(restored.rails[0],{cargo:16,progress:16,path});
    await restoreColony(r,restored);await step(r);
    assert.deepEqual(state(r).rails[0].path,path);assert.equal(state(r).rails[0].progress,48);
    assert.equal(state(r).rails[0].cargo,16);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('isolated surveyed depots keep stock without an impossible connection or a stranded worker',async()=>{
    const r=await fresh(),world=state(r);fund(world);const site=depot(world,16,22);
    // Ground immediately around a remote depot is known, but no surveyed
    // corridor reaches it. The seed's original hub is deliberately far away.
    const remote={x:2,y:2};Object.assign(site,remote,{aimX:100,aimY:100,stock:16});world.produced+=16;
    world.surveys=[world.surveys[0],{...remote,radius:7}];
    await restoreColony(r,world);await step(r,2);
    assert.deepEqual(state(r).rails,[]);assert.equal(state(r).buildings[0].stock,16);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('paused legacy track cells are ignored and static flow meshes retain display-clock phases',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);
    await restoreColony(r,world);await step(r);await fixtureCall(r,'pause-colony',[1]);
    const clean=state(r),before=r.view().scene.batches.filter(batch=>batch.key>=20&&batch.key<28);
    const a=routeCell(clean,8,23);clean.tracks=[a*32+17,(a+1)*32+20];await restoreColony(r,clean);
    const after=r.view().scene.batches.filter(batch=>batch.key>=20&&batch.key<28);
    assert.equal(after.length,8);assert.ok(after.every((batch,i)=>Math.abs(batch.pulsePhase-i*Math.PI/4)<1e-12));
    for(let i=0;i<8;i++){assert.equal(after[i].transforms,before[i].transforms);assert.equal(after[i].draws,before[i].draws);assert.equal(after[i].pulse,true);}
    const saved=r.snapshot(1);await step(r);assert.deepEqual(r.snapshot(1),saved);
    await fixtureCall(r,'pause-colony',[0]);await step(r);assert.deepEqual(state(r).tracks,[]);await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkTransport(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} live transport checks passed`);
}
