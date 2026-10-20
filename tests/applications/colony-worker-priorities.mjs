// Explicit work keeps one economy worker; idle labor has no hidden builder quota.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,withdrawReserves} from './colony-state.mjs';

export async function checkWorkerPriorities(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function setup(level=1) {
    const r=await fresh(),world=state(r),point=pixelAt(world,12,20),cost=[0,25,65,225][level];
    withdrawReserves(world,500);world.delivered=500;world.ore+=500;world.started=true;world.spent=cost;world.ore-=cost;
    const mine={id:world.nextId++,kind:1,...at(world,12,20),level,hp:140,stock:0,stage:2,cooldown:0,
      aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
    world.buildings=[mine];world.surveys.push({...at(world,12,20),radius:level===1?7:10});
    await restoreColony(r,world);return {r,mine};
  }
  async function check(r){const world=state(r),sums=colonyBalance(world);assert.equal(world.ore,sums.bank);assert.equal(world.produced,sums.raw);await r.restore(1,r.snapshot(1));return world;}
  async function order(r,x,y){await fixtureCall(r,'observe',[x,y]);assert.equal(state(r).notice,10);await check(r);}
  async function step(r){await fixtureCall(r,'advance');return check(r);}
  const claims=world=>world.bots.filter(bot=>bot.order>0||bot.job===3);
  await test('two idle workers accept explicit construction while the only miner keeps its assignment',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);setWorker(w,0,{x:12,y:20,job:8,target:mine.id});await restoreColony(r,w);
      await order(r,12,22);await order(r,10,22);assert.equal(claims(state(r)).length,2);assert.equal(state(r).bots[0].job,8);
      await order(r,8,25);assert.equal(state(r).buildings.at(-1).stage,0);assert.equal(state(r).bots[0].job,8);
    }finally{await r.close();}
  });
  await test('a nearby local kit cannot preempt the last active miner in favor of an idle future replacement',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);withdrawReserves(w,25);w.buildings[0].stock=25;
      setWorker(w,0,{x:12,y:20,job:8,target:mine.id});await restoreColony(r,w);
      await order(r,13,20);const ordered=state(r);
      assert.equal(ordered.bots[0].job,8);assert.equal(ordered.bots[0].target,mine.id);assert.equal(ordered.bots[0].order,0);
      assert.ok(ordered.bots.slice(1).some(bot=>bot.order===ordered.buildings.at(-1).id));
    }finally{await r.close();}
  });
  await test('queued orders leave a worker to start mining even before any economy assignment exists',async()=>{
    const {r,mine}=await setup();try {
      await order(r,12,22);await order(r,10,22);await order(r,8,25);assert.equal(claims(state(r)).length,2);
      await step(r);assert.ok(state(r).bots.some(bot=>[8,9].includes(bot.job)&&bot.target===mine.id));
      assert.equal(state(r).buildings.at(-1).stage,0);
    }finally{await r.close();}
  });
  await test('the last economy worker retains carried ore and its return job while other workers construct',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);withdrawReserves(w,16);setWorker(w,0,{x:12,y:20,job:2,cargo:16,path:[12+21*48,12+22*48,11+22*48,10+22*48,9+22*48,8+22*48]});
      await restoreColony(r,w);await order(r,12,22);await order(r,10,22);await order(r,8,25);
      assert.equal(claims(state(r)).length,2);assert.equal(state(r).bots[0].job,2);assert.equal(state(r).bots[0].cargo,16);
      assert.equal(state(r).bots[0].order,0);assert.equal(state(r).buildings.at(-1).stage,0);
      await step(r);assert.equal(state(r).bots[0].cargo,16);
    }finally{await r.close();}
  });
  await test('connected extractors staff every available mining slot without keeping an idle manual hauler',async()=>{
    const {r,mine}=await setup(3);try {
      await step(r);const w=state(r);assert.equal(w.bots.filter(bot=>[8,9].includes(bot.job)&&bot.target===mine.id).length,3);
      assert.equal(w.rails.length,1);assert.equal(claims(w).length,0);
    }finally{await r.close();}
  });
  await test('a sole miner can complete paid construction sequentially and resume mining',async()=>{
    const {r,mine}=await setup();try {
      const w=state(r);w.bots.length=1;setWorker(w,0,{x:12,y:20,job:8,target:mine.id});await restoreColony(r,w);
      await order(r,12,22);assert.equal(claims(state(r)).length,1);
      for(let i=0;i<180&&state(r).buildings.at(-1).stage!==2;i++)await step(r);
      assert.equal(state(r).buildings.at(-1).stage,2);assert.ok([8,9].includes(state(r).bots[0].job));assert.equal(state(r).bots[0].target,mine.id);
    }finally{await r.close();}
  });
  await test('ordinary mine stock ships immediately instead of retaining an invisible construction cache',async()=>{
    const {r}=await setup();try {
      const w=state(r);withdrawReserves(w,20);w.buildings[0].stock=20;await restoreColony(r,w);await step(r);
      assert.equal(state(r).buildings[0].stock,0);assert.equal(state(r).rails[0].cargo,20);
      assert.equal(state(r).produced,w.produced);
    }finally{await r.close();}
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkWorkerPriorities(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} worker priority groups passed`);
}
