// Actual compiled reducer transitions own demolition, ownership and refunds.
import {settleWorker} from './casualty.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,addEnemy,withdrawReserves} from './colony-state.mjs';

export async function checkScavenge(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function step(r,count=1) {
    for(let i=0;i<count;i++) {
      await fixtureCall(r,'advance');const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
      assert.ok(world.localSpent<=world.spent);await r.restore(1,r.snapshot(1));
    }
  }
  async function until(r,predicate) {
    for(let tick=0;tick<200&&!predicate(state(r));tick++)await step(r);
    assert.ok(predicate(state(r)),'worker transition completed');
  }
  const investment=(kind,level)=>(kind===1?0:kind===2?50:25)+(kind===1?[0,40,200][level-1]:25*(level-1));
  function building(world,kind=3,level=1,x=12,y=22,local=0) {
    const cost=investment(kind,level),point=pixelAt(world,x,y),cell=at(world,x,y);
    const value={id:world.nextId++,kind,...cell,level,hp:kind===1?140:kind===2?100:90,stock:0,stage:2,cooldown:0,
      aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
    world.started=true;world.buildings.push(value);world.spent+=cost;world.ore-=cost;
    if(local){withdrawReserves(world,local);world.localSpent+=local;world.ore+=local;}
    world.surveys.push({...cell,radius:kind===3?(level===1?7:10):4});return value;
  }
  await test('every completed building quotes and refunds one fifth of its construction and all upgrades after worker demolition',async()=>{
    for(const kind of [1,2,3])for(const level of [1,2,3]) {
      const r=await fresh(),world=state(r);world.bots.length=1;
      withdrawReserves(world,300);world.delivered+=300;world.ore+=300;
      const y=kind===1?20:22,site=building(world,kind,level,12,y),refund=Math.floor(investment(kind,level)/5);
      await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,y]);
      assert.equal(state(r).notice,44);assert.equal(state(r).ore,world.ore);assert.equal(state(r).buildings.length,1);
      assert.equal(state(r).bots[0].job,16);await until(r,w=>w.bots[0].job===17);
      const working=state(r);assert.equal(working.bots[0].timer,20);assert.equal(working.buildings[0].id,site.id);
      await step(r,19);assert.equal(state(r).buildings.length,1);assert.equal(state(r).ore,world.ore);
      await step(r);assert.equal(state(r).buildings.length,0);assert.equal(state(r).ore,world.ore+refund);
      assert.equal(state(r).spent,world.spent-refund);assert.deepEqual(state(r).deposits,world.deposits);
      const paid=state(r).ore;await step(r,30);assert.equal(state(r).ore,paid);await r.close();
    }
  });
  await test('local and mixed construction refunds preserve raw ore and cumulative spending bounds',async()=>{
    for(const local of [0,25,75]) {
      const r=await fresh(),world=state(r);world.bots.length=1;building(world,3,3,12,22,local);
      setWorker(world,0,{x:12,y:22});await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,22]);
      await until(r,w=>w.buildings.length===0);const done=state(r);
      assert.equal(done.ore,world.ore+15);assert.equal(done.spent,60);
      assert.equal(done.localSpent,Math.min(local,60));assert.equal(done.delivered,Math.max(0,local-60));
      assert.equal(done.produced,world.produced);await r.restore(1,r.snapshot(1));await r.close();
    }
  });
  await test('all-local demolition preserves a separately paid local kit until its later physical refund',async()=>{
    const r=await fresh(),world=state(r),site=building(world,3,3,12,22,75);
    world.bots.length=2;setWorker(world,0,{x:12,y:22});withdrawReserves(world,25);world.localSpent+=25;world.spent+=25;
    setWorker(world,1,{x:18,y:22,job:5,cargo:25,source:site.id,path:[17,16,15,14,13,12,11,10,9,8].map(x=>x+22*48)});
    await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,22]);await until(r,w=>w.buildings.length===0);
    const demolished=state(r);assert.equal(demolished.ore,175);assert.equal(demolished.localSpent,85);
    assert.equal(demolished.delivered,15);assert.equal(demolished.bots[1].cargo,25);
    await r.restore(1,r.snapshot(1));await until(r,w=>w.bots[1].cargo===0);
    assert.equal(state(r).ore,200);assert.equal(state(r).localSpent,60);assert.equal(state(r).delivered,40);await r.close();
  });
  await test('completion recovers source stock and its freight once while other freight returns to its surviving source',async()=>{
    const r=await fresh(),world=state(r);world.bots.length=1;const site=building(world),child=building(world,3,1,16,22);
    setWorker(world,0,{x:12,y:22});await restoreColony(r,world);await step(r);
    await fixtureCall(r,'scavenge-building',[12,22]);await until(r,w=>w.bots[0].job===17);
    const loaded=state(r);loaded.bots[0].timer=1;withdrawReserves(loaded,64);
    loaded.buildings.find(b=>b.id===site.id).stock=32;loaded.rails.find(rail=>rail.source===site.id).cargo=16;
    loaded.rails.find(rail=>rail.source===child.id).cargo=16;await restoreColony(r,loaded);await step(r);
    const done=state(r);assert.equal(done.delivered,loaded.delivered+48);assert.equal(done.ore,loaded.ore+48+5);
    assert.equal(done.buildings.find(b=>b.id===child.id).stock,16);assert.equal(done.lostOre,0);
    await step(r,40);assert.equal(state(r).delivered,loaded.delivered+64);assert.equal(state(r).ore,loaded.ore+64+5);
    await r.restore(1,r.snapshot(1));await r.close();
  });
  await test('demolition preserves loaded ore and paid local kits through completion or later cancellation',async()=>{
    for(const mode of ['ore','kit','cancelled-kit']) {
      const paidKit=mode!=='ore',cancel=mode==='cancelled-kit';
      const r=await fresh(),world=state(r),site=building(world,3,cancel?3:1,12,22,cancel?75:0);
      world.bots.length=2;setWorker(world,0,{x:12,y:22});
      let project;
      if(paidKit) {
        project=building(world,3,1,18,22,25);project.stage=1;project.source=site.id;
        setWorker(world,1,{x:14,y:22,job:3,target:project.id,cargo:25,source:site.id,path:[15,16,17,18].map(x=>x+22*48)});
      } else {
        withdrawReserves(world,16);
        setWorker(world,1,{x:18,y:22,job:2,target:site.id,cargo:16,path:[17,16,15,14,13,12].map(x=>x+22*48)});
      }
      await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,22]);assert.equal(state(r).notice,44);
      await step(r);const working=state(r);working.bots[0].timer=1;await restoreColony(r,working);await step(r);
      assert.equal(state(r).buildings.some(b=>b.id===site.id),false);assert.equal(state(r).bots[1].cargo,paidKit?25:16);
      await r.restore(1,r.snapshot(1));
      if(cancel) {
        assert.equal(state(r).localSpent,85);assert.equal(state(r).delivered,15);
        assert.equal(state(r).bots[1].source,site.id);await fixtureCall(r,'cancel-building',[18,22]);
        await until(r,w=>w.bots[1].cargo===0);assert.equal(state(r).localSpent,60);assert.equal(state(r).delivered,40);
      } else if(paidKit)await until(r,w=>w.buildings.find(b=>b.id===project.id)?.stage===2);
      else await until(r,w=>w.delivered===world.delivered+16);
      assert.equal(state(r).ore,world.ore+(cancel?40:paidKit?5:21));assert.equal(state(r).lostOre,0);await r.close();
    }
  });
  await test('pause, reload, duplicate orders and explicit cancellation cannot repeat or accelerate demolition',async()=>{
    const r=await fresh(),world=state(r);building(world);setWorker(world,0,{x:12,y:22});await restoreColony(r,world);
    await fixtureCall(r,'scavenge-building',[12,22]);await fixtureCall(r,'scavenge-building',[12,22]);assert.equal(state(r).notice,41);
    assert.equal(state(r).bots.filter(b=>b.job===16||b.job===17).length,1);
    await fixtureCall(r,'upgrade',[12,22]);assert.equal(state(r).notice,41);
    await fixtureCall(r,'relocate-building',[12+22*48,13+22*48]);assert.equal(state(r).notice,41);
    await fixtureCall(r,'pause-colony',[1]);const saved=r.snapshot(1);await step(r,40);assert.deepEqual(r.snapshot(1),saved);
    await r.restore(1,saved);await fixtureCall(r,'pause-colony',[0]);await step(r,5);
    const midway=r.snapshot(1);await r.restore(1,midway);assert.deepEqual(r.snapshot(1),midway);
    await fixtureCall(r,'cancel-building',[12,22]);assert.equal(state(r).notice,46);await step(r,30);
    assert.equal(state(r).buildings.length,1);assert.equal(state(r).ore,world.ore);await r.close();
  });
  await test('enemy destruction and worker death cancel demolition without a structural refund',async()=>{
    for(const targetBuilding of [true,false]) {
      const r=await fresh(),world=state(r),site=building(world);setWorker(world,0,{x:12,y:22,hp:7});
      if(targetBuilding)site.hp=7;await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,22]);await step(r);
      const working=state(r);working.tick=9;working.lastRevealTick=-100;await restoreColony(r,working);
      if(targetBuilding){await addEnemy(r,{x:12,y:22,target:site.id});await step(r);}
      else await settleWorker(r,working.bots[0].id);
      const attacked=state(r);assert.equal(attacked.ore,world.ore);assert.equal(attacked.spent,world.spent);
      if(targetBuilding)assert.equal(attacked.buildings.length,0);else assert.equal(attacked.casualties,1);
      await r.restore(1,r.snapshot(1));attacked.enemies=[];await restoreColony(r,attacked);await step(r,40);
      assert.equal(state(r).ore,world.ore);await r.close();
    }
  });
  await test('captured Scavenge flights land safely after either endpoint is destroyed and refund only a surviving target',async()=>{
    for(const destroyTarget of [true,false]) {
      const r=await fresh(),world=state(r);world.bots.length=1;
      const departure=building(world),target=building(world,3,1,16,22),landing=pixelAt(world,16,22);
      setWorker(world,0,{x:12,y:22});await restoreColony(r,world);await step(r);
      await fixtureCall(r,'scavenge-building',[16,22]);assert.equal(state(r).notice,44);await step(r);
      assert.equal(state(r).bots[0].flight.length,1);
      const flying=state(r),id=destroyTarget?target.id:departure.id;
      flying.buildings.find(b=>b.id===id).hp=7;flying.tick=9;flying.lastRevealTick=-100;await restoreColony(r,flying);
      await addEnemy(r,{x:destroyTarget?16:12,y:22,target:id});await step(r);const attacked=state(r);
      assert.equal(attacked.buildings.some(b=>b.id===id),false);assert.equal(attacked.bots[0].flight.length,1);
      assert.equal(attacked.ore,world.ore);attacked.enemies=[];await restoreColony(r,attacked);
      await until(r,w=>w.bots[0].flight.length===0);const landed=state(r).bots[0];
      assert.deepEqual([landed.x,landed.y],[landing.x,landing.y]);assert.equal(state(r).ore,world.ore);
      await step(r,80);const done=state(r),refund=destroyTarget?0:5;
      assert.equal(done.ore,world.ore+refund);assert.equal(done.spent,world.spent-refund);
      assert.equal(done.bots[0].flight.length,0);assert.equal([16,17].includes(done.bots[0].job),false);
      await step(r,20);assert.equal(state(r).ore,done.ore);await r.close();
    }
  });
  await test('nearby enemies do not interrupt paid demolition or reset its work timer',async()=>{
    const r=await fresh(),world=state(r);world.bots.length=1;building(world);setWorker(world,0,{x:12,y:22});
    await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[12,22]);await step(r,6);
    assert.equal(state(r).bots[0].timer,15);await addEnemy(r,{x:13,y:22,hp:80});await step(r);
    const working=state(r);assert.equal(working.bots[0].job,17);assert.equal(working.bots[0].timer,14);
    assert.equal(working.bots[0].hp,14);assert.equal(working.ore,world.ore);
    await step(r,14);assert.equal(state(r).ore,world.ore+5);assert.equal(state(r).buildings.length,0);
    assert.equal(state(r).casualties,0);await step(r,5);assert.equal(state(r).ore,world.ore+5);await r.close();
  });
  await test('malformed demolition claims reject atomically without replacing the saved colony',async()=>{
    const r=await fresh(),world=state(r);building(world);setWorker(world,0,{x:12,y:22});await restoreColony(r,world);
    await fixtureCall(r,'scavenge-building',[12,22]);await step(r);const saved=r.snapshot(1);
    for(const edit of [w=>w.bots[0].cargo=1,w=>w.bots[0].timer=0,w=>w.bots[0].timer=21,
      w=>w.bots[0].order=w.buildings[0].id,w=>w.bots[0].source=w.buildings[0].id,w=>w.bots[0].x+=40,
      w=>{w.bots[1]={...w.bots[0],id:w.bots[1].id};},w=>{w.buildings[0].stage=4;w.spent+=25;w.ore-=25;}]) {
      const invalid=colony(saved);edit(invalid);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('the hub, pending work, uncollected supply reservations and unavailable workers reject Scavenge explicitly',async()=>{
    const r=await fresh(),world=state(r),source=building(world);await restoreColony(r,world);
    await fixtureCall(r,'scavenge-building',[8,22]);assert.equal(state(r).notice,40);
    const pending=state(r);pending.buildings[0].stage=4;pending.spent+=25;pending.ore-=25;await restoreColony(r,pending);
    await fixtureCall(r,'scavenge-building',[12,22]);assert.equal(state(r).notice,40);
    await restoreColony(r,world);const reserved=state(r),project=building(reserved,2,1,14,24,50);
    project.stage=0;project.source=source.id;await restoreColony(r,reserved);
    await fixtureCall(r,'scavenge-building',[12,22]);assert.equal(state(r).notice,43);
    const unavailable=world;unavailable.bots.length=1;withdrawReserves(unavailable,16);
    setWorker(unavailable,0,{job:2,cargo:16});await restoreColony(r,unavailable);
    await fixtureCall(r,'scavenge-building',[12,22]);assert.equal(state(r).notice,42);await r.close();
  });
}
if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkScavenge(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} Scavenge integration groups passed`);
}
