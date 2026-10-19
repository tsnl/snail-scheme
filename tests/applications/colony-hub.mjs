// Hub orders and paid repairs use the compiled reducer and its real decoder.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {readRecord,saveContract} from '../../src/application/indexeddb.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,at,setWorker,addEnemy, withdrawReserves} from './colony-state.mjs';

const state=r=>colony(r.snapshot(1)),call=fixtureCall;
async function advance(r,count=1) {
  for(let i=0;i<count;i++) {
    await call(r,'advance'); const world=state(r),balance=colonyBalance(world);
    assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
  }
}
async function until(r,predicate) {
  for(let i=0;i<250&&!predicate(state(r));i++)await advance(r);
  assert.ok(predicate(state(r)),'the bounded hub work completed');
}
async function roundTrip(r) {
  const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved);
}
async function damaged(r,hull=180) {
  const world=state(r); world.hull=hull; await restoreColony(r,world);
}
async function loaded(r) {
  const world=state(r); world.hull=180; withdrawReserves(world, (16) - world.produced); world.bots.length=1;
  setWorker(world,0,{x:12,y:20,job:2,cargo:16,path:[971,970,969,968,1016,1064]});
  await restoreColony(r,world);
}

export async function checkHub(test,fresh,bytes) {
  await test('World12 hub capacity rejects old geography and uses a distinct storage identity',async()=>{
    const r=await fresh(),fixture=JSON.parse(readFileSync(new URL('./siegework-world10.json',import.meta.url)));
    const saved=r.snapshot(1),record={format:1,application:fixture.application,contract:fixture.contract,snapshot:{revision:17,state:fixture.world}};
    assert.equal(r.manifest.settings.id,'siegework-colony-v12');assert.equal(saved[0],12);
    assert.throws(()=>readRecord(record,r.manifest.settings.id,saveContract(r.manifest)),/incompatible/);
    await assert.rejects(()=>r.restore(1,fixture.world),/invalid snapshot schema/);
    assert.deepEqual(r.snapshot(1),saved);assert.equal(record.snapshot.state[0],10);
    await roundTrip(r);await r.close();
  });
  await test('stored contracts allow added Match commands but retain every old endpoint and state/reset identity',async()=>{
    const r=await fresh(),contract=saveContract(r.manifest);
    const record={format:1,application:r.manifest.settings.id,contract,snapshot:{revision:17,state:r.snapshot(1)}};
    const match=manifest=>manifest.applications.find(app=>app.owner==='match'),extended=structuredClone(r.manifest);
    match(extended).handlers.push({id:'future-build-cell',payload:['I32','I32'],result:match(extended).handlers[0].result});
    assert.equal(readRecord(record,record.application,saveContract(extended)),record.snapshot);
    const edits=[manifest=>match(manifest).schema++,manifest=>match(manifest).state='DifferentWorld',
      manifest=>manifest.settings.runMarker++,manifest=>manifest.settings.reset='pause-colony',manifest=>manifest.effects='different-effects',
      manifest=>match(manifest).handlers.shift(),manifest=>match(manifest).handlers[0].id='different-id',
      manifest=>match(manifest).handlers[0].payload=['I32'],manifest=>match(manifest).handlers[0].result='DifferentResult'];
    for(const edit of edits) {
      const incompatible=structuredClone(r.manifest);edit(incompatible);
      assert.throws(()=>readRecord(record,record.application,saveContract(incompatible)),/incompatible/);
    }
    assert.throws(()=>readRecord({...record,contract:'not JSON'},record.application,saveContract(r.manifest)),/incompatible/);
    assert.throws(()=>readRecord({...record,contract:saveContract(extended)},record.application,contract),/incompatible/);
    const live=structuredClone(r.manifest);match(live).handlers.pop();
    assert.throws(()=>r.prepare(bytes,live),/endpoint contract/);await r.close();
  });
  await test('all nine hub tiles reject new buildings and relocation without spending',async()=>{
    const r=await fresh();
    for(let y=21;y<=23;y++)for(let x=7;x<=9;x++)for(const name of ['extract','observe','fortify']) {
      const before=state(r); await call(r,name,[x,y]); assert.deepEqual(state(r),{...before,notice:3});
    }
    await call(r,'observe',[10,23]); await until(r,world=>world.buildings[0]?.stage===2);
    const before=state(r); await call(r,'relocate-building',[10+23*48,9+23*48]);
    assert.deepEqual(state(r),{...before,notice:3}); await roundTrip(r); await r.close();
  });
  await test('old neighboring structures decode and old moves into the expanded hub refund once',async()=>{
    const r=await fresh(); await call(r,'observe',[10,23]); await until(r,world=>world.buildings[0]?.stage===2);
    const pending=state(r),point=at(pending,9,23); pending.buildings[0].moveX=point.x; pending.buildings[0].moveY=point.y;
    pending.ore-=5; pending.spent+=5; await restoreColony(r,pending); await roundTrip(r); await advance(r);
    assert.equal(state(r).ore,pending.ore+5); assert.equal(state(r).buildings[0].moveX,-1);
    const bank=state(r).ore; await advance(r,3); assert.equal(state(r).ore,bank); await r.close();
    const legacy=await fresh(); await call(legacy,'fortify',[10,23]); await until(legacy,world=>world.buildings[0]?.stage===2);
    const world=state(legacy); Object.assign(world.buildings[0],at(world,9,23));world.surveys.push({...at(world,9,23),radius:4});
    await restoreColony(legacy,world); await roundTrip(legacy); await advance(legacy);
    assert.deepEqual([state(legacy).buildings[0].x,state(legacy).buildings[0].y],Object.values(at(world,9,23)));
    await legacy.close();
  });
  await test('manual repair pays only for missing health and completes after thirty unpaused work ticks',async()=>{
    const r=await fresh(); await damaged(r); await advance(r,100); assert.equal(state(r).hull,180);
    await call(r,'repair-hub'); const ordered=state(r),worker=ordered.bots.find(bot=>bot.job===13);
    assert.equal(ordered.ore,100); assert.equal(ordered.spent,60); assert.equal(worker.timer,30); assert.equal(worker.target,60);
    assert.equal(ordered.started,true); assert.equal(ordered.bots.length,3);
    await call(r,'repair-hub'); assert.deepEqual(state(r),{...ordered,notice:30});
    await call(r,'pause-colony',[1]); const paused=r.snapshot(1); await roundTrip(r); await advance(r,50);
    assert.deepEqual(r.snapshot(1),paused); await call(r,'pause-colony',[0]); await advance(r,29);
    assert.equal(state(r).hull,180); assert.equal(state(r).bots.find(bot=>bot.job===13).timer,1);
    await advance(r); assert.equal(state(r).hull,300); assert.ok(state(r).bots.every(bot=>bot.job!==13));
    await damaged(r,240); await advance(r,40); assert.equal(state(r).hull,240); assert.equal(state(r).spent,60);
    await call(r,'repair-hub'); await advance(r,30); assert.equal(state(r).hull,300); assert.equal(state(r).spent,90);
    const full=state(r); await call(r,'repair-hub'); assert.deepEqual(state(r),{...full,notice:29}); await r.close();
  });
  await test('a repair worker delivers its existing ore before thirty ticks of paid work',async()=>{
    const r=await fresh(); await loaded(r); await call(r,'repair-hub'); const ordered=state(r);
    assert.equal(ordered.bots[0].job,12); assert.equal(ordered.bots[0].cargo,16);
    assert.equal(ordered.ore,100); assert.equal(ordered.delivered,0); await roundTrip(r);
    await until(r,world=>world.bots[0].job===13); assert.equal(state(r).delivered,16);
    assert.equal(state(r).ore,116); assert.equal(state(r).bots[0].cargo,0); assert.equal(state(r).bots[0].timer,30);
    await roundTrip(r); await advance(r,29); assert.equal(state(r).hull,180);
    await advance(r); assert.equal(state(r).hull,300); assert.equal(state(r).spent,60); await r.close();
  });
  await test('code replacement retains the exact paid repair amount in travel and work phases',async()=>{
    const r=await fresh(); await loaded(r); await call(r,'repair-hub');
    for(const job of [12,13]) {
      await until(r,world=>world.bots[0].job===job); const world=r.snapshot(1),local=r.snapshot(2),old=r.instance;
      await r.replace(r.prepare(bytes,r.manifest)); await r.initialize(1); await r.initialize(2);
      assert.notEqual(r.instance,old); assert.deepEqual(r.snapshot(1),world); assert.deepEqual(r.snapshot(2),local);
      assert.equal(state(r).bots[0].target,60);
    }
    await advance(r,30); assert.equal(state(r).hull,300); assert.equal(state(r).spent,60); await r.close();
  });
  await test('a killed repair worker refunds unused hub materials once and loses only carried ore',async()=>{
    const r=await fresh(); await loaded(r); await call(r,'repair-hub');
    const world=state(r); world.tick=9; world.bots[0].hp=7; await restoreColony(r,world);
    await addEnemy(r,{x:12,y:20}); await advance(r);
    assert.equal(state(r).ore,160); assert.equal(state(r).spent,0); assert.equal(state(r).lostOre,16);
    assert.equal(state(r).casualties,1); assert.equal(state(r).hull,180);
    assert.ok(state(r).bots.every(bot=>![12,13].includes(bot.job)));
    await advance(r,20); assert.equal(state(r).ore,160); assert.equal(state(r).spent,0); await r.close();
  });
  await test('a surviving repair worker retains its payment through retreat, reload and return',async()=>{
    const r=await fresh();await loaded(r);await call(r,'repair-hub');await addEnemy(r,{x:12,y:20});await advance(r);
    const fleeing=state(r).bots[0];assert.equal(fleeing.job,7);assert.equal(fleeing.timer,12);
    assert.equal(fleeing.target,60);assert.equal(fleeing.cargo,16);await roundTrip(r);
    const saved=r.snapshot(1);await r.replace(r.prepare(bytes,r.manifest));await r.initialize(1);
    assert.deepEqual(r.snapshot(1),saved);
    const quiet=state(r);quiet.enemies=[];await restoreColony(r,quiet);
    await until(r,world=>world.bots[0].job===13);assert.equal(state(r).bots[0].timer,30);
    assert.equal(state(r).delivered,16);assert.equal(state(r).ore,116);assert.equal(state(r).spent,60);
    await advance(r,29);assert.equal(state(r).hull,180);await advance(r);
    assert.equal(state(r).hull,300);assert.equal(state(r).spent,60);assert.equal(state(r).lostOre,0);await r.close();
  });
  await test('partial repair spends available ore and refuses unavailable workers, zero funds and destroyed hubs',async()=>{
    const r=await fresh(); await damaged(r);
    for(let i=0;i<3;i++)await call(r,'fabricate-worker');
    const busy=state(r); await call(r,'repair-hub'); assert.deepEqual(state(r),{...busy,notice:27}); await r.close();
    const poor=await fresh(); const world=state(poor); Object.assign(world,{hull:180,ore:24,spent:136,started:true});
    await restoreColony(poor,world); await call(poor,'repair-hub'); assert.equal(state(poor).ore,0);
    assert.equal(state(poor).bots.find(bot=>bot.job===13).target,24); await advance(poor,30);
    assert.equal(state(poor).hull,228); const empty=state(poor); await call(poor,'repair-hub');
    assert.deepEqual(state(poor),{...empty,notice:7}); await poor.close();
    const dead=await fresh(); await damaged(dead,7); await call(dead,'repair-hub');
    const attacked=state(dead); attacked.tick=9; await restoreColony(dead,attacked); await addEnemy(dead,{x:8,y:22});
    await advance(dead); assert.equal(state(dead).outcome,1); const lost=state(dead);
    await advance(dead,50); assert.deepEqual(state(dead),lost); await call(dead,'repair-hub');
    assert.deepEqual(state(dead),{...lost,notice:9}); await roundTrip(dead); await dead.close();
  });
  await test('damage during repair reduces the quoted outcome without increasing its reserved payment',async()=>{
    const r=await fresh(); await damaged(r); await call(r,'repair-hub');
    const world=state(r); world.tick=9; await restoreColony(r,world); await addEnemy(r,{x:8,y:22}); await advance(r);
    const hit=state(r); assert.equal(hit.hull,173); assert.equal(hit.spent,60); hit.enemies=[]; await restoreColony(r,hit);
    await advance(r,29); assert.equal(state(r).hull,293); assert.equal(state(r).spent,60); assert.equal(state(r).ore,100);
    await call(r,'repair-hub'); assert.equal(state(r).bots.find(bot=>bot.job===13).target,4);
    await advance(r,30); assert.equal(state(r).hull,300); assert.equal(state(r).spent,64); await r.close();
  });
  await test('repair snapshots reject duplicate workers, unfunded jobs and malformed work phases',async()=>{
    const r=await fresh(); await damaged(r); await call(r,'repair-hub'); const saved=r.snapshot(1);
    for(const edit of [world=>{world.ore+=60;world.spent-=60;},
      world=>{world.bots[1]={...world.bots[0],id:world.bots[1].id};world.ore-=60;world.spent+=60;},
      world=>world.bots[0].timer=31,world=>world.bots[0].timer=0,
      world=>world.bots[0].x+=40,world=>world.bots[0].target=0,world=>world.bots[0].target=151]) {
      const invalid=colony(saved); edit(invalid); await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0; await checkHub(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh,bytes);
  console.log(`${count} hub and repair checks passed`);
}
