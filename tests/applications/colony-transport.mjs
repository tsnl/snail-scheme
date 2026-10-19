// The compiled Scheme reducer owns every transition. Kruskal is an independent
// small-graph oracle for its geometric minimum, not a second game simulator.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,routeCell,setWorker, addEnemy, withdrawReserves} from './colony-state.mjs';

export async function checkTransport(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function step(r,count=1) {
    for(let i=0;i<count;i++) {
      await fixtureCall(r,'advance'); const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    }
  }
  function fund(world) {withdrawReserves(world, 10000);world.delivered+=10000;world.ore+=10000;}
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
    withdrawReserves(changed, 48);Object.assign(changed.rails[0],{cargo:32,progress:16});
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
    await restoreColony(r,world);await step(r);const loaded=state(r);withdrawReserves(loaded, 16);
    Object.assign(loaded.rails[0],{returning:1,progress:80});Object.assign(loaded.rails[1],{cargo:16,progress:16});
    await restoreColony(r,loaded);await step(r);const next=state(r);
    assert.equal(next.rails[0].returning,1);assert.equal(next.rails[0].progress,48);
    assert.equal(next.rails[1].cargo,16);assert.equal(next.rails[1].progress,48);
    assert.deepEqual(next.rails.map(rail=>rail.path),loaded.rails.map(rail=>rail.path));await r.close();
  });
  await test('worker flights lift, cross a direct diagonal and land before delivering cargo',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,24);
    await restoreColony(r,world);await step(r);const riding=state(r),route=riding.rails[0].path;
    assert.equal(route.length,2);withdrawReserves(riding,16);
    setWorker(riding,0,{x:12,y:24,job:2,cargo:16,path:[8+22*48]});
    await restoreColony(r,riding);const start=[riding.bots[0].x,riding.bots[0].y];
    await step(r);let bot=state(r).bots[0];assert.deepEqual([bot.x,bot.y],start);
    assert.equal(bot.flight.length,1);assert.equal(bot.flight[0].progress,80);assert.equal(bot.flight[0].speed,80);
    await step(r);assert.deepEqual([state(r).bots[0].x,state(r).bots[0].y],start);
    await step(r);bot=state(r).bots[0];assert.ok(bot.x<start[0]&&bot.y<start[1]);
    assert.equal(bot.cargo,16);assert.equal(state(r).delivered,riding.delivered);
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    while(state(r).bots[0].flight.length)await step(r);
    bot=state(r).bots[0];assert.deepEqual([bot.x,bot.y],Object.values(pixelAt(riding,8,22)));
    assert.equal(bot.cargo,16);assert.equal(state(r).delivered,riding.delivered);
    await step(r);assert.equal(state(r).delivered,riding.delivered+16);await r.close();
  });
  await test('freight speed doubles at each shared tower level and keeps its 32-ore load',async()=>{
    for(const level of [1,2,3]) {
      const r=await fresh(),world=state(r);fund(world);depot(world,16,22,level);
      await restoreColony(r,world);await step(r);const loaded=state(r);withdrawReserves(loaded, 32);loaded.rails[0].cargo=32;
      await restoreColony(r,loaded);await step(r);assert.equal(state(r).rails[0].progress,32*2**(level-1));
      assert.equal(state(r).rails[0].cargo,32);await r.restore(1,r.snapshot(1));await r.close();
    }
  });
  await test('a committed flight survives station destruction and stale queued flights replan on the ground',async()=>{
    const r=await fresh(),world=state(r);fund(world);const tower=depot(world,12,22,3);
    await restoreColony(r,world);await step(r);const riding=state(r);withdrawReserves(riding,32);
    setWorker(riding,0,{x:12,y:22,job:2,cargo:16,path:[8+22*48]});
    setWorker(riding,1,{x:12,y:22,job:2,cargo:16,path:[8+22*48]});
    await restoreColony(r,riding);await step(r);const flying=state(r);
    assert.equal(flying.bots[0].flight.length,1);setWorker(flying,1,{x:12,y:22,job:2,cargo:16,path:[8+22*48]});
    flying.buildings[0].hp=7;flying.tick=9;flying.lastRevealTick=-100;
    await restoreColony(r,flying);await addEnemy(r,{x:12,y:22,target:tower.id});await step(r);
    const lost=state(r);assert.equal(lost.buildings.length,0);assert.equal(lost.rails.length,0);
    assert.equal(lost.bots[0].flight.length,1);assert.equal(lost.bots[0].cargo,16);
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    lost.enemies=[];setWorker(lost,1,{x:12,y:22,job:2,cargo:16,path:[8+22*48]});
    await restoreColony(r,lost);const waiting=lost.bots[1].x;await step(r);
    assert.equal(state(r).bots[1].flight.length,0);assert.equal(state(r).bots[1].x,waiting);
    assert.equal(state(r).bots[1].path.length,4);await step(r,40);
    assert.equal(state(r).delivered,riding.delivered+32);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('legacy routed freight returns once to its source and starts a straight replacement',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);
    await restoreColony(r,world);await step(r);const restored=state(r);
    const path=[[12,22],[12,23],[11,23],[10,23],[9,23],[8,23],[8,22]].map(([x,y])=>routeCell(restored,x,y));
    withdrawReserves(restored,16);Object.assign(restored.rails[0],{cargo:16,progress:16,path});
    await restoreColony(r,restored);await step(r);
    assert.deepEqual(state(r).rails[0].path,[path[0],path.at(-1)]);assert.equal(state(r).rails[0].progress,0);
    assert.equal(state(r).rails[0].cargo,16);assert.equal(state(r).lostOre,0);
    await step(r,30);assert.equal(state(r).delivered,restored.delivered+16);await r.close();
  });
  await test('links use the larger endpoint reveal radius and ignore globally remembered visibility',async()=>{
    for(const [x,level,connected] of [[16,1,true],[18,1,false],[18,2,true],[19,3,false]]) {
      const r=await fresh(),world=state(r);fund(world);depot(world,x,22,level);
      world.surveys.push({...at(world,12,22),radius:10});await restoreColony(r,world);await step(r);
      assert.equal(state(r).rails.length,connected?1:0);await r.close();
    }
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);const far=depot(world,22,22,2);
    await restoreColony(r,world);await step(r);assert.ok(state(r).rails.some(rail=>rail.source===far.id));await r.close();
  });
  await test('construction flights retain paid kits and their local source through save and landing',async()=>{
    const r=await fresh(),world=state(r);fund(world);const source=depot(world,12,22);depot(world,16,22);
    await restoreColony(r,world);await step(r);const supplied=state(r);
    withdrawReserves(supplied,50);supplied.buildings.find(site=>site.id===source.id).stock=50;
    setWorker(supplied,0,{x:12,y:22});await restoreColony(r,supplied);await fixtureCall(r,'fortify',[16,24]);
    let carrier;
    for(let tick=0;tick<100&&!carrier;tick++) {
      await step(r);carrier=state(r).bots.find(bot=>bot.job===3&&bot.flight.length&&bot.source===source.id);
    }
    assert.ok(carrier,'a local paid construction kit boards the endpoint flight');
    const captured={cargo:carrier.cargo,source:carrier.source,target:carrier.target,order:carrier.order};
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    do {
      const bot=state(r).bots.find(bot=>bot.id===carrier.id);
      assert.deepEqual({cargo:bot.cargo,source:bot.source,target:bot.target,order:bot.order},captured);
      await step(r);
    } while(state(r).bots.find(bot=>bot.id===carrier.id).flight.length);
    await step(r,100);assert.equal(state(r).buildings.find(site=>site.id===carrier.target).stage,2);
    assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('flight decoding rejects malformed coordinates, speed and progress without replacing the world',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);
    await restoreColony(r,world);await step(r);const riding=state(r);withdrawReserves(riding,16);
    setWorker(riding,0,{x:12,y:22,job:2,cargo:16,path:[8+22*48]});await restoreColony(r,riding);await step(r);
    const saved=r.snapshot(1);
    for(const edit of [bot=>bot.x++,bot=>bot.flight[0].speed=81,bot=>bot.flight[0].progress=-1,
      bot=>bot.flight[0].destination=bot.flight[0].origin,bot=>bot.flight.push({...bot.flight[0]})]) {
      const invalid=colony(saved);edit(invalid.bots[0]);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('isolated surveyed depots keep stock without an impossible connection or a stranded worker',async()=>{
    const r=await fresh(),world=state(r);fund(world);const site=depot(world,16,22);
    // Ground immediately around a remote depot is known, but no surveyed
    // corridor reaches it. The seed's original hub is deliberately far away.
    const remote={x:2,y:2};Object.assign(site,remote,{aimX:100,aimY:100,stock:16});withdrawReserves(world, 16);
    world.surveys=[world.surveys[0],{...remote,radius:7}];
    await restoreColony(r,world);await step(r,2);
    assert.deepEqual(state(r).rails,[]);assert.equal(state(r).buildings[0].stock,16);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('paused legacy track cells leave the single solid cable batch unchanged',async()=>{
    const r=await fresh(),world=state(r);fund(world);depot(world,12,22);
    await restoreColony(r,world);await step(r);await fixtureCall(r,'pause-colony',[1]);
    const clean=state(r),before=r.view().scene.batches.filter(batch=>batch.key>=20&&batch.key<28);
    const a=routeCell(clean,8,23);clean.tracks=[a*32+17,(a+1)*32+20];await restoreColony(r,clean);
    const after=r.view().scene.batches.filter(batch=>batch.key>=20&&batch.key<28);
    assert.deepEqual(after.map(batch=>batch.key),[20]);
    for(const [index,batch] of after.entries()) {
      assert.equal(batch,before[index]);assert.equal(batch.pulsePhase,0);assert.equal(batch.pulse,false);
      assert.equal(batch.transforms,before[index].transforms);assert.equal(batch.draws,before[index].draws);
    }
    assert.equal(after[0].opacity,1);
    const saved=r.snapshot(1);await step(r);assert.deepEqual(r.snapshot(1),saved);
    await fixtureCall(r,'pause-colony',[0]);await step(r);assert.deepEqual(state(r).tracks,[]);await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkTransport(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} live transport checks passed`);
}
