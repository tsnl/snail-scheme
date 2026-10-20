// Mixed stations share source ownership; a mine's 120-unit buffer includes refunds.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,withdrawReserves,routeCell,MAP_WIDTH} from './colony-state.mjs';

export async function checkExtractorTransport(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  function station(world,x,y,kind=3) {
    const point=pixelAt(world,x,y),site={id:world.nextId++,kind,...at(world,x,y),level:1,hp:kind===1?140:90,
      stock:0,stage:2,cooldown:0,aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
    world.buildings.push(site);world.spent+=25;world.ore-=25;world.surveys.push({...at(world,x,y),radius:7});return site;
  }
  async function check(r) {
    const world=state(r),balance=colonyBalance(world);assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);return world;
  }
  async function step(r,n=1){for(let i=0;i<n;i++){await fixtureCall(r,'advance');await check(r);}return state(r);}
  async function setup(child=false) {
    const r=await fresh(),world=state(r);world.started=true;
    const mine=station(world,12,20,1),tower=child?station(world,16,20):null;
    await restoreColony(r,world);await step(r);return {r,mine,tower};
  }
  function resetWorkers(world){for(let i=0;i<world.bots.length;i++)setWorker(world,i);}
  const length=rail=>128+Math.floor(Math.hypot(rail.path[0]%MAP_WIDTH-rail.path[1]%MAP_WIDTH,Math.floor(rail.path[0]/MAP_WIDTH)-Math.floor(rail.path[1]/MAP_WIDTH))*40);
  await test('full extractor buffers keep arriving freight source-owned until the upstream shuttle frees capacity',async()=>{
    const {r,mine,tower}=await setup(true);try {
      const w=state(r),out=w.rails.find(edge=>edge.source===mine.id),incoming=w.rails.find(edge=>edge.source===tower.id);
      assert.equal(incoming.parent,mine.id);resetWorkers(w);withdrawReserves(w,152);
      w.buildings[0].stock=88;Object.assign(out,{cargo:32,progress:0});Object.assign(incoming,{cargo:32,progress:length(incoming)});
      await restoreColony(r,w);await step(r);const waiting=state(r);
      assert.equal(waiting.rails.find(edge=>edge.source===tower.id).cargo,32);assert.equal(waiting.buildings[0].stock,88);
      const released=state(r),upstream=released.rails.find(edge=>edge.source===mine.id);upstream.progress=length(upstream)-1;
      await restoreColony(r,released);await step(r);const delivered=state(r);
      assert.equal(delivered.delivered,w.delivered+32);assert.equal(delivered.buildings[0].stock,120);
      assert.equal(delivered.rails.find(edge=>edge.source===tower.id).cargo,0);assert.equal(delivered.lostOre,0);
    }finally{await r.close();}
  });
  await test('rerouting a loaded extractor reserves its freight room before production and recovers each unit once',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);resetWorkers(w);withdrawReserves(w,120);w.buildings[0].stock=88;
      Object.assign(w.rails[0],{cargo:32,progress:16});setWorker(w,0,{x:12,y:20,job:8,target:mine.id});w.tick=9;
      const nearer=station(w,10,20);await restoreColony(r,w);await step(r);const next=state(r),rail=next.rails.find(edge=>edge.source===mine.id);
      assert.equal(rail.parent,nearer.id);assert.equal(next.produced,w.produced);assert.equal(next.lostOre,0);
      assert.equal(next.buildings.find(site=>site.id===mine.id).stock+rail.cargo,120);
      const invalid=state(r);withdrawReserves(invalid,1);invalid.buildings.find(site=>site.id===mine.id).stock++;
      const before=r.snapshot(1);await assert.rejects(()=>restoreColony(r,invalid));assert.deepEqual(r.snapshot(1),before);
    }finally{await r.close();}
  });
  await test('a worker deposits at a connected extractor and reroutes a full-buffer delivery without losing cargo',async()=>{
    for(const full of [false,true]) {
      const {r,mine}=await setup();try {
        const w=state(r);resetWorkers(w);withdrawReserves(w,full?136:16);w.buildings[0].stock=full?88:0;
        if(full)Object.assign(w.rails[0],{cargo:32,progress:0});
        setWorker(w,0,{x:12,y:20,job:2,target:mine.id,cargo:16});await restoreColony(r,w);await step(r);const next=state(r);
        if(full){assert.equal(next.bots[0].cargo,16);assert.equal(next.bots[0].target,0);assert.equal(next.buildings[0].stock,88);}
        else {assert.equal(next.bots[0].cargo,0);assert.equal(next.buildings[0].stock,16);}
      }finally{await r.close();}
    }
  });
  await test('a paid local kit and outbound freight jointly reserve refund room in the extractor buffer',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);withdrawReserves(w,120);w.buildings[0].stock=88;Object.assign(w.rails[0],{cargo:32,progress:16});
      w.spent+=w.ore;w.ore=0;for(let i=0;i<w.bots.length;i++)setWorker(w,i,{x:12,y:20});await restoreColony(r,w);
      await fixtureCall(r,'observe',[13,20]);const reserved=await check(r),project=reserved.buildings.at(-1);
      assert.equal(project.source,mine.id);assert.equal(project.stage,3);assert.equal(reserved.buildings[0].stock,63);
      assert.equal(reserved.localSpent,25);assert.equal(reserved.rails[0].cargo,32);
      const invalid=state(r);withdrawReserves(invalid,1);invalid.buildings[0].stock++;
      const before=r.snapshot(1);await assert.rejects(()=>restoreColony(r,invalid));assert.deepEqual(r.snapshot(1),before);
      await fixtureCall(r,'cancel-building',[13,20]);const refunded=await check(r);
      assert.equal(refunded.buildings[0].stock,88);assert.equal(refunded.rails[0].cargo,32);assert.equal(refunded.localSpent,0);assert.equal(refunded.spent,w.spent);
    }finally{await r.close();}
  });
  async function returningLocalKit() {
    const {r,mine}=await setup(),world=state(r);resetWorkers(world);world.bots.length=1;
    const point=pixelAt(world,13,20),project={id:world.nextId++,kind:2,...at(world,13,20),level:1,hp:100,
      stock:0,stage:1,cooldown:0,aimX:point.x,aimY:point.y,armed:0,source:mine.id,moveX:-1,moveY:-1};
    world.buildings.push(project);withdrawReserves(world,145);world.buildings[0].stock=95;
    world.localSpent=50;world.spent=75;setWorker(world,0,{x:12,y:20,job:5,target:project.id,cargo:25,source:mine.id});
    await restoreColony(r,world);return {r,mine,project,worker:world.bots[0].id};
  }
  await test('a returning local artillery kit waits for outbound freight to free source reservation room',async()=>{
    const {r,mine,project,worker}=await returningLocalKit();try {
      await step(r);const waiting=state(r),rail=waiting.rails.find(edge=>edge.source===mine.id);
      assert.equal(waiting.buildings[0].stock,63);assert.equal(rail.cargo,32);
      assert.equal(waiting.buildings.find(site=>site.id===project.id).stage,1);
      assert.equal(waiting.bots.find(bot=>bot.id===worker).cargo,25);assert.equal(waiting.localSpent,50);
      // Loading frees physical stock space but not refund capacity: the source
      // still owns those 32 units until its shuttle actually reaches the hub.
      await step(r);assert.equal(state(r).bots[0].cargo,25);assert.equal(state(r).delivered,0);
      for(let tick=0;tick<30&&state(r).bots[0].cargo===25;tick++)await step(r);
      const handed=state(r);assert.equal(handed.bots[0].cargo,0);
      assert.equal(handed.buildings.find(site=>site.id===project.id).stage,0);
      assert.equal(handed.buildings[0].stock,63);assert.equal(handed.rails[0].cargo,0);assert.equal(handed.delivered,32);
      assert.equal(handed.localSpent,50);assert.equal(handed.spent,75);assert.equal(handed.produced,145);assert.equal(handed.lostOre,0);
    }finally{await r.close();}
  });
  await test('cancelling a capacity-blocked local handback refunds the source kit then the carried kit exactly once',async()=>{
    const {r,project,worker}=await returningLocalKit();try {
      await step(r);assert.equal(state(r).bots[0].cargo,25);await fixtureCall(r,'cancel-building',[13,20]);
      const cancelled=await check(r);assert.equal(cancelled.buildings.some(site=>site.id===project.id),false);
      assert.equal(cancelled.buildings[0].stock,88);assert.equal(cancelled.rails[0].cargo,32);
      assert.equal(cancelled.spent,50);assert.equal(cancelled.localSpent,25);assert.equal(cancelled.ore,135);
      assert.equal(cancelled.bots[0].target,0);assert.equal(cancelled.bots[0].cargo,25);
      for(let tick=0;tick<40&&state(r).bots.find(bot=>bot.id===worker).cargo===25;tick++)await step(r);
      const refunded=state(r);assert.equal(refunded.bots.find(bot=>bot.id===worker).cargo,0);
      assert.equal(refunded.spent,25);assert.equal(refunded.localSpent,0);assert.ok(refunded.delivered>=25);
      assert.equal(refunded.produced,145);assert.equal(refunded.lostOre,0);
      await step(r);assert.equal(state(r).spent,25);assert.equal(state(r).localSpent,0);
    }finally{await r.close();}
  });
  await test('workers use extractor links in both directions without a duplicate tower beside the mine',async()=>{
    for(const outward of [true,false]) {
      const {r,mine}=await setup();try {
        const w=state(r);resetWorkers(w);w.bots.length=1;
        if(outward)setWorker(w,0,{job:9,target:mine.id,path:[12+20*48]});
        else {withdrawReserves(w,16);setWorker(w,0,{x:12,y:20,job:2,cargo:16,path:[8+22*48]});}
        await restoreColony(r,w);await step(r);const flight=state(r).bots[0].flight[0];assert.ok(flight);
        assert.deepEqual([flight.origin,flight.destination],outward?[routeCell(w,8,22),routeCell(w,12,20)]:[routeCell(w,12,20),routeCell(w,8,22)]);
        assert.equal(flight.speed,80);assert.equal(state(r).buildings.length,1);
      }finally{await r.close();}
    }
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkExtractorTransport(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} extractor transport groups passed`);
}
