// Upgrade healing and refunds execute the compiled reducer; snapshots only establish scenarios.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {settleWorker} from './casualty.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,addEnemy,withdrawReserves} from './colony-state.mjs';

export async function checkUpgradeHealing(test,fresh) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  async function step(r,count=1) {
    for(let i=0;i<count;i++) {
      await call(r,'advance');const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);assert.ok(world.localSpent<=world.spent);
      const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    }
  }
  async function until(r,predicate) {
    for(let tick=0;tick<300&&!predicate(state(r));tick++)await step(r);
    assert.ok(predicate(state(r)),'worker completed the bounded upgrade transition');
  }
  function building(world,{kind=3,level=1,x=12,y=22,hp=50,local=0}={}) {
    const cost=kind===1?[0,40,200][level-1]:(kind===2?50:25)+25*(level-1),point=pixelAt(world,x,y),cell=at(world,x,y);
    const b={id:world.nextId++,kind,...cell,level,hp,stock:0,stage:2,cooldown:0,aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
    world.started=true;world.buildings.push(b);world.spent+=cost;world.ore-=cost;world.surveys.push({...cell,radius:level===1?7:10});
    if(local){withdrawReserves(world,local);world.localSpent+=local;world.ore+=local;}return b;
  }
  await test('completed upgrades heal towers, artillery, extractors and hub capacity without another charge',async()=>{
    for(const kind of [1,2,3]) {
      const r=await fresh(),world=state(r),y=kind===1?20:22;building(world,{kind,y,hp:40});
      await restoreColony(r,world);await call(r,'upgrade',[12,y]);
      if(kind!==1)assert.equal(state(r).buildings[0].hp,40);
      await until(r,w=>w.buildings[0].level===2);assert.equal(state(r).buildings[0].hp,kind===1?140:kind===2?100:90);
      assert.equal(state(r).ore,world.ore-(kind===1?40:25));await r.close();
    }
    const r=await fresh(),world=state(r);world.hull=200;world.started=true;await restoreColony(r,world);
    await call(r,'upgrade',[8,22]);assert.equal(state(r).hull,200);assert.equal(state(r).ore,60);
    await step(r,29);assert.equal(state(r).hull,200);
    await step(r);assert.equal(state(r).hull,300);assert.equal(state(r).hubCapacityLevel,1);assert.equal(state(r).ore,60);await r.close();
  });
  await test('maximum-level towers and artillery remain damaged and cannot buy another upgrade',async()=>{
    for(const kind of [2,3]) {
      const r=await fresh(),world=state(r);building(world,{kind,level:3,hp:40});await restoreColony(r,world);
      await call(r,'upgrade',[12,22]);assert.equal(state(r).notice,11);assert.equal(state(r).ore,world.ore);
      await step(r,40);assert.equal(state(r).buildings[0].hp,40);assert.equal(state(r).ore,world.ore);await r.close();
    }
  });
  await test('destroyed upgrade targets never revive when their worker or clock advances',async()=>{
    for(const hub of [false,true]) {
      const r=await fresh(),world=state(r);world.started=true;let site;
      if(hub)world.hull=7;else site=building(world,{hp:7});await restoreColony(r,world);
      await call(r,'upgrade',[hub?8:12,22]);const ordered=state(r);ordered.tick=9;ordered.lastRevealTick=-100;
      await restoreColony(r,ordered);await addEnemy(r,{x:hub?9:12,y:22,target:hub?0:site.id});await step(r);
      if(hub)assert.equal(state(r).hull,0);else assert.equal(state(r).buildings.length,0);
      await step(r,80);if(hub)assert.equal(state(r).hull,0);else assert.equal(state(r).buildings.length,0);await r.close();
    }
  });
  await test('Scavenge followed by bank-work refunds preserves still-refundable local kits and both ledgers',async()=>{
    for(const job of [4,12,14,0,3]) {
      const r=await fresh(),world=state(r),site=building(world,{level:3,hp:90,local:75});
      building(world,{level:3,x:16,hp:40,local:75});setWorker(world,0,{x:12,y:22});
      withdrawReserves(world,25);world.localSpent+=25;world.spent+=25;
      setWorker(world,2,{x:19,y:22,job:5,cargo:25,source:site.id,path:Array.from({length:11},(_,i)=>18-i+22*48)});
      const price=job===14?100:25;world.spent+=price;world.ore-=price;world.hull=250;
      let project;
      if(job===0||job===3){
        world.spent-=25;world.ore+=25;project=building(world,{x:20,hp:90});project.stage=job===3?1:0;
        if(job===3)setWorker(world,1,{x:18,y:22,job:3,target:project.id,cargo:25,path:[19,20].map(x=>x+22*48)});
      }
      else setWorker(world,1,{x:18,y:22,hp:7,job,target:job===4?world.nextId++:price,cargo:0,
        path:Array.from({length:10},(_,i)=>17-i+22*48)});
      await restoreColony(r,world);await call(r,'scavenge-building',[12,22]);await step(r);
      const working=state(r);working.bots[0].timer=1;await restoreColony(r,working);await step(r);
      if(job===0||job===3) {
        await call(r,'cancel-building',[20,22]);
        if(job===3)await until(r,w=>w.bots[1].cargo===0);
      } else {await settleWorker(r,world.bots[1].id);assert.equal(state(r).casualties,1);}
      const done=state(r);assert.equal(done.localSpent,160);assert.equal(done.delivered,15);assert.equal(done.ore,175);
      done.enemies=[];await restoreColony(r,done);await until(r,w=>w.bots.find(b=>b.id===world.bots[2].id)?.cargo===0);
      assert.equal(state(r).localSpent,135);assert.equal(state(r).delivered,40);assert.equal(state(r).ore,200);await r.close();
    }
  });
}
if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkUpgradeHealing(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} upgrade healing and refund groups passed`);
}
