// World15 boundaries execute the compiled reducer; fixtures only establish states.
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
  async function until(r,predicate){for(let i=0;i<300&&!predicate(state(r));i++)await step(r);assert.ok(predicate(state(r)));}
  async function mine(r){await fixtureCall(r,'extract',[12,20]);await until(r,w=>w.buildings[0]?.stage===2);return state(r).buildings[0];}
  await test('the first extractor pays one 25-ore kit and completes only after pickup and physical arrival',async()=>{
    const r=await fresh();await fixtureCall(r,'observe',[12,22]);assert.equal(state(r).notice,38);
    await fixtureCall(r,'extract',[12,20]);const ordered=await check(r),worker=ordered.bots.find(b=>b.job===11);
    assert.equal(ordered.started,true);assert.equal(ordered.spent,25);assert.equal(ordered.ore,135);assert.equal(ordered.localSpent,0);
    assert.ok(worker);assert.equal(worker.cargo,0);assert.equal(worker.order,ordered.buildings[0].id);assert.equal(ordered.buildings[0].stage,3);
    await fixtureCall(r,'extract',[12,20]);assert.equal(state(r).notice,3);assert.equal(state(r).buildings.length,1);
    await step(r);const carrier=state(r).bots.find(b=>b.job===3);assert.equal(carrier.cargo,25);assert.equal(carrier.source,0);
    await step(r,5);assert.notEqual(state(r).buildings[0].stage,2);
    await until(r,w=>w.buildings[0].stage===2);assert.equal(state(r).ore,135);assert.equal(state(r).spent,25);await r.close();
  });
  await test('an extractor cannot reserve a worker or start a colony without its full material cost',async()=>{
    const r=await fresh(),w=state(r);w.started=true;w.ore=24;w.spent=136;await restoreColony(r,w);
    await fixtureCall(r,'extract',[12,20]);assert.equal(state(r).notice,7);assert.equal(state(r).buildings.length,0);
    assert.equal(state(r).ore,24);assert.equal(state(r).spent,136);assert.deepEqual(state(r).bots,w.bots);await check(r);await r.close();
  });
  await test('a loaded builder delivers its raw ore before picking up the separately paid extractor kit',async()=>{
    const r=await fresh(),w=state(r);w.started=true;w.bots.length=1;withdrawReserves(w,16);
    setWorker(w,0,{x:12,y:22,job:2,cargo:16,path:[11,10,9,8].map(x=>x+22*48)});await restoreColony(r,w);
    await fixtureCall(r,'extract',[12,20]);const ordered=await check(r);assert.equal(ordered.buildings[0].stage,3);
    assert.equal(ordered.bots[0].cargo,16);assert.equal(ordered.bots[0].job,2);assert.equal(ordered.bots[0].order,ordered.buildings[0].id);
    await until(r,w=>w.buildings[0].stage===2);assert.equal(state(r).delivered,16);assert.equal(state(r).spent,25);assert.equal(state(r).ore,151);await r.close();
  });
  await test('extractor cancellation refunds uncollected supplies immediately and a carried kit only on return',async()=>{
    for(const carried of [false,true]) {
      const r=await fresh();await fixtureCall(r,'extract',[12,20]);if(carried)await step(r,8);
      const ordered=state(r),builder=ordered.bots.find(b=>b.order||b.job===3);
      for(const edit of [w=>{w.bots[1]={...builder,id:w.bots[1].id};},w=>{w.bots.find(b=>b.id===builder.id).cargo=40;}]) {
        const malformed=structuredClone(ordered);edit(malformed);const before=r.snapshot(1);await assert.rejects(restoreColony(r,malformed));assert.deepEqual(r.snapshot(1),before);
      }
      await fixtureCall(r,'cancel-building',[12,20]);await check(r);assert.equal(state(r).buildings.length,0);
      assert.equal(state(r).notice,carried?18:17);assert.equal(state(r).ore,carried?135:160);
      await until(r,w=>w.bots.every(b=>b.job!==5));assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);
      await step(r,5);assert.equal(state(r).ore,160);await r.close();
    }
  });
  await test('worker death releases a reserved extractor but loses its physically carried kit without a refund',async()=>{
    for(const carried of [false,true]) {
      const r=await fresh();await fixtureCall(r,'extract',[12,20]);if(carried)await step(r);
      const builder=state(r).bots.find(b=>b.order||b.job===3);await settleWorker(r,builder.id);await check(r);
      assert.equal(state(r).ore,135);assert.equal(state(r).spent,25);assert.equal(state(r).buildings.length,carried?0:1);
      if(!carried){assert.equal(state(r).buildings[0].stage,0);await until(r,w=>w.buildings[0].stage===2);}
      await r.close();
    }
  });
  await test('cancelling an extractor kit in flight keeps the committed landing and refunds once at the hub',async()=>{
    const r=await fresh();await fixtureCall(r,'extract',[12,20]);await step(r);const w=state(r),index=w.bots.findIndex(b=>b.job===3),id=w.buildings[0].id;
    setWorker(w,index,{x:16,y:22,job:3,target:id,cargo:25,flight:[{origin:routeCell(w,16,22),destination:routeCell(w,12,20),progress:80,speed:80}]});
    w.surveys.push({...at(w,16,22),radius:7});await restoreColony(r,w);await fixtureCall(r,'cancel-building',[12,20]);const cancelled=await check(r);
    assert.equal(cancelled.buildings.length,0);assert.equal(cancelled.bots[index].job,5);assert.equal(cancelled.bots[index].flight.length,1);
    assert.equal(cancelled.bots[index].cargo,25);assert.equal(cancelled.ore,135);await until(r,w=>w.bots[index].flight.length===0);
    assert.deepEqual([state(r).bots[index].x,state(r).bots[index].y],Object.values(pixelAt(w,12,20)));
    await until(r,w=>w.bots[index].job!==5);assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);await r.close();
  });
  await test('extractor demolition includes its base kit and unchanged mining upgrades exactly once',async()=>{
    for(const level of [1,2,3]) {
      const r=await fresh(),w=state(r);withdrawReserves(w,240);w.delivered=240;w.ore=400;await restoreColony(r,w);await mine(r);
      for(let next=2;next<=level;next++)await fixtureCall(r,'upgrade',[12,20]);
      const before=state(r),investment=[0,25,65,225][level];assert.equal(before.spent,investment);
      const reserve=before.deposits.find(d=>d.cell===routeCell(before,12,20)).remaining;
      await fixtureCall(r,'scavenge-building',[12,20]);await until(r,w=>w.bots.some(b=>b.job===17));const working=state(r),bot=working.bots.find(b=>b.job===17);bot.timer=1;
      await restoreColony(r,working);await step(r);const after=await check(r);assert.equal(after.buildings.length,0);assert.equal(after.spent,investment*4/5);
      assert.equal(after.deposits.find(d=>d.cell===routeCell(after,12,20)).remaining,reserve);await step(r,5);assert.equal(state(r).spent,after.spent);await r.close();
    }
  });
  await test('a completed extractor supplies its own depot, bidirectional worker flights and ordinary upgraded freight speed',async()=>{
    for(const level of [1,2,3]) {
      const r=await fresh(),base=state(r);withdrawReserves(base,400);base.delivered=400;base.ore=560;await restoreColony(r,base);await mine(r);
      for(let next=2;next<=level;next++)await fixtureCall(r,'upgrade',[12,20]);
      await step(r,2);const w=state(r),site=w.buildings[0];assert.equal(site.level,level);assert.equal(w.rails.length,1);assert.equal(w.rails[0].source,site.id);
      assert.ok(w.surveys.some(s=>s.x===site.x&&s.y===site.y&&s.radius===(level===1?7:10)));
      // Hold mining fixed to isolate the source-owned 32-ore shuttle.
      for(let i=0;i<w.bots.length;i++)setWorker(w,i);withdrawReserves(w,82);site.stock+=82;await restoreColony(r,w);
      await step(r);let next=state(r);assert.equal(next.rails[0].cargo,32);assert.equal(next.rails[0].progress,0);
      await step(r);assert.equal(state(r).rails[0].progress,32*2**(level-1));await check(r);await r.close();
    }
  });
  await test('local extractor construction reserves source capacity and cancellation restores its paid ore',async()=>{
    const r=await fresh();await mine(r);await fixtureCall(r,'upgrade',[12,20]);const w=state(r),source=w.buildings[0];
    withdrawReserves(w,100);source.stock+=100;w.spent+=w.ore;w.ore=0;
    w.surveys.push({...at(w,9,13),radius:7});for(let i=0;i<w.bots.length;i++)setWorker(w,i,{x:12,y:20});await restoreColony(r,w);
    await fixtureCall(r,'extract',[9,13]);const ordered=await check(r),project=ordered.buildings.at(-1);
    assert.equal(project.source,source.id);assert.equal(ordered.localSpent,w.localSpent+25);assert.equal(ordered.buildings[0].stock,w.buildings[0].stock-25);
    await fixtureCall(r,'cancel-building',[9,13]);const refunded=await check(r);assert.equal(refunded.localSpent,w.localSpent);
    assert.equal(refunded.buildings[0].stock,w.buildings[0].stock);assert.equal(refunded.spent,w.spent);await r.close();
  });
  await test('resignation freezes a paid in-flight claim, reveals the map and rejects World14 before restarting cleanly',async()=>{
    const r=await fresh();await fixtureCall(r,'extract',[12,20]);await step(r);const w=state(r),index=w.bots.findIndex(b=>b.job===3),id=w.buildings[0].id;
    setWorker(w,index,{x:16,y:22,job:3,target:id,cargo:25,flight:[{origin:routeCell(w,16,22),destination:routeCell(w,12,20),progress:80,speed:80}]});
    w.surveys.push({...at(w,16,22),radius:7});w.paused=1;await restoreColony(r,w);const before=state(r);
    await fixtureCall(r,'resign');assert.deepEqual(state(r),{...before,outcome:4});await check(r);
    const frozen=r.snapshot(1);for(const [name,args]of [['advance',[]],['pause-colony',[0]],['pause-colony',[1]],['resign',[]]])await fixtureCall(r,name,args);
    assert.deepEqual(r.snapshot(1),frozen);const observed=decodeObservation(r.observe());assert.equal(observed.outcome,4);assert.equal(observed.hull,300);
    assert.equal(observed.tiles.length,MAP_WIDTH*MAP_HEIGHT);assert.equal(observed.nests.length,3);
    const old=frozen.slice();old[0]=14;await assert.rejects(r.restore(1,old));assert.deepEqual(r.snapshot(1),frozen);
    await fixtureCall(r,'new-run');const restarted=await check(r);assert.equal(restarted.outcome,0);assert.equal(restarted.hull,300);assert.equal(restarted.started,false);
    assert.equal(restarted.ore,160);assert.equal(restarted.spent,0);assert.equal(restarted.buildings.length,0);assert.equal(restarted.payloadVersion,1);assert.equal(r.snapshot(1)[0],15);await r.close();
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkCompact(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} paid extractor World15 groups passed`);
}
