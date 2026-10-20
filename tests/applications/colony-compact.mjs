// World14 boundaries execute the compiled reducer; fixtures only establish states.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {decodeObservation} from '../../apps/siegework/headless.mjs';
import {settleWorker} from './casualty.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,withdrawReserves,routeCell,MAP_WIDTH,MAP_HEIGHT} from './colony-state.mjs';

export async function checkCompact(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function check(r) {
    const w=state(r),balance=colonyBalance(w);assert.equal(w.ore,balance.bank);assert.equal(w.produced,balance.raw);
    assert.ok(w.localSpent>=0&&w.localSpent<=w.spent);const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);return w;
  }
  async function step(r,n=1){for(let i=0;i<n;i++){await fixtureCall(r,'advance');await check(r);}return state(r);}
  async function until(r,predicate){for(let i=0;i<200&&!predicate(state(r));i++)await step(r);assert.ok(predicate(state(r)));}
  await test('free first extractor starts the clock, reserves one empty worker and completes only on physical arrival',async()=>{
    const r=await fresh(),initial=state(r);initial.started=false;await restoreColony(r,initial);
    await fixtureCall(r,'observe',[12,22]);assert.equal(state(r).notice,38);assert.equal(state(r).ore,160);
    await fixtureCall(r,'extract',[12,20]);const ordered=await check(r),worker=ordered.bots.find(b=>b.job===3);
    assert.equal(ordered.started,true);assert.equal(ordered.spent,0);assert.equal(ordered.ore,160);assert.equal(ordered.localSpent,0);
    assert.ok(worker);assert.equal(worker.cargo,0);assert.equal(worker.source,0);assert.equal(ordered.buildings[0].stage,1);
    await fixtureCall(r,'extract',[12,20]);assert.equal(state(r).notice,3);assert.equal(state(r).buildings.length,1);
    await step(r,5);assert.notEqual(state(r).buildings[0].stage,2);assert.equal(state(r).spent,0);
    await until(r,w=>w.buildings[0].stage===2);assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);await r.close();
  });
  await test('free construction works with no bank balance and sends an unladen worker directly to its site',async()=>{
    const r=await fresh(),w=state(r);w.started=true;w.ore=0;w.spent=160;w.bots.length=1;setWorker(w,0,{x:12,y:21});await restoreColony(r,w);
    await fixtureCall(r,'extract',[12,20]);const ordered=await check(r);assert.equal(ordered.ore,0);assert.equal(ordered.spent,160);
    assert.equal(ordered.bots[0].job,3);assert.equal(ordered.bots[0].cargo,0);assert.deepEqual(ordered.bots[0].path,[routeCell(w,12,20)]);
    await step(r,5);assert.equal(state(r).buildings[0].stage,1);await step(r);assert.equal(state(r).buildings[0].stage,2);
    assert.equal(state(r).ore,0);assert.equal(state(r).spent,160);await r.close();
  });
  await test('a loaded worker delivers its single raw-ore cargo before taking the free construction task',async()=>{
    const r=await fresh(),w=state(r);w.started=true;w.bots.length=1;withdrawReserves(w,16);
    setWorker(w,0,{x:12,y:22,job:2,cargo:16,path:[11,10,9,8].map(x=>x+22*48)});await restoreColony(r,w);
    await fixtureCall(r,'extract',[12,20]);const ordered=await check(r);assert.equal(ordered.buildings[0].stage,3);
    assert.equal(ordered.bots[0].cargo,16);assert.equal(ordered.bots[0].job,2);assert.equal(ordered.bots[0].order,ordered.buildings[0].id);
    await until(r,w=>w.buildings[0].stage===2);assert.equal(state(r).delivered,16);assert.equal(state(r).spent,0);assert.equal(state(r).ore,176);await r.close();
  });
  await test('cancelling or losing a free builder creates no refund and zero cargo still proves unique ownership',async()=>{
    for(const casualty of [false,true]) {
      const r=await fresh();await fixtureCall(r,'extract',[12,20]);const ordered=state(r),builder=ordered.bots.find(b=>b.job===3);
      for(const edit of [w=>{w.bots[1]={...w.bots[1],...builder,id:w.bots[1].id};},w=>{w.bots.find(b=>b.id===builder.id).cargo=40;}]) {
        const malformed=structuredClone(ordered);edit(malformed);const before=r.snapshot(1);await assert.rejects(restoreColony(r,malformed));assert.deepEqual(r.snapshot(1),before);
      }
      if(casualty)await settleWorker(r,builder.id);else {await fixtureCall(r,'cancel-building',[12,20]);assert.equal(state(r).notice,47);}
      await check(r);assert.equal(state(r).buildings.length,0);assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);
      await step(r,10);assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);await r.close();
    }
  });
  await test('cancelling a free builder in flight retains its captured landing without creating a return kit',async()=>{
    const r=await fresh();await fixtureCall(r,'extract',[12,20]);const w=state(r),index=w.bots.findIndex(b=>b.job===3),id=w.buildings[0].id;
    setWorker(w,index,{x:16,y:22,job:3,target:id,flight:[{origin:routeCell(w,16,22),destination:routeCell(w,12,20),progress:80,speed:80}]});
    await restoreColony(r,w);await fixtureCall(r,'cancel-building',[12,20]);const cancelled=await check(r);
    assert.equal(cancelled.buildings.length,0);assert.equal(cancelled.bots[index].job,0);assert.equal(cancelled.bots[index].flight.length,1);
    assert.equal(cancelled.bots[index].cargo,0);await until(r,w=>w.bots[index].flight.length===0);
    assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);assert.deepEqual([state(r).bots[index].x,state(r).bots[index].y],Object.values(pixelAt(w,12,20)));await r.close();
  });
  await test('extractor demolition refunds only completed paid upgrades and preserves the finite deposit',async()=>{
    for(const level of [1,2,3]) {
      const r=await fresh(),w=state(r);w.started=true;withdrawReserves(w,240);w.delivered=240;w.ore=400;setWorker(w,0,{x:12,y:20});await restoreColony(r,w);
      await fixtureCall(r,'extract',[12,20]);await step(r);assert.equal(state(r).buildings[0].stage,2);
      for(let next=2;next<=level;next++)await fixtureCall(r,'upgrade',[12,20]);
      const before=state(r),investment=[0,0,40,200][level];assert.equal(before.spent,investment);assert.equal(before.ore,400-investment);
      await fixtureCall(r,'scavenge-building',[12,20]);await step(r);const working=state(r),bot=working.bots.find(b=>b.job===17);assert.ok(bot);bot.timer=1;
      await restoreColony(r,working);await step(r);const after=await check(r);assert.equal(after.buildings.length,0);assert.equal(after.ore,before.ore+investment/5);
      assert.equal(after.spent,investment*4/5);assert.deepEqual(after.deposits,before.deposits);await step(r,5);assert.equal(state(r).ore,after.ore);await r.close();
    }
  });
  await test('resignation freezes an intact in-flight construction claim, reveals 4096 cells and restarts cleanly',async()=>{
    const r=await fresh();await fixtureCall(r,'extract',[12,20]);const w=state(r),index=w.bots.findIndex(b=>b.job===3),id=w.buildings[0].id;
    setWorker(w,index,{x:16,y:22,job:3,target:id,cargo:0,flight:[{origin:routeCell(w,16,22),destination:routeCell(w,12,20),progress:80,speed:80}]});
    w.surveys.push({...at(w,16,22),radius:7});w.paused=1;await restoreColony(r,w);const before=state(r);
    await fixtureCall(r,'resign');assert.deepEqual(state(r),{...before,outcome:4});await check(r);
    const frozen=r.snapshot(1);for(const [name,args]of [['advance',[]],['pause-colony',[0]],['pause-colony',[1]],['resign',[]]])await fixtureCall(r,name,args);
    assert.deepEqual(r.snapshot(1),frozen);const observed=decodeObservation(r.observe());assert.equal(observed.outcome,4);assert.equal(observed.hull,300);
    assert.equal(observed.tiles.length,MAP_WIDTH*MAP_HEIGHT);assert.equal(observed.nests.length,3);
    const old=frozen.slice();old[0]=12;await assert.rejects(r.restore(1,old));assert.deepEqual(r.snapshot(1),frozen);
    await fixtureCall(r,'new-run');const restarted=await check(r);assert.equal(restarted.outcome,0);assert.equal(restarted.hull,300);assert.equal(restarted.started,false);
    assert.equal(restarted.ore,160);assert.equal(restarted.spent,0);assert.equal(restarted.buildings.length,0);assert.equal(restarted.payloadVersion,1);assert.equal(r.snapshot(1)[0],14);await r.close();
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkCompact(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} compact World14 groups passed`);
}
